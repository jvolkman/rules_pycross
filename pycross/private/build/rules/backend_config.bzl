"""Backend configuration: maps backend macro names to their rules and required tool packages."""

# Each entry describes a backend build rule and the PyPI package names of the
# tools it needs at build time.  package_repo.bzl reads this at repo-generation
# time and wires up tool_deps defaults for any packages present in the lockfile.
BACKEND_CONFIGS = {
    "meson_build": {
        "rule_bzl": "meson_build",
        "tool_packages": ["meson", "ninja", "meson-python"],
    },
    "cmake_build": {
        "rule_bzl": "cmake_build",
        "tool_packages": ["cmake", "ninja", "scikit-build-core"],
    },
    "maturin_build": {
        "rule_bzl": "maturin_build",
        "tool_packages": ["maturin"],
    },
    "setuptools_build": {
        "rule_bzl": "setuptools_build",
        "tool_packages": ["setuptools", "wheel"],
    },
    "pep517_build": {
        "rule_bzl": "pep517_build",
        "tool_packages": [],
    },
}
