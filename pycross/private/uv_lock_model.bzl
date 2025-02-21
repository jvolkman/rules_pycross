"""Implementation of the pycross_uv_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "UV_IMPORT_ATTRS")

TRANSLATOR_TOOL = Label("//pycross/private/tools:uv_translator.py")

def _handle_args(attrs, project_file, lock_file, output):
    args = []
    args.extend(["--project-file", project_file])
    args.extend(["--lock-file", lock_file])
    args.extend(["--output", output])

    if attrs.default:
        args.append("--default")

    for group in attrs.optional_groups:
        args.extend(["--optional-group", group])

    if attrs.all_optional_groups:
        args.append("--all-optional-groups")

    for group in attrs.development_groups:
        args.extend(["--development-group", group])

    if attrs.all_development_groups:
        args.append("--all-development-groups")

    if attrs.require_static_urls:
        args.append("--require-static-urls")

    return args

def _pycross_uv_lock_model_impl(ctx):
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

pycross_uv_lock_model = rule(
    implementation = _pycross_uv_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:uv_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | UV_IMPORT_ATTRS,
)

def lock_repo_model_uv(*, project_file, lock_file, default = True, optional_groups = [], all_optional_groups = False, development_groups = [], all_development_groups = False, require_static_urls = True):
    return json.encode(dict(
        model_type = "uv",
        project_file = str(project_file),
        lock_file = str(lock_file),
        default = default,
        optional_groups = optional_groups,
        all_optional_groups = all_optional_groups,
        development_groups = development_groups,
        all_development_groups = all_development_groups,
        require_static_urls = require_static_urls,
    ))

def repo_create_uv_model(rctx, project_file, lock_file, lock_model, output):
    """Run the uv lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_uv_lock_model rule.
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
