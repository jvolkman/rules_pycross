"""Implementation of the cmake_build rule."""

load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")
load("//pycross/private/build/actions:tool_extract.bzl", "extract_wheel_tool_aspect", "extract_wheel_tools")
load(":common_attrs.bzl", "CC_BUILD_ATTRS", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS", "COMMON_BUILD_ATTRS", "COMMON_TOOLCHAINS", "REPAIR_BUILD_ATTRS", "defer_build_error", "group_tool_deps", "resolve_path_tools", "run_wheel_build")

def _cmake_build_impl(ctx):
    # 1. Extract tools
    tool_deps = group_tool_deps(ctx.attr.tool_deps)
    tool_executables, missing_errors = extract_wheel_tools(tool_deps, ("cmake", "ninja"))
    if missing_errors:
        return defer_build_error(ctx, missing_errors)

    tool_executables.extend(resolve_path_tools(ctx))

    # 2. Extract CC environment
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )

    # cmake and ninja are registered as tool_executables (so they appear on
    # PATH inside the sandbox) AND as build_deps (so scikit-build-core can
    # `import cmake` / `import ninja` to discover their binary paths via
    # cmake.CMAKE_BIN_DIR and ninja.BIN_DIR).
    additional_build_deps = []
    if "scikit-build-core" in tool_deps:
        additional_build_deps.extend(tool_deps["scikit-build-core"])
    elif "scikit-build" in tool_deps:
        additional_build_deps.extend(tool_deps["scikit-build"])
    if "cmake" in tool_deps:
        additional_build_deps.extend(tool_deps["cmake"])
    if "ninja" in tool_deps:
        additional_build_deps.extend(tool_deps["ninja"])

    # 3. Build and repair wheel
    return run_wheel_build(
        ctx,
        builder = ctx.attr._builder,
        additional_build_deps = additional_build_deps,
        tool_executables = tool_executables,
        layers = [cc_layer],
        parallelism_env_vars = ("CMAKE_BUILD_PARALLEL_LEVEL", "NINJA_JOBS"),
        repair_deps = tool_deps.get("repairwheel", []),
    )

cmake_build = rule(
    implementation = _cmake_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | REPAIR_BUILD_ATTRS | {
        "tool_deps": attr.label_list(
            doc = "Python build tool packages (`cmake`, `ninja` and `scikit-build-core`). " +
                  "The generated `@<repo>//_backend` macro fills these in from the lock file.",
            cfg = pycross_exec_platform_transition,
            aspects = [extract_wheel_tool_aspect],
        ),
        "_builder": attr.label(
            default = "//pycross/private/build/tools:cmake_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = COMMON_TOOLCHAINS + CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)
