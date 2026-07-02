"""PDM lock format extension.

Provides the `pdm` module extension for importing PDM lock files.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":lock_common.bzl", "discover_pdm_all_members")
load(":pdm_lock_model.bzl", "repo_create_pdm_model")

# PDM-specific attrs for standalone project imports.
_PDM_PROJECT_ATTRS = dict(
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

# PDM-specific attrs for workspace tags (none beyond shared).
_PDM_WORKSPACE_ATTRS = dict()

# PDM-specific attrs for all_projects tags (none beyond shared).
_PDM_ALL_PROJECTS_ATTRS = dict()

pdm = make_format_extension(
    model_type = "pdm",
    standalone_project_attrs = _PDM_PROJECT_ATTRS,
    workspace_attrs = _PDM_WORKSPACE_ATTRS,
    all_projects_attrs = _PDM_ALL_PROJECTS_ATTRS,
    discover_members_fn = discover_pdm_all_members,
    repo_create_model_fn = repo_create_pdm_model,
)
