"""Implementation of the pycross_uv_lock_model rule."""

load(":lock_attrs.bzl", "UV_IMPORT_ATTRS")
load(":lock_model.bzl", "lock_model")

TRANSLATOR_TOOL = Label("//pycross/private/tools:uv_translator.py")

def lock_repo_model_uv(*, project_file, lock_file, default = True, optional_groups = [], all_optional_groups = False, development_groups = [], all_development_groups = False, require_static_urls = True):
    return lock_model.lock_repo_model(
        model_type = "uv",
        project_file = project_file,
        lock_file = lock_file,
        default = default,
        optional_groups = optional_groups,
        all_optional_groups = all_optional_groups,
        development_groups = development_groups,
        all_development_groups = all_development_groups,
        require_static_urls = require_static_urls,
    )

def repo_create_uv_model(rctx, params, output):
    """Run the pdm lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        params: a struct or dict containing the same attrs as the pycross_pdm_lock_model rule.
        output: the output file.
    """
    lock_model.repo_create_model(
        rctx = rctx,
        params = params,
        output = output,
        translator_tool = TRANSLATOR_TOOL,
    )

pycross_uv_lock_model = rule(
    implementation = lock_model.implementation,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:uv_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | UV_IMPORT_ATTRS,
)
