"""Implementation of the pep517_build rule."""

load("//pycross/private:providers.bzl", "PycrossPackageInfo", "PycrossWheelInfo")
load("//pycross/private/build/actions:pep517_action.bzl", "register_pep517_action")
load(":common_attrs.bzl", "COMMON_BUILD_ATTRS")

def _pep517_build_impl(ctx):
    # Validate that all required build packages are present in build_deps.
    if ctx.attr.required_build_packages:
        available = {}
        for dep in ctx.attr.build_deps:
            if PycrossPackageInfo in dep:
                available[dep[PycrossPackageInfo].package_name] = True

        missing = [pkg for pkg in ctx.attr.required_build_packages if pkg not in available]
        if missing:
            fail(
                "Missing required build-system packages: {}. ".format(", ".join(missing)) +
                "These are listed in build-system.requires but are not present in build_deps. " +
                "Make sure they are included in your lockfile.",
            )

    build_result = register_pep517_action(
        ctx,
        sdist = ctx.file.sdist,
        builder = ctx.attr._builder,
        deps = ctx.attr.deps,
        build_deps = ctx.attr.build_deps,
        pre_build_patches = ctx.files.pre_build_patches,
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
        "required_build_packages": attr.string_list(
            doc = "PEP 503 normalized names of packages required by build-system.requires. " +
                  "Used to validate that all needed build tools are present in build_deps.",
        ),
        "_builder": attr.label(
            default = "//pycross/private/build/tools:pep517_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [
        "@rules_python//python:toolchain_type",
        config_common.toolchain_type("//pycross:toolchain_type", mandatory = False),
    ],
)
