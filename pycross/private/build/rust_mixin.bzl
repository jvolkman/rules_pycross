"""Rule for compiling Rust toolchain info into a PycrossBuildMixinInfo."""

load("//pycross/private:providers.bzl", "PycrossBuildMixinInfo")

def _get_executable_file(val):
    """Extract a File from a toolchain value, trying multiple access patterns."""
    if not val:
        return None

    # Direct File object
    if hasattr(val, "path") and hasattr(val, "is_source"):
        return val

    # FilesToRunProvider or similar
    if hasattr(val, "executable") and val.executable:
        return val.executable
    if hasattr(val, "files_to_run") and hasattr(val.files_to_run, "executable") and val.files_to_run.executable:
        return val.files_to_run.executable

    # Depset/list of files — take first
    if hasattr(val, "files") and val.files:
        if hasattr(val.files, "to_list"):
            files_list = val.files.to_list()
        else:
            files_list = val.files
        if files_list:
            return files_list[0]
    return None

def _rust_mixin_impl(ctx):
    # Query the resolved Rust toolchain
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]

    rustc_file = _get_executable_file(rust_toolchain.rustc)
    rustc_path = rustc_file.path if rustc_file else None

    cargo_file = _get_executable_file(rust_toolchain.cargo)
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

    config_json = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_json, json.encode(rust_config))

    mixin_direct_files = [config_json]
    if rustc_file:
        mixin_direct_files.append(rustc_file)
    if cargo_file:
        mixin_direct_files.append(cargo_file)

    return [
        PycrossBuildMixinInfo(
            config_json = config_json,
            files = depset(mixin_direct_files, transitive = transitive_files),
        ),
    ]

pycross_rust_mixin = rule(
    implementation = _rust_mixin_impl,
    attrs = {
        "_exec_rust_toolchain": attr.label(
            default = Label("@rules_rust//rust/toolchain:current_rust_toolchain"),
            cfg = "exec",
        ),
    },
    toolchains = ["@rules_rust//rust:toolchain_type"],
)
