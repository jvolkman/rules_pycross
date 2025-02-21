"""Implementation of the pycross_poetry_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "POETRY_IMPORT_ATTRS")

TRANSLATOR_TOOL = Label("//pycross/private/tools:poetry_translator.py")

def _handle_args(attrs, project_file, lock_file, output):
    args = []
    args.extend(["--project-file", project_file])
    args.extend(["--lock-file", lock_file])
    args.extend(["--output", output])

    if attrs.default:
        args.append("--default")

    for group in attrs.optional_groups:
        args.extend(["--optional-group", group])

    return args

def _pycross_poetry_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add_all(
        _handle_args(
            ctx.attr,
            ctx.file.project_file.path,
            ctx.file.lock_file.path,
            out.path,
        ),
    )

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

def lock_repo_model_poetry(*, project_file, lock_file, default = True, optional_groups = [], all_optional_groups = False):
    return json.encode(dict(
        model_type = "poetry",
        project_file = str(project_file),
        lock_file = str(lock_file),
        default = default,
        optional_groups = optional_groups,
        all_optional_groups = all_optional_groups,
    ))

def repo_create_poetry_model(rctx, project_file, lock_file, lock_model, output):
    """Run the poetry lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_poetry_lock_model rule.
        output: the output file.
    """
    args = _handle_args(
        lock_model,
        str(rctx.path(project_file)),
        str(rctx.path(lock_file)),
        output,
    )

    exec_internal_tool(
        rctx,
        TRANSLATOR_TOOL,
        args,
    )
