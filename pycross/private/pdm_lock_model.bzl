"""Implementation of the pycross_pdm_lock_model rule."""

def _pycross_pdm_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = [
        "--project-file",
        ctx.file.project_file.path,
        "--lock-file",
        ctx.file.lock_file.path,
        "--output",
        out.path,
    ]

    if ctx.attr.default:
      args.append("--default")

    if ctx.attr.dev:
      args.append("--dev")

    for group in ctx.attr.groups:
      args.extend(["--group", group])

    ctx.actions.run(
        inputs = (
            ctx.files.project_file +
            ctx.files.lock_file
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
        "project_file": attr.label(
            doc = "The pyproject.toml file with pdm dependencies.",
            allow_single_file = True,
            mandatory = True,
        ),
        "lock_file": attr.label(
            doc = "The pdm.lock file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "default": attr.bool(
            doc = "Whether to install dependencies from the default group.",
            mandatory = False,
            default = True,
        ),
        "dev": attr.bool(
            doc = "Whether to install dev dependencies.",
            mandatory = False,
            default = False,
        ),
        "groups": attr.string_list(
            doc = "Select groups of optional-dependencies or dev-dependencies to install.",
            mandatory = False,
            default = [],
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:pdm_translator"),
            cfg = "host",
            executable = True,
        ),
    },
)
