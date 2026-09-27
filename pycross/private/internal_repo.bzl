"""Internal repo"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":lock_attrs.bzl", "CONFIGURE_TOOLCHAINS_ATTRS")

INTERNAL_REPO_NAME = "rules_pycross_internal"

_python_bzl = """\
load("@rules_python//python:defs.bzl", _py_library = "py_library")
load("{python_defs}", _py_binary = "py_binary", _py_test = "py_test")

py_binary = _py_binary
py_library = _py_library
py_test = _py_test
"""

def exec_internal_tool(rctx, tool, args, *, flagfile_param = "--flagfile", flagfile_threshold = 1000, quiet = False, extra_wheels = []):
    """
    Execute a script under //pycross/private/tools.

    Args:
      rctx: repository context
      tool: the script to execute
      args: a list of args to pass to the script
      flagfile_param: the parameter name used when dumping arguments to a flag file
      flagfile_threshold: use a flag file if len(args) >= this value
      quiet: The quiet value to pass to rctx.execute.
      extra_wheels: a list of wheel files or directories to add to sys.path

    Returns:
      exec_result
    """

    # interpreter_path.txt holds host-specific paths, so recording it as an
    # input would make every caller's repo contents cache entry specific to
    # one machine and output base. Record the machine-independent
    # interpreter_identity.txt instead, so that callers still re-run when
    # the interpreter changes. rctx.path(Label) records the file it resolves,
    # so reach interpreter_path.txt as a sibling instead.
    interpreter_identity_file = rctx.path(Label("@{}//:interpreter_identity.txt".format(INTERNAL_REPO_NAME)))
    rctx.read(interpreter_identity_file)
    interpreter_path_file = interpreter_identity_file.dirname.get_child("interpreter_path.txt")
    python_exe = rctx.read(interpreter_path_file, watch = "no").strip()

    # Setup the flagfile if necessary
    flagfile = None
    if flagfile_param and len(args) >= flagfile_threshold:
        flagfile_data = "\n".join([shell.quote(str(arg)) for arg in args])
        flagfile = rctx.path("_internal_flagfile_%s.params" % hash(flagfile_data))
        if flagfile.exists:
            rctx.delete(flagfile)
        rctx.file(flagfile, flagfile_data)
        args = [flagfile_param, str(flagfile)]

    wrapper_script = """
import sys
import os
import glob

extra_wheels = {extra_wheels}
paths_to_add = []
for w in extra_wheels:
    if os.path.isdir(w):
        paths_to_add.extend(glob.glob(os.path.join(w, "*.whl")))
    elif w.endswith(".whl"):
        paths_to_add.append(w)

sys.path = paths_to_add + sys.path

sys.argv = ["{tool}"] + sys.argv[1:]

import runpy
runpy.run_path("{tool}", run_name="__main__")
"""

    wrapper_file = rctx.path("_internal_wrapper.py")
    rctx.file(wrapper_file, wrapper_script.format(
        extra_wheels = repr([str(rctx.path(w)) for w in extra_wheels]),
        tool = str(rctx.path(tool)),
    ))

    result = rctx.execute(
        [python_exe, str(wrapper_file)] + args,
        quiet = quiet,
    )

    # These files embed host-specific paths and are not needed after execution;
    # leaving them behind would make the calling repo's contents host-specific.
    rctx.delete(wrapper_file)
    if flagfile:
        rctx.delete(flagfile)

    if result.return_code != 0:
        fail("Failed to execute internal tool: {}\n{}".format(tool, result.stderr))

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

def _interpreter_identity(rctx, python_executable):
    """Describes the interpreter without referring to a host-specific path.

    Args:
      rctx: Handle to the rule repository context.
      python_executable: The resolved interpreter path.

    Returns:
      str: The interpreter's label (or path, if found on PATH) and version.
    """
    if rctx.attr.python_interpreter_target != None:
        # A canonical label is the same on every machine.
        location = str(rctx.attr.python_interpreter_target)
    else:
        # An interpreter found on PATH is host-specific anyway.
        location = str(python_executable)

    # The label does not change across patch releases, so include the version.
    result = rctx.execute([
        python_executable,
        "-c",
        "import sys; print(sys.implementation.name, *sys.version_info)",
    ])
    if result.return_code != 0:
        fail("Failed to query python interpreter {}: {}".format(python_executable, result.stderr))

    return "{}\n{}\n".format(location, result.stdout.strip())

def _defaults_bzl(rctx):
    lines = []
    for key in CONFIGURE_TOOLCHAINS_ATTRS:
        val = getattr(rctx.attr, key)

        lines.append("{} = {}".format(key, repr(val)))

    return "\n".join(lines) + "\n"

def _pycross_internal_repo_impl(rctx):
    python_executable = _resolve_python_interpreter(rctx)
    rctx.file("interpreter_path.txt", str(python_executable))
    rctx.file("interpreter_identity.txt", _interpreter_identity(rctx, python_executable))

    # python.bzl
    if rctx.attr.python_defs_file:
        python_defs = rctx.attr.python_defs_file
    else:
        python_defs = Label("@rules_python//python:defs.bzl")
    rctx.file("python.bzl", _python_bzl.format(python_defs = python_defs))

    # Root BUILD.bazel
    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "python.bzl",
    "interpreter_identity.txt",
    "interpreter_path.txt",
])
""")

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
