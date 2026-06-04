"""Implementation of the maturin_build rule."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "CC_BUILD_ATTRS",
    "CC_FRAGMENTS",
    "CC_TOOLCHAINS",
    "CC_TOOLCHAIN_ATTRS",
    "COMMON_BUILD_ATTRS",
    "PycrossWheelInfo",
    "extract_cc_layer",
    "get_unzipped_wheel",
    "group_tool_deps",
    "pycross_exec_platform_transition",
    "register_bin_extract_action",
    "register_pep517_action",
    "register_repair_action",
)
load("//private:rust_layer.bzl", "extract_rust_layer")

def _get_executable_file(val):
    if not val or type(val) == "File":
        return val
    if DefaultInfo in val:
        return val[DefaultInfo].files_to_run.executable
    return None

def _maturin_build_impl(ctx):
    # 1. Extract tools
    tool_executables = []
    has_maturin = False
    for target in ctx.attr.path_tools:
        exe = target[DefaultInfo].files_to_run.executable
        name = exe.basename
        if "maturin" in name.lower():
            has_maturin = True
        tool_executables.append(struct(name = name, file = exe, files_to_run = target[DefaultInfo].files_to_run))

    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    if not has_maturin:
        if "maturin" not in tool_deps:
            fail("Missing 'maturin' in tool_deps")
        maturin_wheel = get_unzipped_wheel(tool_deps["maturin"][0])
        tool_executables.append(register_bin_extract_action(
            ctx,
            wheel_dir = maturin_wheel,
            binary_name = "maturin",
        ))

    # Add rustc and cargo wrappers
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]
    rustc_exe = _get_executable_file(rust_toolchain.rustc)
    if rustc_exe:
        tool_executables.append(struct(name = "rustc", file = rustc_exe))
    cargo_exe = _get_executable_file(rust_toolchain.cargo)
    if cargo_exe:
        tool_executables.append(struct(name = "cargo", file = cargo_exe))

    # 2. Extract CC and Rust environments
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )
    rust_layer = extract_rust_layer(ctx)

    build_deps = list(ctx.attr.build_deps)
    if "maturin" in tool_deps:
        build_deps.extend(tool_deps["maturin"])

    # Collect extra files to inject into the sdist before building.
    extra_files = {}
    if ctx.file.cargo_lock:
        extra_files["Cargo.lock"] = ctx.file.cargo_lock

    cargo_vendored_sources = None
    if ctx.attr.vendored_crates:
        workspace_name = ctx.label.workspace_name
        if workspace_name:
            cargo_vendored_sources = "external/{}/vendor".format(workspace_name)
        else:
            cargo_vendored_sources = "vendor"

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
        layers = [cc_layer, rust_layer],
        pkg_config_files = ctx.files.pkg_config_files,
        extra_files = extra_files,
        extra_inputs = ctx.files.vendored_crates if ctx.attr.vendored_crates else [],
        cargo_vendored_sources = cargo_vendored_sources,
    )

    # 4. Repair wheel
    if ctx.attr.repair_wheel:
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

maturin_build = rule(
    implementation = _maturin_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | {
        "tool_deps": attr.label_list(
            cfg = pycross_exec_platform_transition,
        ),
        "cargo_lock": attr.label(
            doc = "A Cargo.lock file to inject into the source tree before building. If not provided, the sdist's own Cargo.lock is used (if present).",
            allow_single_file = [".lock"],
        ),
        "vendored_crates": attr.label(
            doc = "A filegroup containing vendored crates.",
        ),
        "repair_wheel": attr.bool(
            default = True,
        ),
        "_builder": attr.label(
            default = "@rules_pycross//pycross/private/build/tools:maturin_builder",
            executable = True,
            cfg = "exec",
        ),
        "_repair_tool": attr.label(
            default = Label("@rules_pycross//pycross/private/build/tools:repair_wheel_hook"),
            executable = True,
            cfg = "exec",
        ),
        "target_environment": attr.label(
            doc = "The target environment mapping JSON (resolved dynamically via alias filegroup).",
            default = Label("@pycross_environments//:current"),
            allow_files = True,
        ),
        "_extract_console_script": attr.label(
            default = "@rules_pycross//pycross/private/tools:extract_console_script",
            executable = True,
            cfg = "exec",
        ),
        "_exec_rust_toolchain": attr.label(
            default = Label("@rules_rust//rust/toolchain:current_rust_toolchain"),
            cfg = "exec",
        ),
    },
    toolchains = [
        "@rules_python//python:toolchain_type",
        config_common.toolchain_type("@rules_pycross//pycross:toolchain_type", mandatory = False),
        "@rules_rust//rust:toolchain_type",
    ] + CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)
