"""Implementation of the setuptools_build rule."""

load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")
load(":common_attrs.bzl", "CC_BUILD_ATTRS", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS", "COMMON_BUILD_ATTRS", "COMMON_TOOLCHAINS", "REPAIR_BUILD_ATTRS", "group_tool_deps", "resolve_path_tools", "run_wheel_build")

def _setuptools_build_impl(ctx):
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )

    tool_executables = resolve_path_tools(ctx)
    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    # setuptools and wheel are injected as build deps when present, but are not
    # strictly required — they may already be available in the build environment
    # (e.g. bundled with the Python interpreter).
    additional_build_deps = []
    if "setuptools" in tool_deps:
        additional_build_deps.extend(tool_deps["setuptools"])
    if "wheel" in tool_deps:
        additional_build_deps.extend(tool_deps["wheel"])

    return run_wheel_build(
        ctx,
        builder = ctx.attr._builder,
        additional_build_deps = additional_build_deps,
        tool_executables = tool_executables,
        layers = [cc_layer],
        repair_deps = tool_deps.get("repairwheel", []),
    )

setuptools_build = rule(
    implementation = _setuptools_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | REPAIR_BUILD_ATTRS | {
        "tool_deps": attr.label_list(
            doc = "Python build tool packages (`setuptools` and `wheel`). " +
                  "The generated `@<repo>//_backend` macro fills these in from the lock file.",
            cfg = pycross_exec_platform_transition,
        ),
        "_builder": attr.label(
            default = "//pycross/private/build/tools:pep517_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = COMMON_TOOLCHAINS + CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)
