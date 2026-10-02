"""Tests for sdist build_deps deduplication via extract_pep508_name and dict-as-set.

Regression test for commit 8d8122f: when a pyproject.toml lists the same
build dependency multiple times (possibly via different specifiers),
the generated BUILD file must not contain duplicate label entries.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "merge_dependencies_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:sdist_repo.bzl", "compute_sdist_build_config_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_file.bzl", "render_wheel_file_build_for_testing")

# ── Helpers ─────────────────────────────────────────────────────────

def _make_attr(known_packages, thin_repo = "pypi", build_backend = "", extra_build_tools = None):
    return struct(
        sdist = "@pypi_foo//:foo.tar.gz",
        deps = [],
        known_packages = known_packages,
        thin_repo = thin_repo,
        build_backend = build_backend,
        backend_to_rule = {"setuptools.build_meta": "setuptools_build"},
        default_backend = "pep517_build",
        extra_build_tools = extra_build_tools or [],
        whldir_name = "",
        source_dir = "",
        override_backend_configs = "",
        pre_build_patches = [],
        site_hooks = [],
    )

def _build_deps_from_requires(requires, known_packages, thin_repo):
    """Run compute_sdist_build_config_for_testing and return (build_deps, required_build_packages)."""
    cfg = compute_sdist_build_config_for_testing(
        _make_attr(known_packages = known_packages, thin_repo = thin_repo),
        {"build_backend": "flit_core.buildapi", "build_requires": requires},
    )
    return json.decode(cfg.macro_attrs["build_deps"]), json.decode(cfg.macro_attrs["required_build_packages"])

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

# ── Test: extra_build_tools included without explicit build_backend ──

# buildifier: disable=unused-variable
def _test_extra_build_tools_auto_backend_impl(env, target):
    """extra_build_tools must be merged with build_requires when build_backend is auto-detected."""
    cfg = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["setuptools", "wheel", "cython"],
            thin_repo = "uv__build",
            extra_build_tools = ["cython@3.0.0"],
        ),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": ["setuptools>=61", "wheel"],
            "site_paths": ["foo_pkg"],
            "bin_paths": ["foo_cli"],
            "data_paths": ["share"],
            "include_paths": ["foo.h"],
        },
    )
    env.expect.that_str(cfg.backend_macro).equals("setuptools_build")
    env.expect.that_collection(json.decode(cfg.macro_attrs["build_deps"])).contains_exactly([
        "@uv__build//cython:pkg",
        "@uv__build//setuptools:pkg",
        "@uv__build//wheel:pkg",
    ])
    env.expect.that_collection(cfg.site_paths).contains_exactly(["foo_pkg"])
    env.expect.that_collection(cfg.bin_paths).contains_exactly(["foo_cli"])
    env.expect.that_collection(cfg.data_paths).contains_exactly(["share"])
    env.expect.that_collection(cfg.include_paths).contains_exactly(["foo.h"])

def _test_extra_build_tools_auto_backend(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extra_build_tools_auto_backend_impl)

# ── Test: explicit build_backend preserves inspection metadata & requires ──

# buildifier: disable=unused-variable
def _test_explicit_build_backend_preserves_inspection_impl(env, target):
    """Explicit build_backend must still include inspected build_requires and path metadata."""
    cfg = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["setuptools", "wheel", "cython"],
            thin_repo = "uv__build",
            build_backend = "pep517_build",
            extra_build_tools = ["cython@3.0.0"],
        ),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": ["setuptools>=61", "wheel"],
            "site_paths": ["foo_pkg"],
            "bin_paths": ["foo_cli"],
            "data_paths": ["share"],
            "include_paths": ["foo.h"],
        },
    )
    env.expect.that_str(cfg.backend_macro).equals("pep517_build")
    env.expect.that_collection(json.decode(cfg.macro_attrs["build_deps"])).contains_exactly([
        "@uv__build//cython:pkg",
        "@uv__build//setuptools:pkg",
        "@uv__build//wheel:pkg",
    ])
    env.expect.that_collection(json.decode(cfg.macro_attrs["required_build_packages"])).contains_exactly([
        "setuptools",
        "wheel",
    ])
    env.expect.that_collection(cfg.site_paths).contains_exactly(["foo_pkg"])
    env.expect.that_collection(cfg.bin_paths).contains_exactly(["foo_cli"])
    env.expect.that_collection(cfg.data_paths).contains_exactly(["share"])
    env.expect.that_collection(cfg.include_paths).contains_exactly(["foo.h"])

def _test_explicit_build_backend_preserves_inspection(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_explicit_build_backend_preserves_inspection_impl)

# ── Test: wheel_file BUILD template includes all metadata paths ──────

# buildifier: disable=unused-variable
def _test_wheel_file_build_metadata_paths_impl(env, target):
    """render_wheel_file_build_for_testing must emit site_paths, bin_paths, data_paths, include_paths."""
    rendered = render_wheel_file_build_for_testing(
        filename = "foo-1.0.0-py3-none-any.whl",
        package_name = "foo",
        package_version = "1.0.0",
        inspection_data = {
            "site_paths": ["foo"],
            "bin_paths": ["foo-cli"],
            "data_paths": ["share"],
            "include_paths": ["foo.h"],
        },
    )
    env.expect.that_bool('site_paths = ["foo"],' in rendered).equals(True)
    env.expect.that_bool('bin_paths = ["foo-cli"],' in rendered).equals(True)
    env.expect.that_bool('data_paths = ["share"],' in rendered).equals(True)
    env.expect.that_bool('include_paths = ["foo.h"],' in rendered).equals(True)

def _test_wheel_file_build_metadata_paths(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_file_build_metadata_paths_impl)

# ── Test: package_repo _merge_dependencies merges all path fields ────

# buildifier: disable=unused-variable
def _test_merge_dependencies_paths_impl(env, target):
    """merge_dependencies_for_testing must merge site_paths, bin_paths, data_paths, include_paths."""
    entry_a = ("member_a", {"site_paths": ["foo"]})
    entry_b = ("member_b", {
        "bin_paths": ["foo-bin"],
        "data_paths": ["foo-data"],
        "include_paths": ["foo-inc"],
    })
    merged = merge_dependencies_for_testing(entry_a[1], [entry_a, entry_b])
    env.expect.that_collection(merged.get("site_paths", [])).contains_exactly(["foo"])
    env.expect.that_collection(merged.get("bin_paths", [])).contains_exactly(["foo-bin"])
    env.expect.that_collection(merged.get("data_paths", [])).contains_exactly(["foo-data"])
    env.expect.that_collection(merged.get("include_paths", [])).contains_exactly(["foo-inc"])

def _test_merge_dependencies_paths(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_dependencies_paths_impl)

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
            _test_extra_build_tools_auto_backend,
            _test_explicit_build_backend_preserves_inspection,
            _test_wheel_file_build_metadata_paths,
            _test_merge_dependencies_paths,
        ],
    )
