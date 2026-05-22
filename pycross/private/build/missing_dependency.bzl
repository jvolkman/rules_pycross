"""A rule that fails at analysis time with a helpful error message when a required build tool is missing from the lock file."""

def _missing_dep_impl(ctx):
    fail(
        "\n========================================================================\n" +
        "ERROR: The build tool '{tool}' is required to build this package, but it\n" +
        "was not found in the lock file '{repo}'.\n\n" +
        "Please add '{tool}' to your requirements (e.g., in pyproject.toml or uv.lock)\n" +
        "and regenerate your lock files.\n" +
        "========================================================================\n".format(
            tool = ctx.attr.tool_name,
            repo = ctx.attr.lock_repo,
        ),
    )

pycross_missing_dependency = rule(
    implementation = _missing_dep_impl,
    attrs = {
        "tool_name": attr.string(mandatory = True),
        "lock_repo": attr.string(mandatory = True),
    },
)
