"""Implementation of the pycross_pylock_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "PYLOCK_IMPORT_ATTRS")

TRANSLATOR_TOOL = Label("//pycross/private/tools:pylock_translator.py")

def _handle_args(lock_model, project_file, lock_file, output):
    args = []
    if project_file:
        args.extend(["--project-file", project_file])
    args.extend(["--lock-file", lock_file])
    args.extend(["--output", output])

    if lock_model.default:
        args.append("--default")
    else:
        args.append("--no-default")

    if lock_model.all_optional_groups:
        args.append("--all-optional-groups")
    else:
        for group in lock_model.optional_groups:
            args.extend(["--optional-group", group])

    if getattr(lock_model, "all_development_groups", False):
        args.append("--all-development-groups")
    else:
        for group in getattr(lock_model, "development_groups", []):
            args.extend(["--development-group", group])

    return args

def _pycross_pylock_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")

    project_file_path = ctx.file.project_file.path if getattr(ctx.file, "project_file", None) else None

    args.add_all(
        _handle_args(
            ctx.attr,
            project_file_path,
            ctx.file.lock_file.path,
            out.path,
        ),
    )

    inputs = [ctx.file.lock_file]
    if getattr(ctx.file, "project_file", None):
        inputs.append(ctx.file.project_file)

    ctx.actions.run(
        inputs = inputs,
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = [args],
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
    ]

pycross_pylock_lock_model = rule(
    implementation = _pycross_pylock_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:pylock_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | PYLOCK_IMPORT_ATTRS,
)

def lock_repo_model_pylock(*, project_file = None, lock_file, default = True, optional_groups = [], all_optional_groups = False, development_groups = [], all_development_groups = False, **_kwargs):
    return json.encode(dict(
        model_type = "pylock",
        project_file = str(project_file) if project_file else None,
        lock_file = str(lock_file),
        default = default,
        optional_groups = optional_groups,
        all_optional_groups = all_optional_groups,
        development_groups = development_groups,
        all_development_groups = all_development_groups,
    ))

def repo_create_pylock_model(rctx, project_file, lock_file, lock_model, output):
    """Run the pylock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file (optional).
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pylock_lock_model rule.
        output: the output file.
    """

    project_file_path = str(rctx.path(project_file)) if project_file else None

    args = _handle_args(
        lock_model,
        project_file_path,
        str(rctx.path(lock_file)),
        output,
    )

    exec_internal_tool(
        rctx,
        TRANSLATOR_TOOL,
        args,
    )
