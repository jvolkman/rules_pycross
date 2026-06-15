"""Internal repo"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@toml.bzl", "toml")
load(":lock_attrs.bzl", "CREATE_ENVIRONMENTS_ATTRS", "REGISTER_TOOLCHAINS_ATTRS")
load(":repo_venv_utils.bzl", "create_venv", "get_venv_python_executable", "install_venv_wheels")

INTERNAL_REPO_NAME = "rules_pycross_internal"

_root_build = """\
package(default_visibility = ["//visibility:public"])

alias(
    name = "installer_whl",
    actual = "{installer_whl}",
)

alias(
    name = "patch_ng_whl",
    actual = "{patch_ng_whl}",
)

exports_files([
    "defaults.bzl",
    "python.bzl",
])
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

def _installer_whl(wheels, prefix):
    for repo_name, filename in wheels.items():
        if filename.startswith("installer-"):
            return Label("@@" + prefix + repo_name + "//file:" + filename)
    fail("Unable to find `installer` wheel in lock file.")

def _patch_ng_whl(wheels, prefix):
    for repo_name, filename in wheels.items():
        if filename.startswith("patch_ng-") or filename.startswith("patch-ng-"):
            return Label("@@" + prefix + repo_name + "//file:" + filename)
    fail("Unable to find `patch-ng` wheel in lock file.")

def _pip_whl(wheels, prefix):
    for repo_name, filename in wheels.items():
        if filename.startswith("pip-"):
            return Label("@@" + prefix + repo_name + "//file:" + filename)
    fail("Unable to find `pip` wheel in lock file.")

def _defaults_bzl(rctx):
    lines = []
    for key in CREATE_ENVIRONMENTS_ATTRS | REGISTER_TOOLCHAINS_ATTRS:
        val = getattr(rctx.attr, key)

        lines.append("{} = {}".format(key, repr(val)))

    return "\n".join(lines) + "\n"

def _pycross_internal_repo_impl(rctx):
    # Extract Bzlmod extension repository prefix from rctx.name
    # (e.g., "rules_pycross++pycross+" or "rules_pycross~1.0.0~pycross~")
    prefix = rctx.name.split("rules_pycross_internal")[0]

    python_executable = _resolve_python_interpreter(rctx)
    wheel_paths = sorted([rctx.path(Label("@@" + prefix + repo + "//file:" + file)) for repo, file in rctx.attr.wheels.items()], key = lambda k: str(k))
    pycross_path = rctx.path(Label("//:BUILD.bazel")).dirname

    venv_path = rctx.path("exec_venv")
    pip_whl = _pip_whl(rctx.attr.wheels, prefix)
    if rctx.attr.install_wheels:
        create_venv(rctx, python_executable, venv_path, [pycross_path])
        install_venv_wheels(rctx, venv_path, pip_whl, wheel_paths)
    else:
        create_venv(rctx, python_executable, venv_path, [pycross_path] + wheel_paths)

    # 1. Read and parse the TOML lock
    deps_toml_path = rctx.path(Label("//pycross/private:pycross_deps.toml"))
    deps_data = toml.decode(rctx.read(deps_toml_path))

    # 2. Write the target definitions
    deps_build_lines = [
        'load("@rules_pycross//pycross:defs.bzl", "pycross_wheel_library")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

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
            '    actual = "@{}//file",'.format(pkg["repo_name"]),
            ")",
            "",
        ])

        deps = []
        for dep in pkg.get("deps", []):
            deps.append(":{}".format(dep))

        deps_build_lines.extend([
            "pycross_wheel_library(",
            '    name = "{}",'.format(pkg_version),
            '    wheel = ":{}",'.format(wheel_target_name),
        ])
        if deps:
            deps_build_lines.append("    deps = {},".format(deps))
        deps_build_lines.append(")")
        deps_build_lines.append("")

    rctx.file("deps/BUILD.bazel", "\n".join(deps_build_lines))

    # python.bzl
    if rctx.attr.python_defs_file:
        python_defs = rctx.attr.python_defs_file
    else:
        python_defs = Label("@rules_python//python:defs.bzl")
    rctx.file("python.bzl", _python_bzl.format(python_defs = python_defs))

    # defaults.bzl
    rctx.file("defaults.bzl", _defaults_bzl(rctx))

    # Root build file
    rctx.file("BUILD.bazel", _root_build.format(
        installer_whl = _installer_whl(rctx.attr.wheels, prefix),
        patch_ng_whl = _patch_ng_whl(rctx.attr.wheels, prefix),
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
        "wheels": attr.string_dict(
            mandatory = True,
        ),
        "install_wheels": attr.bool(
            default = True,
        ),
    } | CREATE_ENVIRONMENTS_ATTRS | REGISTER_TOOLCHAINS_ATTRS,
)

def create_internal_repo(wheels = {}, **kwargs):
    pycross_internal_repo(
        name = INTERNAL_REPO_NAME,
        wheels = {wheel_label: wheel_name for wheel_name, wheel_label in wheels.items()},
        **kwargs
    )
