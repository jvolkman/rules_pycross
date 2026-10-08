"""UV lock format extension.

Provides the `uv` module extension for importing UV lock files.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":lock_common.bzl", "discover_uv_all_members")
load(":uv_lock_model.bzl", "repo_create_uv_model")

uv = make_format_extension(
    model_type = "uv",
    workspace_attrs = {},
    discover_members_fn = discover_uv_all_members,
    repo_create_model_fn = repo_create_uv_model,
)
