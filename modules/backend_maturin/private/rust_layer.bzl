"""Action logic for Rust environment extraction and PEP 517 Rust builds."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "CC_BUILD_ATTRS",
    "CC_FRAGMENTS",
    "CC_TOOLCHAINS",
    "CC_TOOLCHAIN_ATTRS",
    "COMMON_BUILD_ATTRS",
    "COMMON_TOOLCHAINS",
    "REPAIR_BUILD_ATTRS",
    "extract_cc_layer",
    "pycross_exec_platform_transition",
    "run_wheel_build",
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

def _find_rustlib_dir(toolchain, triple_str):
    """Finds the execroot path to lib/rustlib/<triple>/lib from a rust_toolchain."""
    if not toolchain:
        return None
    marker = "/lib/rustlib/{}/lib".format(triple_str) if triple_str else "/lib/rustlib/"
    rust_std_paths = getattr(toolchain, "rust_std_paths", None)
    if rust_std_paths:
        for d in rust_std_paths.to_list():
            if d.endswith(marker):
                return d
            if marker + "/" in d:
                prefix, _, _ = d.partition(marker)
                return prefix + marker
    rust_std = getattr(toolchain, "rust_std", None)
    if rust_std:
        for f in rust_std.to_list():
            if marker in f.path:
                prefix, _, _ = f.path.partition(marker)
                return prefix + marker
    sysroot_val = getattr(toolchain, "sysroot", None)
    if sysroot_val and triple_str:
        sysroot_str = sysroot_val if type(sysroot_val) == "string" else getattr(sysroot_val, "path", None)
        if sysroot_str:
            return "{}/lib/rustlib/{}/lib".format(sysroot_str.rstrip("/"), triple_str)
    return None

def _resolve_vendored_crates_dir(vendored_target, vendored_files):
    """Resolves the execroot vendor directory path from vendored_crates files."""
    best_vendor_dir = None
    best_depth = None
    for f in vendored_files:
        if f.basename == ".cargo-checksum.json":
            vendor_dir, _, _ = f.dirname.rpartition("/")
            if vendor_dir:
                depth = vendor_dir.count("/")
                if best_depth == None or depth < best_depth:
                    best_depth = depth
                    best_vendor_dir = vendor_dir
    if best_vendor_dir:
        return best_vendor_dir
    for f in vendored_files:
        if "/vendor/" in f.path:
            return f.path.split("/vendor/", 1)[0] + "/vendor"
        if f.path.startswith("vendor/"):
            return "vendor"
    ws_root = vendored_target.label.workspace_root
    pkg = vendored_target.label.package
    parts = [p for p in [ws_root, pkg, "vendor"] if p]
    return "/".join(parts)

def _triple_to_str(triple):
    """Normalize a rules_rust triple value to a string."""
    if not triple:
        return ""
    if type(triple) == "string":
        return triple
    if hasattr(triple, "str"):
        return triple.str
    return str(triple)

def extract_rust_layer(ctx):
    """Extracts Rust toolchain info into a JSON file.

    Requires the calling rule to declare:
        - toolchains = ["@rules_rust//rust:toolchain_type"]
        - _exec_rust_toolchain attr

    Args:
        ctx: The rule context.

    Returns:
        struct(
            config_json = File,        # the serialized Rust config
            transitive_files = depset, # all files needed at build time
            rustc = File | None,       # rustc executable file
            cargo = File | None,       # cargo executable file
        )
    """
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]

    rustc_file = get_executable_file(rust_toolchain.rustc)
    rustc_path = rustc_file.path if rustc_file else None

    cargo_file = get_executable_file(rust_toolchain.cargo)
    cargo_path = cargo_file.path if cargo_file else None

    target_triple_str = _triple_to_str(getattr(rust_toolchain, "target_triple", None))
    host_triple_str = _triple_to_str(getattr(rust_toolchain, "exec_triple", None))

    transitive_files = []
    if hasattr(rust_toolchain, "all_files"):
        transitive_files.append(rust_toolchain.all_files)
    exec_rust_toolchain = None
    if ctx.attr._exec_rust_toolchain:
        transitive_files.append(ctx.attr._exec_rust_toolchain[DefaultInfo].files)
        if platform_common.ToolchainInfo in ctx.attr._exec_rust_toolchain:
            exec_rust_toolchain = ctx.attr._exec_rust_toolchain[platform_common.ToolchainInfo]

    target_rustlib_dir = _find_rustlib_dir(rust_toolchain, target_triple_str)
    host_rustlib_dir = _find_rustlib_dir(exec_rust_toolchain, host_triple_str) if exec_rust_toolchain else None

    rust_config = {
        "rustc": rustc_path,
        "cargo": cargo_path,
        "host_triple": host_triple_str,
        "target_triple": target_triple_str,
        "host_rustlib_dir": host_rustlib_dir,
        "target_rustlib_dir": target_rustlib_dir,
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
        rustc = rustc_file,
        cargo = cargo_file,
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

RUST_BUILD_TOOLCHAINS = COMMON_TOOLCHAINS + [
    "@rules_rust//rust:toolchain_type",
] + CC_TOOLCHAINS

RUST_BUILD_FRAGMENTS = CC_FRAGMENTS

def rust_tool_deps_attr(doc, aspects = []):
    return attr.label_list(
        doc = doc,
        cfg = pycross_exec_platform_transition,
        aspects = aspects,
    )

def run_rust_pep517_build(ctx, tool_deps, tool_executables, tool_pkg_names):
    """Shared implementation for Rust PEP 517 wheel-building rules.

    Args:
        ctx: The rule context.
        tool_deps: Dict mapping normalized tool package names to Target lists.
        tool_executables: List of tool executable structs to place on PATH.
        tool_pkg_names: List of tool package names to include in additional_build_deps.

    Returns:
        List of providers for the build rule.
    """
    cc_layer = extract_cc_layer(
        ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
    )
    rust_layer = extract_rust_layer(ctx)
    if rust_layer.rustc:
        tool_executables.append(struct(name = "rustc", file = rust_layer.rustc))
    if rust_layer.cargo:
        tool_executables.append(struct(name = "cargo", file = rust_layer.cargo))

    additional_build_deps = []
    for pkg_name in tool_pkg_names:
        if pkg_name in tool_deps:
            additional_build_deps.extend(tool_deps[pkg_name])

    extra_files = {}
    if ctx.file.cargo_lock:
        extra_files["Cargo.lock"] = ctx.file.cargo_lock

    cargo_vendored_sources = None
    if ctx.attr.vendored_crates:
        cargo_vendored_sources = _resolve_vendored_crates_dir(
            ctx.attr.vendored_crates,
            ctx.files.vendored_crates,
        )

    env = {}
    if cargo_vendored_sources:
        env["CARGO_VENDORED_SOURCES"] = cargo_vendored_sources

    return run_wheel_build(
        ctx,
        builder = ctx.attr._builder,
        additional_build_deps = additional_build_deps,
        tool_executables = tool_executables,
        layers = [cc_layer, rust_layer],
        extra_files = extra_files,
        extra_inputs = ctx.files.vendored_crates if ctx.attr.vendored_crates else [],
        env = env,
        parallelism_env_vars = ("CARGO_BUILD_JOBS",),
        repair_deps = tool_deps.get("repairwheel", []),
    )
