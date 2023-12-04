"""Implementation of the pycross_poetry_lock_model rule."""

load(":internal.bzl", "exec_internal_tool")

def _pycross_poetry_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--poetry-project-file", ctx.file.poetry_project_file)
    args.add("--poetry-lock-file", ctx.file.poetry_lock_file)
    args.add("--output", out)

    ctx.actions.run(
        inputs = (
            ctx.files.poetry_project_file +
            ctx.files.poetry_lock_file
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
        "_tool": attr.label(
            default = Label("//pycross/private/tools:poetry_translator"),
            cfg = "exec",
            executable = True,
        ),
    },
)

def pkg_repo_model_poetry(*, project_file, lock_file):
    return json.encode(dict(
        model_type = "poetry",
        project_file = project_file,
        lock_file = lock_file,
    ))

def repo_create_poetry_model(rctx, params, output):
    args = [
        "--poetry-project-file",
        str(rctx.path(Label(params["project_file"]))),
        "--poetry-lock-file",
        str(rctx.path(Label(params["lock_file"]))),
        "--output",
        output,
    ]

    exec_internal_tool(
        rctx,
        Label("@jvolkman_rules_pycross//pycross/private/tools:poetry_translator.py"),
        args,
    )
