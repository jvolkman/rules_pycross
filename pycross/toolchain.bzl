"""This module implements the language-specific toolchain rule.
"""

load("@rules_python//python:defs.bzl", "PyRuntimeInfo")

PycrossBuildExecRuntimeInfo = provider(
    doc = "Extended information about a (exec, target) Python interpreter pair.",
    fields = {
        "exec_python_files": "A depset containing all files for the exec interpreter.",
        "exec_python_files_to_run": "Optional FilesToRunProvider for the exec interpreter.",
        "exec_python_executable": "The path to the exec Python interpreter, either absolute or relative to execroot.",
        "target_python_files": "A depset containing all files for the target interpreter.",
        "target_python_files_to_run": "Optional FilesToRunProvider for the target interpreter.",
        "target_python_executable": "The path to the target Python interpreter, either absolute or relative to execroot.",
        "target_sys_path": "An array of system path directories (i.e., the value of sys.path from `python -m site`).",
    },
)

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

    pycross_info = PycrossBuildExecRuntimeInfo(
        exec_python_files = exec_py_info.files,
        exec_python_files_to_run = getattr(exec_py_info, "interpreter_files_to_run", None),
        exec_python_executable = _python_executable(exec_py_info),
        target_python_files = target_py_info.files,
        target_python_files_to_run = getattr(target_py_info, "interpreter_files_to_run", None),
        target_python_executable = _python_executable(target_py_info),
        target_sys_path = None,
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
            cfg = "exec",
        ),
    },
)

def config_compatible(config_setting_target):
    return select(
        {
            config_setting_target: [],
            "//conditions:default": ["@platforms//:incompatible"],
        },
    )
