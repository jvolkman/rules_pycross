"""Internal repo"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@toml.bzl", "toml")
load(":lock_attrs.bzl", "CONFIGURE_TOOLCHAINS_ATTRS")
load(":repo_venv_utils.bzl", "create_venv", "get_venv_python_executable", "install_venv_wheels")

INTERNAL_REPO_NAME = "rules_pycross_internal"

_root_build = """\
package(default_visibility = ["//visibility:public"])

alias(
    name = "installer_whl",
    actual = ":{installer_whl}",
)

alias(
    name = "patch_ng_whl",
    actual = ":{patch_ng_whl}",
)

exports_files([
    "python.bzl",
] + {wheel_exports})
"""

_python_bzl = """\
load("@rules_python//python:defs.bzl", _py_library = "py_library")
load("{python_defs}", _py_binary = "py_binary", _py_test = "py_test")

py_binary = _py_binary
py_library = _py_library
py_test = _py_test
"""

def exec_internal_tool(rctx, tool, args, *, flagfile_param = "--flagfile", flagfile_threshold = 1000, quiet = False):
    """
    Execute a script under //pycross/private/tools.

    Args:
      rctx: repository context
      tool: the script to execute
      args: a list of args to pass to the script
      flagfile_param: the parameter name used when dumping arguments to a flag file
      flagfile_threshold: use a flag file if len(args) >= this value
      quiet: The quiet value to pass to rctx.execute.

    Returns:
      exec_result
    """
    venv_path = rctx.path(Label("@{}//exec_venv:BUILD.bazel".format(INTERNAL_REPO_NAME))).dirname
    python_exe = get_venv_python_executable(venv_path)

    # Setup the flagfile if necessary
    flagfile = None
    if flagfile_param and len(args) >= flagfile_threshold:
        flagfile_data = "\n".join([shell.quote(str(arg)) for arg in args])
        flagfile = rctx.path("_internal_flagfile_%s.params" % hash(flagfile_data))
        if flagfile.exists:
            rctx.delete(flagfile)
        rctx.file(flagfile, flagfile_data)
        tool_args = ["--flagfile", str(flagfile)]
    else:
        tool_args = args

    tool_path = rctx.path(tool)

    # Watch the tool script so Bazel invalidates the cached repo when it changes.
    # Without this, edits to tools like inspect_package.py require `bazel clean --expunge`.
    if hasattr(rctx, "watch"):
        rctx.watch(tool_path)

    all_args = [str(python_exe), str(tool_path)] + tool_args
    result = rctx.execute(all_args, quiet = quiet)

    # Clean up the flagfile
    if flagfile and flagfile.exists:
        rctx.delete(flagfile)

    if result.return_code:
        fail("Internal command failed: {}\n{}".format(all_args, result.stderr))

    return result

def _get_python_interpreter_attr(rctx):
    """A helper function for getting the `python_interpreter` attribute or its default.

    Args:
      rctx (repository_ctx): Handle to the rule repository context.

    Returns:
      str: The attribute value or its default.
    """
    if rctx.attr.python_interpreter:
        return rctx.attr.python_interpreter

    if "win" in rctx.os.name:
        return "python.exe"
    else:
        return "python3"

def _resolve_python_interpreter(rctx):
    """Helper function to find the python interpreter from the common attributes

    Args:
      rctx: Handle to the rule repository context.

    Returns:
      Python interpreter path.
    """
    python_interpreter = _get_python_interpreter_attr(rctx)

    if rctx.attr.python_interpreter_target != None:
        python_interpreter = rctx.path(rctx.attr.python_interpreter_target)
        if hasattr(rctx, "watch"):
            rctx.watch(python_interpreter)
    elif "/" not in python_interpreter:
        found_python_interpreter = rctx.which(python_interpreter)
        if not found_python_interpreter:
            fail("python interpreter `{}` not found in PATH".format(python_interpreter))
        python_interpreter = found_python_interpreter

    return python_interpreter.realpath

def _installer_whl(wheels):
    for filename in wheels:
        if filename.startswith("installer-"):
            return filename
    fail("Unable to find `installer` wheel in lock file.")

def _patch_ng_whl(wheels):
    for filename in wheels:
        if filename.startswith("patch_ng-") or filename.startswith("patch-ng-"):
            return filename
    fail("Unable to find `patch-ng` wheel in lock file.")

def _defaults_bzl(rctx):
    lines = []
    for key in CONFIGURE_TOOLCHAINS_ATTRS:
        val = getattr(rctx.attr, key)

        lines.append("{} = {}".format(key, repr(val)))

    return "\n".join(lines) + "\n"

def _sanitize_name(name):
    return name.lower().replace("-", "_").replace("@", "_").replace("+", "_").replace(".", "_").replace("[", "_").replace("]", "_")

def _marker_evaluator_name(marker_str):
    san = _sanitize_name(marker_str.replace(" ", "").replace("\"", "").replace("'", ""))
    if len(san) > 40:
        san = san[:40]
    return "_marker_eval_{}_{}".format(san, hash(marker_str))

def _pycross_internal_repo_impl(rctx):
    # 1. Read and parse the TOML lock
    deps_toml_path = rctx.path(Label("//pycross/private:pycross_deps.toml"))
    deps_data = toml.decode(rctx.read(deps_toml_path))

    # 2. Download all the wheels
    wheel_paths = []
    wheel_filenames = []
    download_handles = []
    for pkg in deps_data["packages"].values():
        filename = pkg["filename"]
        out_path = rctx.path(filename)
        handle = rctx.download(
            url = pkg["url"],
            output = out_path,
            sha256 = pkg["sha256"],
            block = False,
        )
        download_handles.append(handle)
        wheel_filenames.append(filename)
        wheel_paths.append(out_path)

    rctx.report_progress("Downloading {} internal wheels".format(len(deps_data["packages"])))
    for handle in download_handles:
        handle.wait()

    python_executable = _resolve_python_interpreter(rctx)
    pycross_path = rctx.path(Label("//:BUILD.bazel")).dirname

    venv_path = rctx.path("exec_venv")
    installer_whl = _installer_whl(wheel_filenames)
    rctx.report_progress("Creating internal virtual environment")
    create_venv(rctx, python_executable, venv_path, [pycross_path, pycross_path.get_child("pycross", "private", "tools")])
    rctx.report_progress("Installing {} internal wheels".format(len(wheel_paths)))
    install_venv_wheels(rctx, venv_path, installer_whl, wheel_paths)

    # 2. Write the target definitions
    deps_build_lines = [
        'load("@rules_pycross//pycross:defs.bzl", "pycross_pep508_evaluator", "pycross_wheel_library")',
        'load("@rules_pycross//pycross/private:pep508_marker_values.bzl", "OS_NAME_VALUES", "SYS_PLATFORM_VALUES", "PLATFORM_SYSTEM_VALUES", "PLATFORM_MACHINE_VALUES")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    # Collect unique markers
    unique_markers = {}
    for pkg in deps_data["packages"].values():
        for dep in pkg.get("deps", []):
            if "marker" in dep:
                unique_markers[dep["marker"]] = True

    # Write marker evaluators
    for marker_str in sorted(unique_markers.keys()):
        eval_name = _marker_evaluator_name(marker_str)

        deps_build_lines.extend([
            "pycross_pep508_evaluator(",
            '    name = "{}",'.format(eval_name),
            '    expr = "{}",'.format(marker_str.replace('"', '\\"')),
            "    sys_platform = select(SYS_PLATFORM_VALUES),",
            "    os_name = select(OS_NAME_VALUES),",
            "    platform_system = select(PLATFORM_SYSTEM_VALUES),",
            "    platform_machine = select(PLATFORM_MACHINE_VALUES),",
            ")",
            "",
            "config_setting(",
            '    name = "{}_match",'.format(eval_name),
            "    flag_values = {",
            '        ":{}": "true",'.format(eval_name),
            "    },",
            ")",
            "",
        ])

    # Config setting
    deps_build_lines.extend([
        "config_setting(",
        '    name = "_env_rules_pycross_deps_target_env",',
        ")",
        "",
    ])

    # Pins
    for pin_name, pin_target in sorted(deps_data["pins"].items()):
        deps_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = ":" + "{}",'.format(pin_target),
            ")",
            "",
        ])

    # Packages
    for pkg_version, pkg in sorted(deps_data["packages"].items()):
        # Each package needs an alias and a wheel library
        wheel_target_name = "_wheel_{}".format(pkg_version)
        deps_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(wheel_target_name),
            '    actual = "//:{}",'.format(pkg["filename"]),
            ")",
            "",
        ])

        unconditional = []
        conditional = []
        for dep in pkg.get("deps", []):
            if "marker" in dep:
                conditional.append(dep)
            else:
                unconditional.append(dep["key"])

        deps_val = []
        for dep_key in sorted(unconditional):
            deps_val.append('":{}"'.format(dep_key))

        deps_expr = "[]"
        if unconditional:
            deps_expr = "[{}]".format(", ".join(deps_val))

        for dep in sorted(conditional, key = lambda x: x["key"]):
            eval_name = _marker_evaluator_name(dep["marker"])
            deps_expr += " + select({{\":{}_match\": [\":{}\"], \"//conditions:default\": []}})".format(eval_name, dep["key"])

        deps_build_lines.extend([
            "pycross_wheel_library(",
            '    name = "{}",'.format(pkg_version),
            '    wheel = ":{}",'.format(wheel_target_name),
        ])
        if unconditional or conditional:
            deps_build_lines.append("    deps = {},".format(deps_expr))
        deps_build_lines.append(")")
        deps_build_lines.append("")

    rctx.file("deps/BUILD.bazel", "\n".join(deps_build_lines))

    # python.bzl
    if rctx.attr.python_defs_file:
        python_defs = rctx.attr.python_defs_file
    else:
        python_defs = Label("@rules_python//python:defs.bzl")
    rctx.file("python.bzl", _python_bzl.format(python_defs = python_defs))

    # defaults.bzl has been moved to rules_pycross_internal_config

    # Root build file
    rctx.file("BUILD.bazel", _root_build.format(
        installer_whl = _installer_whl(wheel_filenames),
        patch_ng_whl = _patch_ng_whl(wheel_filenames),
        wheel_exports = repr(wheel_filenames),
    ))

pycross_internal_repo = repository_rule(
    implementation = _pycross_internal_repo_impl,
    attrs = {
        "python_interpreter_target": attr.label(
            allow_single_file = True,
        ),
        "python_defs_file": attr.label(
            allow_single_file = True,
        ),
        "python_interpreter": attr.string(),
    },
)

def _pycross_internal_config_repo_impl(rctx):
    rctx.file("BUILD.bazel", 'exports_files(["defaults.bzl"])')
    rctx.file("defaults.bzl", _defaults_bzl(rctx))

pycross_internal_config_repo = repository_rule(
    implementation = _pycross_internal_config_repo_impl,
    attrs = CONFIGURE_TOOLCHAINS_ATTRS,
)

def create_internal_repo(toolchains_attrs, **kwargs):
    pycross_internal_repo(
        name = INTERNAL_REPO_NAME,
        **kwargs
    )
    pycross_internal_config_repo(
        name = "rules_pycross_internal_config",
        **toolchains_attrs
    )
