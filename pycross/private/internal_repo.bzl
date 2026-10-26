"""Internal repo"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":lock_attrs.bzl", "CONFIGURE_TOOLCHAINS_ATTRS")

INTERNAL_REPO_NAME = "rules_pycross_internal"

_python_bzl = """\
load("@rules_python//python:defs.bzl", _py_library = "py_library")
load("{python_defs}", _py_binary = "py_binary", _py_test = "py_test")

_GLIBC = {{"@rules_python//python/config_settings:py_linux_libc": "glibc"}}

def py_binary(name, config_settings = None, **kwargs):
    # Internal tools run on the (glibc) exec host, even for musl targets.
    settings = dict(_GLIBC)
    settings.update(config_settings or {{}})
    _py_binary(name = name, config_settings = settings, **kwargs)

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

    # Stdlib-only modules that repo-time tools may import (e.g. inspect_package applying
    # pre_build_patches).
    module_files = [
        Label("//pycross/private/patching:pycross_patch.py"),
        Label("//pycross/private/third_party/rules_python_patch:unified_patch.py"),
    ]
    module_dirs = [str(rctx.path(f).dirname) for f in module_files]

    # rctx.path() doesn't record its file as an input, so changes to the tool (or to the modules
    # it may import) wouldn't re-run the calling repo rule, and the repo contents cache would
    # keep serving stale results. Watch them explicitly.
    if hasattr(rctx, "watch"):
        rctx.watch(tool)
        for f in module_files:
            rctx.watch(f)

    wrapper_script = """
import runpy
import sys

tool_path = {tool}
sys.path[0:0] = {module_dirs}
sys.argv = [tool_path] + sys.argv[1:]

runpy.run_path(tool_path, run_name="__main__")
"""

    wrapper_file = rctx.path("_internal_wrapper.py")
    rctx.file(wrapper_file, wrapper_script.format(
        module_dirs = repr(module_dirs),
        tool = repr(str(rctx.path(tool))),
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

def _resolve_python_interpreter(rctx):
    """Resolve the configured python_interpreter_target path."""
    python_interpreter = rctx.path(rctx.attr.python_interpreter_target)
    if hasattr(rctx, "watch"):
        rctx.watch(python_interpreter)

    # Keep the logical external-repository path. Resolving it can embed a
    # transient repository contents-cache UUID in generated files.
    return python_interpreter

def _interpreter_identity(rctx, python_executable):
    """Describes the interpreter without referring to a host-specific path."""
    location = str(rctx.attr.python_interpreter_target)

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
    },
)

def _pycross_internal_config_repo_impl(rctx):
    rctx.file("BUILD.bazel", """\
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

exports_files(["defaults.bzl"])

bzl_library(
    name = "defaults",
    srcs = ["defaults.bzl"],
    visibility = ["//visibility:public"],
)
""")
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
