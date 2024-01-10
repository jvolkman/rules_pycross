"""Implementation of the pycross_poetry_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "POETRY_IMPORT_ATTRS")

def _pycross_poetry_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--project-file", ctx.file.project_file)
    args.add("--lock-file", ctx.file.lock_file)
    args.add("--output", out)

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

def pkg_repo_model_poetry(*, project_file, lock_file):
    return json.encode(dict(
        model_type = "poetry",
        project_file = project_file,
        lock_file = lock_file,
    ))

def repo_create_poetry_model(rctx, params, output):
    args = [
        "--project-file",
        str(rctx.path(Label(params["project_file"]))),
        "--lock-file",
        str(rctx.path(Label(params["lock_file"]))),
        "--output",
        output,
    ]

    exec_internal_tool(
        rctx,
        Label("//pycross/private/tools:poetry_translator.py"),
        args,
    )
