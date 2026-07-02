"""Pylock (PEP 751) lock format extension.

Provides the `pylock` module extension for importing pylock.toml lock files.
Pylock does not support workspaces, so only standalone project imports are available.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":lock_common.bzl", "discover_pylock_all_members")
load(":pylock_lock_model.bzl", "repo_create_pylock_model")

# Pylock-specific attrs for standalone project imports.
_PYLOCK_PROJECT_ATTRS = dict(
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
)

pylock = make_format_extension(
    model_type = "pylock",
    standalone_project_attrs = _PYLOCK_PROJECT_ATTRS,
    # Pylock has no workspace support — single-project only.
    workspace_attrs = None,
    all_projects_attrs = None,
    discover_members_fn = discover_pylock_all_members,
    repo_create_model_fn = repo_create_pylock_model,
)
