"""Implementation of the pycross_pdm_lock_model rule."""

def _pycross_pdm_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = [
        "--pdm-project-file",
        ctx.file.pdm_project_file.path,
        "--pdm-lock-file",
        ctx.file.pdm_lock_file.path,
        "--output",
        out.path,
    ]

    ctx.actions.run(
        inputs = (
            ctx.files.pdm_project_file +
            ctx.files.pdm_lock_file
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

pycross_pdm_lock_model = rule(
    implementation = _pycross_pdm_lock_model_impl,
    attrs = {
        "pdm_project_file": attr.label(
            doc = "The pyproject.toml file with pdm dependencies.",
            allow_single_file = True,
            mandatory = True,
        ),
        "pdm_lock_file": attr.label(
            doc = "The pdm.lock file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:pdm_translator"),
            cfg = "host",
            executable = True,
        ),
    },
)
