"""Action logic for Rust environment extraction and PEP 517 Rust builds."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "CC_BUILD_ATTRS",
    "CC_FRAGMENTS",
    "CC_TOOLCHAINS",
    "CC_TOOLCHAIN_ATTRS",
    "COMMON_BUILD_ATTRS",
    "REPAIR_BUILD_ATTRS",
    "extract_cc_layer",
    "get_resource_set",
    "pycross_exec_platform_transition",
    "register_pep517_action",
    "register_repair_action",
)

def get_executable_file(val):
    """Extract a File from a toolchain value, trying multiple access patterns.

    Args:
        val: A File, Target, or None from a toolchain attribute.

    Returns:
        A File or None.
    """
    if not val or type(val) == "File":
        return val
    if DefaultInfo in val:
        return val[DefaultInfo].files_to_run.executable
    return None

def extract_rust_layer(ctx):
    """Extracts Rust toolchain info into a JSON file.

    Requires the calling rule to declare:
        - toolchains = ["@rules_rust//rust:toolchain_type"]
        - _exec_rust_toolchain attr

    Args:
        ctx: The rule context.

    Returns:
        struct(
            config_json = File,      # the serialized Rust config
            transitive_files = depset, # all files needed at build time
        )
    """
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]

    rustc_file = get_executable_file(rust_toolchain.rustc)
    rustc_path = rustc_file.path if rustc_file else None

    cargo_file = get_executable_file(rust_toolchain.cargo)
    cargo_path = cargo_file.path if cargo_file else None

    sysroot_path = None
    if hasattr(rust_toolchain, "sysroot"):
        sysroot_val = rust_toolchain.sysroot
        if type(sysroot_val) == "string":
            sysroot_path = sysroot_val
        elif hasattr(sysroot_val, "path"):
            sysroot_path = sysroot_val.path

    target_triple = getattr(rust_toolchain, "target_triple", None)
    target_triple_str = ""
    if target_triple:
        if type(target_triple) == "string":
            target_triple_str = target_triple
        elif hasattr(target_triple, "str"):
            target_triple_str = target_triple.str
        else:
            target_triple_str = str(target_triple)

    exec_triple = getattr(rust_toolchain, "exec_triple", None)
    host_triple_str = ""
    if exec_triple:
        if type(exec_triple) == "string":
            host_triple_str = exec_triple
        elif hasattr(exec_triple, "str"):
            host_triple_str = exec_triple.str
        else:
            host_triple_str = str(exec_triple)

    transitive_files = []
    if hasattr(rust_toolchain, "all_files"):
        transitive_files.append(rust_toolchain.all_files)
    if ctx.attr._exec_rust_toolchain:
        transitive_files.append(ctx.attr._exec_rust_toolchain[DefaultInfo].files)

    rust_config = {
        "rustc": rustc_path,
        "cargo": cargo_path,
        "sysroot": sysroot_path,
        "host_triple": host_triple_str,
        "target_triple": target_triple_str,
    }

    config_json = ctx.actions.declare_file(ctx.label.name + "_rust_config.json")
    ctx.actions.write(config_json, json.encode(rust_config))

    env_direct_files = [config_json]
    if rustc_file:
        env_direct_files.append(rustc_file)
    if cargo_file:
        env_direct_files.append(cargo_file)

    return struct(
        config_json = config_json,
        transitive_files = depset(env_direct_files, transitive = transitive_files),
    )

RUST_BUILD_COMMON_ATTRS = COMMON_BUILD_ATTRS | CC_BUILD_ATTRS | CC_TOOLCHAIN_ATTRS | REPAIR_BUILD_ATTRS | {
    "cargo_lock": attr.label(
        doc = "A Cargo.lock file to inject into the source tree before building. If not provided, the sdist's own Cargo.lock is used (if present).",
        allow_single_file = [".lock"],
    ),
    "vendored_crates": attr.label(
        doc = "A filegroup containing vendored crates.",
    ),
    "_exec_rust_toolchain": attr.label(
        default = Label("@rules_rust//rust/toolchain:current_rust_toolchain"),
        cfg = "exec",
    ),
}

RUST_BUILD_TOOLCHAINS = [
    "@rules_python//python:toolchain_type",
    config_common.toolchain_type("@rules_pycross//pycross:toolchain_type", mandatory = False),
    "@rules_rust//rust:toolchain_type",
] + CC_TOOLCHAINS

RUST_BUILD_FRAGMENTS = CC_FRAGMENTS

def rust_tool_deps_attr(doc):
    return attr.label_list(
        doc = doc,
        cfg = pycross_exec_platform_transition,
    )

def run_rust_pep517_build(ctx, tool_deps, tool_executables, tool_pkg_names):
    """Shared implementation for Rust PEP 517 wheel-building rules.

    Args:
        ctx: The rule context.
        tool_deps: Dict mapping normalized tool package names to Target lists.
        tool_executables: List of tool executable structs to place on PATH.
        tool_pkg_names: Tuple of tool package names to include in additional_build_deps.

    Returns:
        List of providers for the build rule.
    """
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]
    rustc_exe = get_executable_file(rust_toolchain.rustc)
    if rustc_exe:
        tool_executables.append(struct(name = "rustc", file = rustc_exe))
    cargo_exe = get_executable_file(rust_toolchain.cargo)
    if cargo_exe:
        tool_executables.append(struct(name = "cargo", file = cargo_exe))

    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )
    rust_layer = extract_rust_layer(ctx)

    additional_build_deps = []
    for pkg_name in tool_pkg_names:
        if pkg_name in tool_deps:
            additional_build_deps.extend(tool_deps[pkg_name])

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

    target_environment = ctx.files.target_environment[0] if ctx.files.target_environment else None
    repair_result = register_repair_action(
        ctx,
        input_wheel_dir = build_result.wheel_dir,
        native_deps = ctx.attr.native_deps,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
        repair_exclude_globs = ctx.attr.repair_exclude_globs,
        repair_deps = tool_deps.get("repairwheel", []),
        resource_set = resources.resource_set,
    )

    return [
        DefaultInfo(files = depset([repair_result.wheel_dir])),
        OutputGroupInfo(
            raw_wheel = depset([build_result.wheel_dir]),
        ),
    ]
