"""Implementation of the pycross_pylock_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "PYLOCK_IMPORT_ATTRS")

TRANSLATOR_TOOL = Label("//pycross/private/tools:pylock_translator.py")

def _handle_args(project_file, lock_file, output):
    args = []
    if project_file:
        args.extend(["--project-file", project_file])
    args.extend(["--lock-file", lock_file])
    args.extend(["--output", output])

    return args

def _pycross_pylock_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")

    project_file_path = ctx.file.project_file.path if getattr(ctx.file, "project_file", None) else None

    args.add_all(
        _handle_args(
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

def lock_repo_model_pylock(*, lock_file, project_file = None, **_kwargs):
    return json.encode(dict(
        model_type = "pylock",
        lock_file = str(lock_file),
        project_file = str(project_file) if project_file else None,
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
        project_file_path,
        str(rctx.path(lock_file)),
        output,
    )

    exec_internal_tool(
        rctx,
        TRANSLATOR_TOOL,
        args,
    )
