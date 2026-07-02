"""Implementation of the maturin_build rule."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "CC_BUILD_ATTRS",
    "CC_FRAGMENTS",
    "CC_TOOLCHAINS",
    "CC_TOOLCHAIN_ATTRS",
    "COMMON_BUILD_ATTRS",
    "REPAIR_BUILD_ATTRS",
    "TOOL_EXTRACT_ATTRS",
    "extract_cc_layer",
    "get_resource_set",
    "get_unzipped_wheel",
    "group_tool_deps",
    "pycross_exec_platform_transition",
    "register_bin_extract_action",
    "register_pep517_action",
    "register_repair_action",
    "resolve_path_tools",
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
    tool_executables = resolve_path_tools(ctx)
    has_maturin = any(["maturin" in t.name.lower() for t in tool_executables])

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

    additional_build_deps = []
    if "maturin" in tool_deps:
        additional_build_deps.extend(tool_deps["maturin"])

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

    resources = get_resource_set(ctx.attr)
    env = {}
    if resources.parallelism > 0:
        env["CARGO_BUILD_JOBS"] = str(resources.parallelism)
        env["MAKEFLAGS"] = "-j{}".format(resources.parallelism)
    if cargo_vendored_sources:
        env["CARGO_VENDORED_SOURCES"] = cargo_vendored_sources

    # 3. Build wheel
    build_result = register_pep517_action(
        ctx,
        builder = ctx.attr._builder,
        additional_build_deps = additional_build_deps,
        tool_executables = tool_executables,
        layers = [cc_layer, rust_layer],
        extra_files = extra_files,
        extra_inputs = ctx.files.vendored_crates if ctx.attr.vendored_crates else [],
        env = env,
        resource_set = resources.resource_set,
    )

    # 4. Repair wheel
    target_environment = ctx.files.target_environment[0] if ctx.files.target_environment else None
    repair_result = register_repair_action(
        ctx,
        input_wheel_dir = build_result.wheel_dir,
        native_deps = ctx.attr.native_deps,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
        repair_deps = tool_deps.get("repairwheel", []),
        resource_set = resources.resource_set,
    )

    return [
        DefaultInfo(files = depset([repair_result.wheel_dir])),
        OutputGroupInfo(
            raw_wheel = depset([build_result.wheel_dir]),
        ),
    ]

maturin_build = rule(
    implementation = _maturin_build_impl,
    attrs = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | REPAIR_BUILD_ATTRS | TOOL_EXTRACT_ATTRS | {
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
        "_builder": attr.label(
            default = "@rules_pycross_backend_maturin//private/tools:maturin_builder",
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
