"""Public API for pycross backend repository rules.

This module provides the building blocks needed to implement custom
sdist repository rules that integrate with rules_pycross lock import.
"""

load(
    "//pycross/private/bzlmod:sdist_repo.bzl",
    _SDIST_REPO_ATTRS = "SDIST_REPO_ATTRS",
    _sdist_repo_common = "sdist_repo_common",
)

SDIST_REPO_ATTRS = _SDIST_REPO_ATTRS
sdist_repo_common = _sdist_repo_common
