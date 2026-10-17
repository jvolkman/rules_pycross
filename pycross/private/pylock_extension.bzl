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

pylock = make_format_extension(
    model_type = "pylock",
    discover_members_fn = discover_pylock_all_members,
    repo_create_model_fn = repo_create_pylock_model,
)
