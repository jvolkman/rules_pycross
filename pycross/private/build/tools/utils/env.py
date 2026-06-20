"""Shared environment utilities for Pycross build tools."""

import os
from typing import Dict

# Environment variables injected by Bazel's py_binary launcher that should
# not leak into subprocess environments (e.g., PEP 517 builds, repairwheel).
_BAZEL_LAUNCHER_VARS = [
    "PYTHONSAFEPATH",
    "PYTHONPATH",
    "PYTHONHOME",
    "RUNFILES_DIR",
    "RUNFILES_MANIFEST_FILE",
    "RUNFILES_MANIFEST_ONLY",
]


def scrub_bazel_env(env: Dict[str, str]) -> Dict[str, str]:
    """Remove Bazel py_binary launcher variables from an environment dict.

    Returns the same dict (mutated in-place) for convenience.
    """
    for key in _BAZEL_LAUNCHER_VARS:
        env.pop(key, None)
    return env


def make_clean_env() -> Dict[str, str]:
    """Create a copy of os.environ with Bazel launcher variables removed."""
    return scrub_bazel_env(os.environ.copy())
