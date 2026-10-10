"""This module implements the language-specific toolchain rule.
"""

load("@rules_python//python:defs.bzl", "PyRuntimeInfo")
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")

PycrossBuildExecRuntimeInfo = provider(
    doc = "Extended information about a (exec, target) Python interpreter pair.",
    fields = {
        "exec_python_files": "A depset containing all files for the exec interpreter.",
        "exec_python_compile_files": "A depset containing the subset of exec interpreter files needed for .pyc bytecode compilation.",
        "exec_python_files_to_run": "Optional FilesToRunProvider for the exec interpreter.",
        "exec_python_executable": "The path to the exec Python interpreter, either absolute or relative to execroot.",
        "target_python_files": "A depset containing all files for the target interpreter.",
        "target_python_files_to_run": "Optional FilesToRunProvider for the target interpreter.",
        "target_python_executable": "The path to the target Python interpreter, either absolute or relative to execroot.",
    },
)

_EXCLUDED_STDLIB_DIRS = {
    "distutils": True,
    "ensurepip": True,
    "idlelib": True,
    "lib2to3": True,
    "site-packages": True,
    "test": True,
    "tkinter": True,
    "turtledemo": True,
}

def _is_compile_interpreter_path(path):
    """Return True if an interpreter file path should be staged for .pyc compilation."""
    if path.startswith("../"):
        _, _, path = path[3:].partition("/")
    parts = path.split("/")
    if len(parts) < 2:
        return True
    top = parts[0]
    if top in ("include", "Include", "tcl", "tk"):
        return False
    if top == "lib":
        if len(parts) >= 3 and (
            parts[1].startswith("tcl") or
            parts[1].startswith("tk") or
            parts[1].startswith("Tix")
        ):
            return False
        if len(parts) >= 4 and parts[1].startswith("python3."):
            sub = parts[2]
            if sub in _EXCLUDED_STDLIB_DIRS or sub.startswith("config-"):
                return False
    elif top == "Lib" and len(parts) >= 3:
        sub = parts[1]
        if sub in _EXCLUDED_STDLIB_DIRS or sub.startswith("config-"):
            return False
    return True

# Visible for testing
is_compile_interpreter_path_for_testing = _is_compile_interpreter_path

def _python_executable(runtime):
    """Resolve the Python executable path from a PyRuntimeInfo.

    Prefers interpreter_files_to_run (rules_python >= 1.x) over
    interpreter_path and interpreter.path for runtimes that expose
    a launcher or wrapper executable.
    """
    files_to_run = getattr(runtime, "interpreter_files_to_run", None)
    if files_to_run and files_to_run.executable:
        return files_to_run.executable.path
    if runtime.interpreter_path:
        return runtime.interpreter_path
    return runtime.interpreter.path

def _pycross_hermetic_toolchain_impl(ctx):
    target_py_info = ctx.attr.target_interpreter[PyRuntimeInfo]

    # Resolve exec interpreter (can be direct PyRuntimeInfo or current_py_toolchain)
    exec_interpreter = ctx.attr.exec_interpreter
    if type(exec_interpreter) == "list":
        exec_interpreter = exec_interpreter[0]
    if PyRuntimeInfo in exec_interpreter:
        exec_py_info = exec_interpreter[PyRuntimeInfo]
    elif platform_common.ToolchainInfo in exec_interpreter:
        exec_tc = exec_interpreter[platform_common.ToolchainInfo]
        if hasattr(exec_tc, "py3_runtime") and exec_tc.py3_runtime:
            exec_py_info = exec_tc.py3_runtime
        else:
            fail("exec_interpreter toolchain does not provide py3_runtime")
    else:
        fail("exec_interpreter must provide PyRuntimeInfo or ToolchainInfo")

    exec_python_compile_files = depset([
        f
        for f in exec_py_info.files.to_list()
        if _is_compile_interpreter_path(f.short_path)
    ]) if exec_py_info.files else depset()

    pycross_info = PycrossBuildExecRuntimeInfo(
        exec_python_files = exec_py_info.files,
        exec_python_compile_files = exec_python_compile_files,
        exec_python_files_to_run = getattr(exec_py_info, "interpreter_files_to_run", None),
        exec_python_executable = _python_executable(exec_py_info),
        target_python_files = target_py_info.files,
        target_python_files_to_run = getattr(target_py_info, "interpreter_files_to_run", None),
        target_python_executable = _python_executable(target_py_info),
    )

    return [
        platform_common.ToolchainInfo(
            pycross_info = pycross_info,
        ),
    ]

pycross_hermetic_toolchain = rule(
    implementation = _pycross_hermetic_toolchain_impl,
    attrs = {
        "target_interpreter": attr.label(
            doc = "The target Python interpreter (PyRuntimeInfo).",
            mandatory = True,
            providers = [PyRuntimeInfo],
            cfg = "target",
        ),
        "exec_interpreter": attr.label(
            doc = "The execution Python interpreter (can be PyRuntimeInfo or a toolchain alias).",
            mandatory = True,
            cfg = pycross_exec_platform_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
