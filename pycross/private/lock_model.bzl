"""Implementation of the pycross_lock_model rule."""

load(":internal_repo.bzl", "exec_internal_tool")

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

def _pycross_lock_model_impl(ctx):
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

def _lock_repo_model(*, model_type, project_file, lock_file, default = True, optional_groups = [], all_optional_groups = False, development_groups = [], all_development_groups = False, require_static_urls = True):
    return json.encode(dict(
        model_type = model_type,
        project_file = str(project_file),
        lock_file = str(lock_file),
        default = default,
        optional_groups = optional_groups,
        all_optional_groups = all_optional_groups,
        development_groups = development_groups,
        all_development_groups = all_development_groups,
        require_static_urls = require_static_urls,
    ))

def _repo_create_model(rctx, params, output, translator_tool):
    """Run the pdm lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        params: a struct or dict containing the same attrs as the pycross_pdm_lock_model rule.
        output: the output file.
        translator_tool: the tool to run.
    """
    if type(params) == "dict":
        attrs = struct(**params)
    else:
        attrs = params
    args = _handle_args(
        attrs,
        str(rctx.path(Label(attrs.project_file))),
        str(rctx.path(Label(attrs.lock_file))),
        output,
    )

    exec_internal_tool(
        rctx,
        translator_tool,
        args,
    )

lock_model = struct(
    implementation = _pycross_lock_model_impl,
    repo_create_model = _repo_create_model,
    lock_repo_model = _lock_repo_model,
)
