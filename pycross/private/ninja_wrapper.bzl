"""Internal Starlark rule that creates a host-executable ninja wrapper.

Wraps the generic ninja_wrapper.py and merges the runfiles of the user's ninja
wheel target natively, ensuring Bazel stages the host-architecture ninja wheel
inside the build sandbox during cross-compilation.
"""

def _ninja_wrapper_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)

    # Copy the script rather than symlink it.  The wrapper uses
    # Path(__file__).resolve() to locate its adjacent .runfiles directory.
    # A symlink would resolve to the source tree where no .runfiles exist.
    ctx.actions.expand_template(
        template = ctx.file._script,
        output = out,
        substitutions = {},
    )

    # Merge runfiles from the user's ninja wheel target so Bazel stages them
    # inside the consuming pycross_wheel_build action's sandbox.
    runfiles = ctx.runfiles(files = [out])
    if ctx.attr.ninja:
        runfiles = runfiles.merge(ctx.attr.ninja[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            files = depset([out]),
            runfiles = runfiles,
            executable = out,
        ),
    ]

ninja_wrapper = rule(
    implementation = _ninja_wrapper_impl,
    executable = True,
    doc = """Creates a host-executable ninja wrapper.

Merges the runfiles of the user's ninja wheel target to ensure Bazel stages
the host-architecture ninja wheel inside the sandbox during cross-compilation.
""",
    attrs = {
        "ninja": attr.label(
            doc = "The user's ninja wheel target.",
            mandatory = True,
            providers = [DefaultInfo],
        ),
        "_script": attr.label(
            doc = "The built-in python wrapper script.",
            allow_single_file = True,
            default = Label("//pycross/private/tools:ninja_wrapper.py"),
        ),
    },
)
