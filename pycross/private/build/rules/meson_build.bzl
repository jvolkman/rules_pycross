"""Implementation of the meson_build rule."""

load("//pycross/private:providers.bzl", "PycrossWheelInfo")
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")
load("//pycross/private/build/actions:pep517_action.bzl", "register_pep517_action")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")
load("//pycross/private/build/actions:tool_extract.bzl", "register_bin_extract_action", "register_console_script_extract_action")
load(":common_attrs.bzl", "CC_BUILD_ATTRS", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS", "COMMON_BUILD_ATTRS", "get_unzipped_wheel", "get_wheel_file", "group_tool_deps")

def _meson_build_impl(ctx):
    # 1. Extract tools
    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    if "meson" not in tool_deps:
        fail("Missing 'meson' in tool_deps")
    if "ninja" not in tool_deps:
        fail("Missing 'ninja' in tool_deps")

    meson_wheel = get_wheel_file(tool_deps["meson"][0])
    ninja_wheel = get_unzipped_wheel(tool_deps["ninja"][0])

    tool_executables = []
    tool_executables.append(register_console_script_extract_action(
        ctx,
        wheel = meson_wheel,
        script_name = "meson",
    ))
    tool_executables.append(register_bin_extract_action(
        ctx,
        wheel_dir = ninja_wheel,
        binary_name = "ninja",
    ))

    for target in ctx.attr.path_tools:
        exe = target[DefaultInfo].files_to_run.executable
        name = exe.basename
        tool_executables.append(struct(name = name, file = exe, files_to_run = target[DefaultInfo].files_to_run))

    # 2. Extract CC environment
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
        meson_properties = ctx.attr.meson_properties,
    )

    build_deps = list(ctx.attr.build_deps)
    if "meson-python" in tool_deps:
        build_deps.extend(tool_deps["meson-python"])

    # 3. Build wheel
    build_result = register_pep517_action(
        ctx,
        sdist = ctx.file.sdist,
        builder = ctx.attr._builder,
        deps = ctx.attr.deps,
        build_deps = build_deps,
        config_settings = ctx.attr.config_settings,
        site_hooks = ctx.attr.site_hooks,
        tool_executables = tool_executables,
        layers = [cc_layer],
        pkg_config_files = ctx.files.pkg_config_files,
        pre_build_patches = ctx.files.pre_build_patches,
    )

    # 4. Repair wheel
    if ctx.attr.native_deps:
        target_environment = ctx.files.target_environment[0] if ctx.files.target_environment else None
        repair_result = register_repair_action(
            ctx,
            input_wheel = build_result.wheel,
            input_name_file = build_result.name_file,
            input_wheel_directory = build_result.wheel_directory,
            native_deps = ctx.attr.native_deps,
            repair_tool = ctx.executable._repair_tool,
            target_environment = target_environment,
            repair_deps = tool_deps.get("repairwheel", []),
        )
    else:
        repair_result = build_result

    return [
        DefaultInfo(files = depset([repair_result.wheel, repair_result.wheel_directory])),
        PycrossWheelInfo(
            wheel_file = repair_result.wheel,
            name_file = repair_result.name_file,
            wheel_directory = repair_result.wheel_directory,
        ),
        OutputGroupInfo(
            raw_wheel = depset([build_result.wheel, build_result.wheel_directory]),
        ),
    ]

meson_build = rule(
    implementation = _meson_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | {
        "tool_deps": attr.label_list(
            cfg = pycross_exec_platform_transition,
        ),
        "meson_properties": attr.string_dict(),
        "_builder": attr.label(
            default = "//pycross/private/build/tools:meson_builder",
            executable = True,
            cfg = "exec",
        ),
        "_repair_tool": attr.label(
            default = Label("//pycross/private/build/tools:repair_wheel_hook"),
            executable = True,
            cfg = "exec",
        ),
        "target_environment": attr.label(
            doc = "The target environment mapping JSON (resolved dynamically via alias filegroup).",
            default = Label("@pycross_environments//:current"),
            allow_files = True,
        ),
        "_extract_console_script": attr.label(
            default = "//pycross/private/tools:extract_console_script",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [
        "@rules_python//python:toolchain_type",
        config_common.toolchain_type("//pycross:toolchain_type", mandatory = False),
    ] + CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)
