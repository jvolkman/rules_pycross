"""Implementation of the pycross_poetry_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "POETRY_IMPORT_ATTRS")

TRANSLATOR_TOOL = Label("//pycross/private/tools:poetry_translator.py")

def _pycross_poetry_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--project-file", ctx.file.project_file)
    args.add("--lock-file", ctx.file.lock_file)
    args.add("--output", out)

    if ctx.attr.default:
        args.add("--default")

    for group in ctx.attr.optional_groups:
        args.add_all(["--optional-group", group])

    if ctx.attr.all_optional_groups:
        args.add("--all-optional-groups")

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

pycross_poetry_lock_model = rule(
    implementation = _pycross_poetry_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:poetry_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | POETRY_IMPORT_ATTRS,
)

def lock_repo_model_poetry(*, project_file, lock_file):
    return json.encode(dict(
        model_type = "poetry",
        project_file = str(project_file),
        lock_file = str(lock_file),
    ))

def repo_create_poetry_model(rctx, params, output):
    """Run the poetry lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        params: a struct or dict containing the same attrs as the pycross_poetry_lock_model rule.
        output: the output file.
    """
    if type(params) == "dict":
        attrs = struct(**params)
    else:
        attrs = params
    args = [
        "--project-file",
        str(rctx.path(Label(attrs.project_file))),
        "--lock-file",
        str(rctx.path(Label(attrs.lock_file))),
        "--output",
        output,
    ]

    exec_internal_tool(
        rctx,
        TRANSLATOR_TOOL,
        args,
    )
