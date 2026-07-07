"""PDM lock format extension.

Provides the `pdm` module extension for importing PDM lock files.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":lock_common.bzl", "discover_pdm_all_members")
load(":pdm_lock_model.bzl", "repo_create_pdm_model")

# PDM-specific attrs for workspace tags (none beyond shared).
_PDM_WORKSPACE_ATTRS = dict()

pdm = make_format_extension(
    model_type = "pdm",
    workspace_attrs = _PDM_WORKSPACE_ATTRS,
    discover_members_fn = discover_pdm_all_members,
    repo_create_model_fn = repo_create_pdm_model,
)
