"""Internal repo"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":lock_attrs.bzl", "CREATE_ENVIRONMENTS_ATTRS", "REGISTER_TOOLCHAINS_ATTRS")
load(":repo_venv_utils.bzl", "create_venv", "get_venv_python_executable", "install_venv_wheels")

INTERNAL_REPO_NAME = "rules_pycross_internal"
LOCK_FILES = {
    "build": "//pycross/private:pycross_deps_build.lock.bzl",
    "core": "//pycross/private:pycross_deps_core.lock.bzl",
    "repairwheel": "//pycross/private:pycross_deps_repairwheel.lock.bzl",
}

_deps_build = """\
package(default_visibility = ["//visibility:public"])

load("{lock}", "targets")

targets()
"""

_root_build = """\
package(default_visibility = ["//visibility:public"])

alias(
    name = "installer_whl",
    actual = "{installer_whl}",
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

    all_args = [str(python_exe), str(rctx.path(tool))] + tool_args
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
    for label, name in wheels.items():
        if name.startswith("installer-"):
            return label
    fail("Unable to find `installer` wheel in lock file.")

def _pip_whl(wheels):
    for label, name in wheels.items():
        if name.startswith("pip-"):
            return label
    fail("Unable to find `pip` wheel in lock file.")

def _defaults_bzl(rctx):
    lines = []
    for key in CREATE_ENVIRONMENTS_ATTRS | REGISTER_TOOLCHAINS_ATTRS:
        val = getattr(rctx.attr, key)

        lines.append("{} = {}".format(key, repr(val)))

    return "\n".join(lines) + "\n"

def _pycross_internal_repo_impl(rctx):
    python_executable = _resolve_python_interpreter(rctx)
    wheel_paths = sorted([rctx.path(w) for w in rctx.attr.wheels.keys()], key = lambda k: str(k))
    pycross_path = rctx.path(Label("//:BUILD.bazel")).dirname

    venv_path = rctx.path("exec_venv")
    pip_whl = _pip_whl(rctx.attr.wheels)
    if rctx.attr.install_wheels:
        create_venv(rctx, python_executable, venv_path, [pycross_path])
        install_venv_wheels(rctx, venv_path, pip_whl, wheel_paths)
    else:
        create_venv(rctx, python_executable, venv_path, [pycross_path] + wheel_paths)

    # All deps
    rctx.file(
        "deps/BUILD.bazel",
        _deps_build.format(lock = Label("//pycross/private:pycross_deps.lock.bzl")),
    )

    # python.bzl
    if rctx.attr.python_defs_file:
        python_defs = rctx.attr.python_defs_file
    else:
        python_defs = Label("@rules_python//python:defs.bzl")
    rctx.file("python.bzl", _python_bzl.format(python_defs = python_defs))

    # defaults.bzl
    rctx.file("defaults.bzl", _defaults_bzl(rctx))

    # Root build file
    rctx.file("BUILD.bazel", _root_build.format(installer_whl = _installer_whl(rctx.attr.wheels)))

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
        "wheels": attr.label_keyed_string_dict(
            mandatory = True,
            allow_files = [".whl"],
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
