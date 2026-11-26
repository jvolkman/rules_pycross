"""Implementation of the meson_build rule."""

load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")
load("//pycross/private/build/actions:tool_extract.bzl", "extract_wheel_tool_aspect", "extract_wheel_tools")
load(":common_attrs.bzl", "CC_BUILD_ATTRS", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS", "COMMON_BUILD_ATTRS", "COMMON_TOOLCHAINS", "REPAIR_BUILD_ATTRS", "defer_build_error", "group_tool_deps", "resolve_path_tools", "run_wheel_build")

def _extract_meson_layer(ctx, make_vars):
    expanded_properties = {
        key: ctx.expand_make_variables("meson_properties", value, make_vars)
        for key, value in ctx.attr.meson_properties.items()
    }
    meson_config = {
        "meson_properties": expanded_properties,
        "allow_native_exec": ctx.attr.allow_native_exec,
    }
    config_json = ctx.actions.declare_file(ctx.label.name + "_meson_config.json")
    ctx.actions.write(config_json, json.encode(meson_config))
    return struct(
        config_json = config_json,
        transitive_files = depset(),
    )

def _meson_build_impl(ctx):
    # 1. Extract tools
    tool_deps = group_tool_deps(ctx.attr.tool_deps)
    tool_executables, missing_errors = extract_wheel_tools(tool_deps, ("meson", "ninja"))
    if missing_errors:
        return defer_build_error(ctx, missing_errors)

    tool_executables.extend(resolve_path_tools(ctx))

    # 2. Extract CC and Meson environments
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )
    meson_layer = _extract_meson_layer(ctx, cc_layer.make_vars)

    additional_build_deps = []
    if "meson-python" in tool_deps:
        additional_build_deps.extend(tool_deps["meson-python"])

    # 3. Build and repair wheel
    return run_wheel_build(
        ctx,
        builder = ctx.attr._builder,
        additional_build_deps = additional_build_deps,
        tool_executables = tool_executables,
        layers = [cc_layer, meson_layer],
        parallelism_env_vars = ("MESON_NUM_PROCESSES", "NINJA_JOBS"),
        repair_deps = tool_deps.get("repairwheel", []),
    )

meson_build = rule(
    implementation = _meson_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | REPAIR_BUILD_ATTRS | {
        "tool_deps": attr.label_list(
            doc = "Python build tool packages (`meson`, `ninja` and `meson-python`). " +
                  "The generated `@<repo>//_backend` macro fills these in from the lock file.",
            cfg = pycross_exec_platform_transition,
            aspects = [extract_wheel_tool_aspect],
        ),
        "meson_properties": attr.string_dict(
            doc = "Extra entries for the `[properties]` section of the generated Meson cross file.",
        ),
        "allow_native_exec": attr.bool(
            doc = "Allow Meson to run compiled test binaries on the build host during " +
                  "feature detection. When False (default), Meson always uses compile-only " +
                  "checks, producing reproducible builds regardless of host. Set to True " +
                  "only if you need host-specific optimizations and don't require " +
                  "cross-host reproducibility.",
            default = False,
        ),
        "_builder": attr.label(
            default = "//pycross/private/build/tools:meson_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = COMMON_TOOLCHAINS + CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)
