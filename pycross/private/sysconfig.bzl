"""Implementation of the pycross_wheel_build rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load("@rules_python//python:defs.bzl", "PyInfo")

PYTHON_TOOLCHAIN_TYPE = "@bazel_tools//tools/python:toolchain_type"

def _find_sysconfigdata_file(py_toolchain):
    for file in py_toolchain.files.to_list():
        if file.basename.startswith("_sysconfigdata_") and file.basename.endswith(".py"):
            return file


def _pycross_sysconfig_impl(ctx):
    cc_toolchain_data = ctx.actions.declare_file(ctx.attr.name + "_cc_toolchain.json")
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    py_toolchain = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE].py3_runtime
    cc_toolchain = find_cpp_toolchain(ctx)

    cc_toolchain_json = cc_toolchain.to_json()
    cc_toolchain.pop("all_files")
    ctx.actions.write(cc_toolchain_data, cc_toolchain.to_json())

    args = [
        "--cc-toolchain-file",
        cc_toolchain_data.path,
        "--output",
        out.path,
    ]

    sysconfigdata_file = _find_sysconfigdata_file(py_toolchain)
    if sysconfigdata_file:
        args.extend([
            "--sysconfigdata-file",
            sysconfigdata_file.path
        ])

    if py_toolchain.interpreter_path:
        args.extend([
            "--interpreter-path",
            py_toolchain.interpreter_path,
        ])

    elif py_toolchain.interpreter:
        args.extend([
            "--interpreter-path",
            py_toolchain.interpreter.path,
        ])

    ctx.actions.run(
        inputs = [cc_toolchain_data],
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
        mnemonic = "Sysconfig",
    )

    return [
        DefaultInfo(
            files = depset(direct = [out]),
        ),
    ]

pycross_sysconfig = rule(
    implementation = _pycross_sysconfig_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:sysconfig_generator"),
            cfg = "host",
            executable = True,
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    toolchains = [PYTHON_TOOLCHAIN_TYPE] + use_cpp_toolchain(),
)
