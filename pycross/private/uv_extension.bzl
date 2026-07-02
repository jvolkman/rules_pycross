"""UV lock format extension.

Provides the `uv` module extension for importing UV lock files.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":lock_common.bzl", "discover_uv_all_members")
load(":uv_lock_model.bzl", "repo_create_uv_model")

# UV-specific attrs for standalone project imports.
_UV_PROJECT_ATTRS = dict(
    default_group = attr.bool(
        doc = "Whether to install dependencies from the default group.",
        default = True,
    ),
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install.",
    ),
    all_optional_groups = attr.bool(
        doc = "Install all optional dependencies.",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install.",
    ),
    all_development_groups = attr.bool(
        doc = "Install all dev dependencies.",
    ),
    require_static_urls = attr.bool(
        doc = "Require that the lock file is created with --static-urls.",
        default = True,
    ),
)

# UV-specific attrs for workspace tags.
_UV_WORKSPACE_ATTRS = dict(
    require_static_urls = attr.bool(
        doc = "Require that the lock file is created with --static-urls.",
        default = True,
    ),
)

# UV-specific attrs for all_projects tags (none beyond shared).
_UV_ALL_PROJECTS_ATTRS = dict()

uv = make_format_extension(
    model_type = "uv",
    standalone_project_attrs = _UV_PROJECT_ATTRS,
    workspace_attrs = _UV_WORKSPACE_ATTRS,
    all_projects_attrs = _UV_ALL_PROJECTS_ATTRS,
    discover_members_fn = discover_uv_all_members,
    repo_create_model_fn = repo_create_uv_model,
)
