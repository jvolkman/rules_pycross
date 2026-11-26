"""Pylock (PEP 751) lock format extension.

Provides the `pylock` module extension for importing pylock.toml lock files.
Pylock does not support workspaces, so only standalone project imports are available.
"""

load(
    ":format_extension.bzl",
    "make_format_extension",
)
load(":pylock_lock_model.bzl", "repo_create_pylock_model")

pylock = make_format_extension(
    model_type = "pylock",
    discover_members_fn = lambda _mctx, _lock_file_label, _toml_cache = None: [struct(name = "root", path = "")],
    repo_create_model_fn = repo_create_pylock_model,
)
