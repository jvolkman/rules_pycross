"""Implementation of the pep517_build rule."""

load("//pycross/private:providers.bzl", "PycrossPackageInfo")
load("//pycross/private/build/actions:pep517_action.bzl", "register_pep517_action")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")
load(":common_attrs.bzl", "COMMON_BUILD_ATTRS", "REPAIR_BUILD_ATTRS")

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
        builder = ctx.attr._builder,
    )

    target_environment = ctx.files.target_environment[0] if ctx.files.target_environment else None
    repair_result = register_repair_action(
        ctx,
        input_wheel_dir = build_result.wheel_dir,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
    )

    return [
        DefaultInfo(files = depset([repair_result.wheel_dir])),
        OutputGroupInfo(
            raw_wheel = depset([build_result.wheel_dir]),
        ),
    ]

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
    toolchains = [
        "@rules_python//python:toolchain_type",
        config_common.toolchain_type("//pycross:toolchain_type", mandatory = False),
    ],
)
