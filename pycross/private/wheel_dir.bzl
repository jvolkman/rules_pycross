"""Rule that ensures a wheel is available as a TreeArtifact directory.

For pre-built wheels (plain .whl files), this copies the file into a
TreeArtifact directory. For sdist-built wheels (already TreeArtifact
directories from the build action), this is a no-op pass-through.
"""

load(":deferred_failure.bzl", "register_failure_action", "unsupported_wheel_message")
load(":providers.bzl", "PycrossUnsupportedWheelInfo")

def _pycross_wheel_dir_impl(ctx):
    if PycrossUnsupportedWheelInfo in ctx.attr.src:
        # No compatible wheel for this target environment (and failures are
        # deferred to execution). Fail with a message naming the package rather
        # than the shared placeholder target, and keep the marker so downstream
        # rules can do the same.
        out = ctx.actions.declare_directory(ctx.attr.whldir_name)
        package = ctx.attr.whldir_name.removesuffix(".whldir")
        register_failure_action(
            ctx,
            outputs = [out],
            message = unsupported_wheel_message(package),
            mnemonic = "PycrossUnsupportedWheel",
            progress_message = "Rejecting unsupported wheel %s" % package,
        )
        return [
            DefaultInfo(files = depset([out])),
            ctx.attr.src[PycrossUnsupportedWheelInfo],
        ]

    src = ctx.files.src[0]

    if src.is_directory:
        # Already a TreeArtifact (e.g., from an sdist build) — pass through.
        return [DefaultInfo(files = depset([src]))]

    # Plain .whl file — wrap it into a TreeArtifact directory.
    out = ctx.actions.declare_directory(ctx.attr.whldir_name)

    args = ctx.actions.args()
    args.add(src.path)
    args.add(out.path)

    ctx.actions.run(
        inputs = [src],
        outputs = [out],
        executable = ctx.executable._copy_file,
        arguments = [args],
        mnemonic = "PycrossWheelDir",
        execution_requirements = {"supports-path-mapping": "1"},
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
        "_copy_file": attr.label(
            default = Label("//pycross/private/tools:copy_file"),
            cfg = "exec",
            executable = True,
        ),
    },
)
