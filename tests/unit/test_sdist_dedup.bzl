"""Tests for sdist build_deps deduplication via extract_pep508_name and dict-as-set.

Regression test for commit 8d8122f: when a pyproject.toml lists the same
build dependency multiple times (possibly via different specifiers),
the generated BUILD file must not contain duplicate label entries.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "extract_pep508_name", "underscore_name")

# ── Helpers ─────────────────────────────────────────────────────────

def _build_deps_from_requires(requires, known_packages, thin_repo):
    """Simulate the dedup logic from sdist_repo.bzl _sdist_repo_common.

    Mirrors the dict-as-set pattern used to prevent duplicate labels
    in the generated BUILD file.
    """
    build_deps = {}
    required_build_packages = {}
    for req in requires:
        req_name = extract_pep508_name(req)
        if req_name == "oldest-supported-numpy":
            req_name = "numpy"
        required_build_packages[req_name] = True
        if req_name in known_packages:
            build_deps["@{}//{}:pkg".format(thin_repo, underscore_name(req_name))] = True
    return sorted(build_deps.keys()), sorted(required_build_packages.keys())

# ── Test: duplicate specifiers produce unique labels ────────────────

# buildifier: disable=unused-variable
def _test_dedup_duplicate_specifiers_impl(env, target):
    """Different version specifiers for the same package must produce a single label."""
    requires = [
        "setuptools>=40.0",
        "setuptools<70.0",
        "wheel",
    ]
    known_packages = ["setuptools", "wheel"]
    deps, pkgs = _build_deps_from_requires(requires, known_packages, "pypi")

    env.expect.that_collection(deps).contains_exactly([
        "@pypi//setuptools:pkg",
        "@pypi//wheel:pkg",
    ])
    env.expect.that_collection(pkgs).contains_exactly([
        "setuptools",
        "wheel",
    ])

def _test_dedup_duplicate_specifiers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_dedup_duplicate_specifiers_impl)

# ── Test: name normalization dedup ──────────────────────────────────

# buildifier: disable=unused-variable
def _test_dedup_normalized_names_impl(env, target):
    """Packages with different name casing/separators must normalize to one label."""
    requires = [
        "my-package>=1.0",
        "My_Package>=2.0",
        "MY.PACKAGE",
    ]
    known_packages = ["my-package"]
    deps, pkgs = _build_deps_from_requires(requires, known_packages, "ws")

    env.expect.that_collection(deps).contains_exactly([
        "@ws//my_package:pkg",
    ])
    env.expect.that_collection(pkgs).contains_exactly([
        "my-package",
    ])

def _test_dedup_normalized_names(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_dedup_normalized_names_impl)

# ── Test: empty requires ────────────────────────────────────────────

# buildifier: disable=unused-variable
def _test_dedup_empty_requires_impl(env, target):
    """Empty requires list produces empty outputs."""
    deps, pkgs = _build_deps_from_requires([], [], "pypi")
    env.expect.that_collection(deps).contains_exactly([])
    env.expect.that_collection(pkgs).contains_exactly([])

def _test_dedup_empty_requires(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_dedup_empty_requires_impl)

# ── Test: unknown packages excluded from build_deps ─────────────────

# buildifier: disable=unused-variable
def _test_dedup_unknown_packages_impl(env, target):
    """Packages not in known_packages appear only in required_build_packages."""
    requires = [
        "setuptools>=40.0",
        "some-unknown-dep",
    ]
    known_packages = ["setuptools"]
    deps, pkgs = _build_deps_from_requires(requires, known_packages, "pypi")

    env.expect.that_collection(deps).contains_exactly([
        "@pypi//setuptools:pkg",
    ])
    env.expect.that_collection(pkgs).contains_exactly([
        "setuptools",
        "some-unknown-dep",
    ])

def _test_dedup_unknown_packages(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_dedup_unknown_packages_impl)

# ── Test: oldest-supported-numpy alias ──────────────────────────────

# buildifier: disable=unused-variable
def _test_dedup_oldest_numpy_impl(env, target):
    """oldest-supported-numpy should be treated as numpy."""
    requires = [
        "oldest-supported-numpy",
        "numpy>=1.21",
    ]
    known_packages = ["numpy"]
    deps, pkgs = _build_deps_from_requires(requires, known_packages, "pypi")

    # Both should collapse to a single numpy entry
    env.expect.that_collection(deps).contains_exactly([
        "@pypi//numpy:pkg",
    ])
    env.expect.that_collection(pkgs).contains_exactly([
        "numpy",
    ])

def _test_dedup_oldest_numpy(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_dedup_oldest_numpy_impl)

# ── Test suite ──────────────────────────────────────────────────────

def sdist_dedup_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_dedup_duplicate_specifiers,
            _test_dedup_normalized_names,
            _test_dedup_empty_requires,
            _test_dedup_unknown_packages,
            _test_dedup_oldest_numpy,
        ],
    )
