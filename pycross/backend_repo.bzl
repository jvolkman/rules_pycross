"""Backwards-compatible re-export. Use //pycross:backend.bzl instead."""

load(
    "//pycross:backend.bzl",
    _SDIST_REPO_ATTRS = "SDIST_REPO_ATTRS",
    _sdist_repo_common = "sdist_repo_common",
)

SDIST_REPO_ATTRS = _SDIST_REPO_ATTRS
sdist_repo_common = _sdist_repo_common
