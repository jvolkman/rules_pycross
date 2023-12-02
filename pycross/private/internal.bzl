"""Internal repo"""

load(":repolib.bzl", "create_venv", "get_venv_python_executable", "install_venv_wheels")

INTERNAL_REPO_NAME = "rules_pycross_internal"
LOCK_FILES = {
    "build": "@jvolkman_rules_pycross//pycross/private:pycross_deps_build.lock.bzl",
    "core": "@jvolkman_rules_pycross//pycross/private:pycross_deps_core.lock.bzl",
    "repairwheel": "@jvolkman_rules_pycross//pycross/private:pycross_deps_repairwheel.lock.bzl",
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
    "defs.bzl",
])
"""

_defs_bzl = """\
# TODO
"""

def exec_internal_tool(rctx, tool, args):
    """
    Execute a script under //pycross/private/tools.

    Args:
      rctx: repository context
      tool: the script to execute
      args: a list of args to pass to the script

    Returns:
      exec_result
    """
    venv_path = rctx.path(Label("@{}//exec_venv:BUILD.bazel".format(INTERNAL_REPO_NAME))).dirname
    python_exe = get_venv_python_executable(venv_path)
    all_args = [str(python_exe), str(rctx.path(tool))] + args
    result = rctx.execute(all_args, quiet = False)
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

def _pycross_internal_repo_impl(rctx):
    python_executable = _resolve_python_interpreter(rctx)
    wheel_paths = sorted([rctx.path(w) for w in rctx.attr.wheels.keys()], key = lambda k: str(k))
    pycross_path = rctx.path(Label("@jvolkman_rules_pycross//:BUILD.bazel")).dirname

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
        _deps_build.format(lock = "@jvolkman_rules_pycross//pycross/private:pycross_deps.lock.bzl"),
    )

    # Root build file and defs
    venv_python_exe = "@{}//exec_venv:python".format(INTERNAL_REPO_NAME)
    rctx.file("BUILD.bazel", _root_build.format(installer_whl = _installer_whl(rctx.attr.wheels)))
    rctx.file("defs.bzl", _defs_bzl.format(venv_python_exe = venv_python_exe))

pycross_internal_repo = repository_rule(
    implementation = _pycross_internal_repo_impl,
    attrs = {
        "python_interpreter_target": attr.label(
            allow_single_file = True,
        ),
        "python_interpreter": attr.string(),
        "wheels": attr.label_keyed_string_dict(
            mandatory = True,
            allow_files = [".whl"],
        ),
        "install_wheels": attr.bool(
        ),
    },
)

def create_internal_repo(python_interpreter_target = None, python_interpreter = None, wheels = {}):
    pycross_internal_repo(
        name = INTERNAL_REPO_NAME,
        wheels = {Label(wheel_label): wheel_name for wheel_name, wheel_label in wheels.items()},
        python_interpreter = python_interpreter,
        python_interpreter_target = python_interpreter_target,
    )
