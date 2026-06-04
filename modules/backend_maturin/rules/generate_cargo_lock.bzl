"""Rule for generating Cargo.lock for an sdist."""

def _pycross_generate_cargo_lock_impl(ctx):
    sdist = ctx.file.sdist
    output = ctx.attr.output
    tool = ctx.executable._tool

    script = ctx.actions.declare_file(ctx.label.name + "_runner.sh")

    # Generate a bash wrapper that invokes the tool with runfiles paths.
    # Under `bazel run`, CWD is <runfiles_dir>/<workspace_name>, so
    # external-repo short paths (../<repo>/<path>) resolve correctly.

    script_content = """#!/bin/bash
# CWD is <runfiles_dir>/<main_workspace_name>
SDIST_PATH="{sdist_path}"
TOOL_PATH="{tool_path}"

# Run the actual tool
if [ -n "{output}" ]; then
    exec "$TOOL_PATH" --sdist "$SDIST_PATH" --output "{output}" "$@"
else
    exec "$TOOL_PATH" --sdist "$SDIST_PATH" "$@"
fi
""".format(
        sdist_path = sdist.short_path,
        tool_path = tool.short_path,
        output = output or "",
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [sdist])
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
            default = Label("//tools:generate_cargo_lock"),
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
)
