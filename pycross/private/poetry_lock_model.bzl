"""Implementation of the pycross_poetry_lock_model rule."""

def _pycross_poetry_lock_model_impl(ctx):
    out = ctx.outputs.out

    args = [
        "--poetry-project-file",
        ctx.file.poetry_project_file.path,
        "--poetry-lock-file",
        ctx.file.poetry_lock_file.path,
        "--output",
        out.path,
    ]

    ctx.actions.run(
        inputs = (
            ctx.files.poetry_project_file +
            ctx.files.poetry_lock_file
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
    ]

pycross_poetry_lock_model = rule(
    implementation = _pycross_poetry_lock_model_impl,
    attrs = {
        "poetry_project_file": attr.label(
            doc = "The pyproject.toml file with Poetry dependencies.",
            allow_single_file = True,
            mandatory = True,
        ),
        "poetry_lock_file": attr.label(
            doc = "The poetry.lock file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "out": attr.output(
            doc = "The output file.",
            mandatory = True,
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:poetry_translator"),
            cfg = "host",
            executable = True,
        ),
    },
)
