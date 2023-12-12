"""Implementation of the pycross_pdm_lock_model rule."""

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

def _pycross_pdm_lock_model_impl(ctx):
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

def pkg_repo_model_pdm(*, project_file, lock_file, default = True, optional_groups = [], all_optional_groups = False, development_groups = [], all_development_groups = False, require_static_urls = True):
    return json.encode(dict(
        model_type = "pdm",
        project_file = project_file,
        lock_file = lock_file,
        default = default,
        optional_groups = optional_groups,
        all_optional_groups = all_optional_groups,
        development_groups = development_groups,
        all_development_groups = all_development_groups,
        require_static_urls = require_static_urls,
    ))

def repo_create_pdm_model(rctx, params, output):
    attrs = struct(**params)
    args = _handle_args(
        attrs,
        str(rctx.path(Label(attrs.project_file))),
        str(rctx.path(Label(attrs.lock_file))),
        output,
    )

    exec_internal_tool(
        rctx,
        Label("//pycross/private/tools:pdm_translator.py"),
        args,
    )
