"""Implementation of the setuptools_build rule."""

load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")
load("//pycross/private/build/actions:pep517_action.bzl", "register_pep517_action")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")
load(":common_attrs.bzl", "CC_BUILD_ATTRS", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS", "COMMON_BUILD_ATTRS", "group_tool_deps")

def _setuptools_build_impl(ctx):
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )

    tool_executables = []
    for target in ctx.attr.path_tools:
        exe = target[DefaultInfo].files_to_run.executable
        name = exe.basename
        tool_executables.append(struct(name = name, file = exe, files_to_run = target[DefaultInfo].files_to_run))

    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    # setuptools and wheel are injected as build deps when present, but are not
    # strictly required — they may already be available in the build environment
    # (e.g. bundled with the Python interpreter).
    build_deps = list(ctx.attr.build_deps)
    if "setuptools" in tool_deps:
        build_deps.extend(tool_deps["setuptools"])
    if "wheel" in tool_deps:
        build_deps.extend(tool_deps["wheel"])

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

    if ctx.attr.native_deps:
        target_environment = ctx.files.target_environment[0] if ctx.files.target_environment else None
        repair_result = register_repair_action(
            ctx,
            input_wheelhouse = build_result.wheelhouse,
            native_deps = ctx.attr.native_deps,
            repair_tool = ctx.executable._repair_tool,
            target_environment = target_environment,
            repair_deps = tool_deps.get("repairwheel", []),
        )
    else:
        repair_result = build_result

    return [
        DefaultInfo(files = depset([repair_result.wheelhouse])),
        OutputGroupInfo(
            raw_wheel = depset([build_result.wheelhouse]),
        ),
    ]

setuptools_build = rule(
    implementation = _setuptools_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | {
        "tool_deps": attr.label_list(
            cfg = pycross_exec_platform_transition,
        ),
        "_builder": attr.label(
            default = "//pycross/private/build/tools:pep517_builder",
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
    },
    toolchains = [
        "@rules_python//python:toolchain_type",
        config_common.toolchain_type("//pycross:toolchain_type", mandatory = False),
    ] + CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)
