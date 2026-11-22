"""Rule for generating Cargo.lock for an sdist."""

load("//private:rust_layer.bzl", "get_executable_file")

def _pycross_generate_cargo_lock_impl(ctx):
    sdist = ctx.file.sdist
    output = ctx.attr.output
    tool = ctx.executable._tool

    cargo_file = None
    rustc_file = None
    toolchain_files = []
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]
    if rust_toolchain:
        cargo_file = get_executable_file(getattr(rust_toolchain, "cargo", None))
        rustc_file = get_executable_file(getattr(rust_toolchain, "rustc", None))
        if cargo_file and hasattr(rust_toolchain, "all_files"):
            toolchain_files.append(rust_toolchain.all_files)

    script = ctx.actions.declare_file(ctx.label.name + "_runner.sh")

    # Generate a bash wrapper that invokes the tool with runfiles paths.
    # Under `bazel run`, CWD is <runfiles_dir>/<workspace_name>, so
    # external-repo short paths (../<repo>/<path>) resolve correctly.
    extra_lines = []
    cargo_args = ""
    if cargo_file:
        extra_lines.append('CARGO_PATH="$PWD/{}"'.format(cargo_file.short_path))
        cargo_args = ' --cargo "$CARGO_PATH"'
        if rustc_file:
            extra_lines.append('export RUSTC="$PWD/{}"'.format(rustc_file.short_path))

    script_content = """#!/bin/bash
# CWD is <runfiles_dir>/<main_workspace_name>
SDIST_PATH="{sdist_path}"
TOOL_PATH="{tool_path}"
{extra_setup}
# Run the actual tool
if [ -n "{output}" ]; then
    exec "$TOOL_PATH" --sdist "$SDIST_PATH" --output "{output}"{cargo_args} "$@"
else
    exec "$TOOL_PATH" --sdist "$SDIST_PATH"{cargo_args} "$@"
fi
""".format(
        sdist_path = sdist.short_path,
        tool_path = tool.short_path,
        extra_setup = ("\n".join(extra_lines) + "\n") if extra_lines else "",
        output = output or "",
        cargo_args = cargo_args,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    direct_runfiles = [sdist]
    if cargo_file:
        direct_runfiles.append(cargo_file)
        if rustc_file:
            direct_runfiles.append(rustc_file)
    runfiles = ctx.runfiles(files = direct_runfiles, transitive_files = depset(transitive = toolchain_files))
    runfiles = runfiles.merge(ctx.attr._tool[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

pycross_generate_cargo_lock = rule(
    implementation = _pycross_generate_cargo_lock_impl,
    attrs = {
        "sdist": attr.label(mandatory = True, allow_single_file = True),
        "output": attr.string(),
        "_tool": attr.label(
            default = Label("//private/tools:generate_cargo_lock"),
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [
        config_common.toolchain_type("@rules_rust//rust:toolchain_type", mandatory = False),
    ],
    executable = True,
)
