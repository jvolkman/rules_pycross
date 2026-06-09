"""Rule that ensures a wheel is available as a TreeArtifact directory.

For pre-built wheels (plain .whl files), this copies the file into a
TreeArtifact directory. For sdist-built wheels (already TreeArtifact
directories from the build action), this is a no-op pass-through.
"""

def _pycross_wheel_dir_impl(ctx):
    src = ctx.files.src[0]

    if src.is_directory:
        # Already a TreeArtifact (e.g., from an sdist build) — pass through.
        return [DefaultInfo(files = depset([src]))]

    # Plain .whl file — wrap it into a TreeArtifact directory.
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
            doc = "The .whl file or TreeArtifact directory to wrap.",
            mandatory = True,
            allow_files = True,
        ),
        "whldir_name": attr.string(
            doc = "Name for the output TreeArtifact directory (e.g., 'numpy-1.24.0.whldir').",
            mandatory = True,
        ),
    },
)
