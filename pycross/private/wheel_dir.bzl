"""Rule that wraps a wheel file into a TreeArtifact directory."""

def _pycross_wheel_dir_impl(ctx):
    src = ctx.file.src
    out = ctx.actions.declare_directory(ctx.attr.whldir_name)
    ctx.actions.run_shell(
        inputs = [src],
        outputs = [out],
        command = 'cp "$1" "$2/"',
        arguments = [src.path, out.path],
        mnemonic = "WheelDir",
        progress_message = "Creating wheel directory %s" % ctx.attr.whldir_name,
    )
    return [DefaultInfo(files = depset([out]))]

pycross_wheel_dir = rule(
    implementation = _pycross_wheel_dir_impl,
    attrs = {
        "src": attr.label(
            doc = "The .whl file to wrap.",
            mandatory = True,
            allow_single_file = [".whl"],
        ),
        "whldir_name": attr.string(
            doc = "Name for the output TreeArtifact directory (e.g., 'numpy-1.24.0.whldir').",
            mandatory = True,
        ),
    },
)
