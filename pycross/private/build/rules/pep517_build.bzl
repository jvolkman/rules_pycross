"""Implementation of the pep517_build rule."""

load("//pycross/private:providers.bzl", "PycrossWheelInfo")
load("//pycross/private/build/actions:pep517_action.bzl", "register_pep517_action")
load(":common_attrs.bzl", "COMMON_BUILD_ATTRS")

def _pep517_build_impl(ctx):
    build_result = register_pep517_action(
        ctx,
        sdist = ctx.file.sdist,
        builder = ctx.attr._builder,
        deps = ctx.attr.deps,
        build_deps = ctx.attr.build_deps,
    )

    return [
        DefaultInfo(files = depset([build_result.wheel, build_result.wheel_directory])),
        PycrossWheelInfo(
            wheel_file = build_result.wheel,
            name_file = build_result.name_file,
            wheel_directory = build_result.wheel_directory,
        ),
    ]

pep517_build = rule(
    implementation = _pep517_build_impl,
    attrs = COMMON_BUILD_ATTRS | {
        "_builder": attr.label(
            default = "//pycross/private/build/tools:setuptools_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [
        "@rules_python//python:toolchain_type",
        config_common.toolchain_type("//pycross:toolchain_type", mandatory = False),
    ],
)
