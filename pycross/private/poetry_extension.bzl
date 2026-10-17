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

poetry = make_format_extension(
    model_type = "poetry",
    discover_members_fn = discover_poetry_all_members,
    repo_create_model_fn = repo_create_poetry_model,
)
