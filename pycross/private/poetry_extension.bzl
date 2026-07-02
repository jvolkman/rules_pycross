"""Poetry lock format extension.

Provides the `poetry` module extension for importing Poetry lock files.
Poetry does not support workspaces, so only standalone project imports are available.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":lock_common.bzl", "discover_poetry_all_members")
load(":poetry_lock_model.bzl", "repo_create_poetry_model")

# Poetry-specific attrs for standalone project imports.
_POETRY_PROJECT_ATTRS = dict(
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
)

poetry = make_format_extension(
    model_type = "poetry",
    standalone_project_attrs = _POETRY_PROJECT_ATTRS,
    # Poetry has no workspace support — single-project only.
    workspace_attrs = None,
    all_projects_attrs = None,
    discover_members_fn = discover_poetry_all_members,
    repo_create_model_fn = repo_create_poetry_model,
)
