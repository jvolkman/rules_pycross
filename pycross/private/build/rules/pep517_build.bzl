"""Implementation of the pep517_build rule."""

load("//pycross/private:providers.bzl", "PycrossPackageInfo")
load(":common_attrs.bzl", "COMMON_BUILD_ATTRS", "COMMON_TOOLCHAINS", "REPAIR_BUILD_ATTRS", "defer_build_error", "run_wheel_build")

def _pep517_build_impl(ctx):
    # Validate that all required build packages are present in build_deps.
    if ctx.attr.required_build_packages:
        available = {}
        for dep in ctx.attr.build_deps:
            if PycrossPackageInfo in dep:
                available[dep[PycrossPackageInfo].package_name] = True

        missing = [pkg for pkg in ctx.attr.required_build_packages if pkg not in available]
        if missing:
            return defer_build_error(ctx, [
                "Missing required build-system packages: {}. ".format(", ".join(missing)) +
                "These are listed in build-system.requires but are not present in build_deps. " +
                "Make sure they are included in your lockfile.",
            ])

    return run_wheel_build(ctx, builder = ctx.attr._builder)

pep517_build = rule(
    implementation = _pep517_build_impl,
    attrs = COMMON_BUILD_ATTRS | REPAIR_BUILD_ATTRS | {
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
    toolchains = COMMON_TOOLCHAINS,
)
