"""Implementation of the pycross_pdm_lock_model rule."""

def _pycross_pdm_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--project-file", ctx.file.project_file)
    args.add("--lock-file", ctx.file.lock_file)
    args.add("--output", out)

    if ctx.attr.default:
        args.add("--default")

    for group in ctx.attr.optional_groups:
        args.add("--optional-group", group)

    if ctx.attr.all_optional_groups:
        args.add("--all-optional-groups")

    for group in ctx.attr.development_groups:
        args.add("--development-group", group)

    if ctx.attr.all_development_groups:
        args.add("--all-development-groups")

    if ctx.attr.require_static_urls:
        args.add("--require-static-urls")

    ctx.actions.run(
        inputs = (
            ctx.files.project_file +
            ctx.files.lock_file
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = [args],
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
            default = True,
        ),
        "optional_groups": attr.string_list(
            doc = "List of optional dependency groups to install.",
        ),
        "all_optional_groups": attr.bool(
            doc = "Install all optional dependencies.",
        ),
        "development_groups": attr.string_list(
            doc = "List of development dependency groups to install.",
        ),
        "all_development_groups": attr.bool(
            doc = "Install all dev dependencies.",
        ),
        "require_static_urls": attr.bool(
            doc = "Require that the lock file is created with --static-urls.",
            default = True,
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:pdm_translator"),
            cfg = "exec",
            executable = True,
        ),
    },
)
