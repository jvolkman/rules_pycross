"""Implementation of the pycross_wheel_build rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:defs.bzl", "PyInfo")

def _pycross_wheel_build_impl(ctx):
    out = ctx.actions.declare_file(paths.join(ctx.attr.name, "wheel.whl"))

    args = [
        "--sdist",
        ctx.file.sdist.path,
        "--wheel",
        out.path,
    ]

    ctx.actions.run(
        inputs = [ctx.file.sdist],
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
        mnemonic = "WheelBuild",
        progress_message = "Building %s" % ctx.file.sdist.basename,
    )

    return [
        DefaultInfo(
            files = depset(direct = [out]),
        ),
    ]

pycross_wheel_build = rule(
    implementation = _pycross_wheel_build_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of build dependencies for the wheel.",
        ),
        "sdist": attr.label(
            doc = "The sdist file.",
            allow_single_file = [".tar.gz"],
            mandatory = True,
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_builder"),
            cfg = "host",
            executable = True,
        ),
    }
)
