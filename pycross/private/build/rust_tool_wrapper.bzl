"""Rule for wrapping a Rust toolchain tool as an executable target."""

def _get_executable_file(val):
    if not val or type(val) == "File":
        return val
    if DefaultInfo in val:
        return val[DefaultInfo].files_to_run.executable
    return None

def _rust_tool_wrapper_impl(ctx):
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]

    if ctx.attr.tool == "cargo":
        tool_val = rust_toolchain.cargo
    elif ctx.attr.tool == "rustc":
        tool_val = rust_toolchain.rustc
    else:
        fail("Unsupported tool: %s" % ctx.attr.tool)

    tool_file = _get_executable_file(tool_val)
    if not tool_file:
        fail("Could not find executable file for tool: %s" % ctx.attr.tool)

    out_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = out_file,
        target_file = tool_file,
        is_executable = True,
    )

    transitive_files = []
    if hasattr(rust_toolchain, "all_files"):
        transitive_files.append(rust_toolchain.all_files)
    if ctx.attr._exec_rust_toolchain:
        transitive_files.append(ctx.attr._exec_rust_toolchain[DefaultInfo].files)

    return [
        DefaultInfo(
            executable = out_file,
            files = depset([out_file]),
            runfiles = ctx.runfiles(transitive_files = depset(transitive = transitive_files)),
        ),
    ]

pycross_rust_tool_wrapper = rule(
    implementation = _rust_tool_wrapper_impl,
    attrs = {
        "tool": attr.string(
            mandatory = True,
            values = ["cargo", "rustc"],
            doc = "The Rust tool to wrap (cargo or rustc).",
        ),
        "_exec_rust_toolchain": attr.label(
            default = Label("@rules_rust//rust/toolchain:current_rust_toolchain"),
            cfg = "exec",
        ),
    },
    toolchains = ["@rules_rust//rust:toolchain_type"],
    executable = True,
)
