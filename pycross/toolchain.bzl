"""This module implements the language-specific toolchain rule.
"""
load("//pycross/private:providers.bzl", "PycrossTargetEnvironmentInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")

PycrossBuildExecRuntimeInfo = provider(
    doc = "Extended information about a (exec, target) Python interpreter pair.",
    fields = {
        "exec_python_files": "A depset containing all files for the exec interpreter.",
        "exec_python_executable": "The path to the exec Python interpreter, either absolute or relative to execroot.",
        "target_python_files": "A depset containing all files for the target interpreter.",
        "target_python_executable": "The path to the target Python interpreter, either absolute or relative to execroot.",
        "target_sys_path": "An array of system path directories (i.e., the value of sys.path from `python -m site`).",
        "target_environment": "The label of an associated PycrossTargetEnvironmentInfo target.",
    },
)

def _pycross_hermetic_toolchain_impl(ctx):
    exec_py_info = ctx.attr.exec_interpreter[PyRuntimeInfo]
    target_py_info = ctx.attr.target_interpreter[PyRuntimeInfo]

    pycross_info = PycrossBuildExecRuntimeInfo(
        exec_python_files=exec_py_info.files,
        exec_python_executable=exec_py_info.interpreter.path,
        target_python_files=target_py_info.files,
        target_python_executable=target_py_info.interpreter.path,
        target_sys_path=[], #find_hermetic_sys_path(target_py_info),
        target_environment=ctx.attr.target_environment,
    )

    return [
        platform_common.ToolchainInfo(
            pycross_info = pycross_info,
        ),
    ]


pycross_hermetic_toolchain = rule(
    implementation = _pycross_hermetic_toolchain_impl,
    attrs = {
        "target_environment": attr.label(
            doc = "The target environment associated with this toolchain.",
            mandatory = True,
            providers = [PycrossTargetEnvironmentInfo],
        ),
        "target_interpreter": attr.label(
            doc = "The target Python interpreter (PyRuntimeInfo).",
            mandatory = True,
            providers = [PyRuntimeInfo],
        ),
        "exec_interpreter": attr.label(
            doc = "The execution Python interpreter (PyRuntimeInfo).",
            mandatory = True,
            providers = [PyRuntimeInfo],
        ),
    },
)

def config_compatible(config_setting_target):
    return select(
        {
            config_setting_target: [],
            "//conditions:default": ["@platforms//:incompatible"],
        }
    )
