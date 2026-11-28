"""Tests for sdist build_deps deduplication via extract_pep508_name and dict-as-set.

Regression test for commit 8d8122f: when a pyproject.toml lists the same
build dependency multiple times (possibly via different specifiers),
the generated BUILD file must not contain duplicate label entries.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_contract.bzl", "is_extras_proxy")

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "merge_workspace_locks", "slim_member_lock")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:sdist_repo.bzl",
    "compute_sdist_build_config_for_testing",
    "render_build_content_for_testing",
    "select_hook_extract_patterns_for_testing",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "is_wheel_platform_specific")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_file.bzl", "render_wheel_file_build_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:availability.bzl", "availability_condition")

# ── Helpers ─────────────────────────────────────────────────────────

_TEST_BACKEND_TO_RULE = {
    "setuptools.build_meta": "setuptools_build",
    "scikit_build_core.build": "cmake_build",
}
_TEST_DEFAULT_BACKEND = "pep517_build"

def _make_attr(known_packages, thin_repo = "pypi", build_backend = "", extra_build_tools = None, override_backend_configs = ""):
    return struct(
        sdist = "@pypi_foo//:foo.tar.gz",
        deps = [],
        known_packages = known_packages,
        thin_repo = thin_repo,
        build_backend = build_backend,
        extra_build_tools = extra_build_tools or [],
        whldir_name = "",
        source_dir = "",
        override_backend_configs = override_backend_configs,
        pre_build_patches = [],
        site_hooks = [],
    )

def _build_deps_from_requires(requires, known_packages, thin_repo):
    """Run compute_sdist_build_config_for_testing and return (build_deps, required_build_packages)."""
    cfg = compute_sdist_build_config_for_testing(
        _make_attr(known_packages = known_packages, thin_repo = thin_repo),
        {"build_backend": "flit_core.buildapi", "build_requires": requires},
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = {},
        default_backend = _TEST_DEFAULT_BACKEND,
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
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = {},
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_str(cfg.backend_macro).equals("setuptools_build")
    env.expect.that_collection(json.decode(cfg.macro_attrs["build_deps"])).contains_exactly([
        "@uv__build//cython:pkg",
        "@uv__build//setuptools:pkg",
        "@uv__build//wheel:pkg",
    ])
    env.expect.that_collection(cfg.site_paths).contains_exactly(["foo_pkg"])
    env.expect.that_collection(cfg.bin_paths).contains_exactly(["foo_cli"])

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
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = {},
        default_backend = _TEST_DEFAULT_BACKEND,
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

def _test_explicit_build_backend_preserves_inspection(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_explicit_build_backend_preserves_inspection_impl)

# ── Test: wheel_file BUILD template includes all metadata paths ──────

# buildifier: disable=unused-variable
def _test_wheel_file_build_metadata_paths_impl(env, target):
    """render_wheel_file_build_for_testing must emit site_paths, bin_paths, data_paths, include_paths."""
    rendered = render_wheel_file_build_for_testing(
        filename = "foo-1.0.0-py3-none-any.whl",
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

# ── Test: merge_workspace_locks and slim_member_lock ────────────────

# buildifier: disable=unused-variable
def _test_merge_dependencies_paths_impl(env, target):
    """merge_workspace_locks merges path/marker/artifact fields once and slim_member_lock keeps thin repos in sync."""
    lock_a = {
        "packages": {
            "foo@1.0": {
                "site_paths": ["foo"],
                "wheel_candidates": [{"filename": "foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
                "availability_markers": ["sys_platform == 'linux'"],
            },
            "foo[extra]@1.0": {
                "cycle_group": "cycle_0",
                "marker_dependencies": [{"key": "dep@1.0"}],
            },
            "foo[x]@1.0": {
                "wheel_candidates": [{"filename": "foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
            },
            "plat@1.0": {
                "wheel_candidates": [{"filename": "plat-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
            },
        },
        "pins": {"foo": "foo@1.0", "foo[extra]": "foo[extra]@1.0", "foo[x]": "foo[x]@1.0", "plat": "plat@1.0"},
        "variants": [{"items": [{"kind": "extra", "package": "app", "name": "cpu", "flags": ["extra_cpu"]}]}],
    }
    lock_b = {
        "packages": {
            "foo@1.0": {
                "bin_paths": ["foo-bin"],
                "data_paths": ["foo-data"],
                "include_paths": ["foo-inc"],
                "sdist_file": {"key": "foo_sdist"},
                "wheel_candidates": [{"filename": "foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
                "availability_markers": ["sys_platform == 'darwin'", "sys_platform == 'linux'"],
            },
        },
        "pins": {"foo": "foo@1.0"},
        "variants": [{"items": [{"kind": "extra", "package": "app", "name": "cpu", "flags": ["extra_cpu"]}]}],
    }
    merged = merge_workspace_locks(
        [("member_a", lock_a), ("member_b", lock_b)],
        skip_variant_members = ["member_b"],
    )
    merged_foo = merged["packages"]["foo@1.0"]
    env.expect.that_collection(merged_foo.get("site_paths", [])).contains_exactly(["foo"])
    env.expect.that_collection(merged_foo.get("bin_paths", [])).contains_exactly(["foo-bin"])
    env.expect.that_collection(merged_foo.get("data_paths", [])).contains_exactly(["foo-data"])
    env.expect.that_collection(merged_foo.get("include_paths", [])).contains_exactly(["foo-inc"])
    env.expect.that_collection(merged_foo.get("availability_markers", [])).contains_exactly([
        "sys_platform == 'darwin'",
        "sys_platform == 'linux'",
    ]).in_order()
    env.expect.that_bool("member_a" in merged.get("member_variant_flags", {})).equals(True)
    env.expect.that_bool("member_b" in merged.get("member_variant_flags", {})).equals(False)

    # Slimming against merged_packages keeps wheel_platform_specific in sync with package_repo
    # (member_a was wheel-only, but member_b supplied an sdist) while keeping availability_markers
    # strictly per-member.
    slim_a = slim_member_lock(lock_a, merged["packages"])
    slim_foo = slim_a["packages"]["foo@1.0"]
    env.expect.that_bool(is_wheel_platform_specific(slim_foo)).equals(False)
    env.expect.that_bool(bool(slim_foo.get("sdist_file"))).equals(True)
    env.expect.that_collection(slim_foo.get("availability_markers", [])).contains_exactly([
        "sys_platform == 'linux'",
    ])

    # Wheel-only platform-specific package with no sdist in any member stays wheel_platform_specific.
    slim_plat = slim_a["packages"]["plat@1.0"]
    env.expect.that_bool(is_wheel_platform_specific(slim_plat)).equals(True)
    env.expect.that_bool(bool(slim_plat.get("sdist_file"))).equals(False)

    # Extras proxy keys drop cycle_group (thin repos always use _raw_) and still classify as extras proxies.
    slim_extra = slim_a["packages"]["foo[extra]@1.0"]
    env.expect.that_bool(is_extras_proxy("foo[extra]@1.0", slim_extra)).equals(True)
    env.expect.that_bool("extras_proxy" in slim_extra).equals(False)
    env.expect.that_bool("cycle_group" in slim_extra).equals(False)

    # resolution_marker_exprs is filtered to constraints referenced by this member's pins
    # (including base marker keys referenced by compound dicts).
    lock_filtered = dict(
        lock_a,
        pins = {
            "foo": {"extra_app_cpu_res_used": "foo@1.0"},
        },
        resolution_marker_exprs = {
            "extra_app_cpu_res_used": {"variant": "extra_app_cpu", "marker": "res_used"},
            "res_used": "sys_platform == 'linux'",
            "res_unused": "sys_platform == 'win32'",
        },
    )
    slim_filtered = slim_member_lock(lock_filtered, merged["packages"])
    env.expect.that_collection(slim_filtered["resolution_marker_exprs"].keys()).contains_exactly([
        "extra_app_cpu_res_used",
        "res_used",
    ])

    # Extras key with its own platform-specific wheel_candidates (e.g. local wheel)
    # must not be misclassified as an extras proxy delegating to the base package.
    slim_extra_whl = slim_a["packages"]["foo[x]@1.0"]
    env.expect.that_bool(is_extras_proxy("foo[x]@1.0", slim_extra_whl)).equals(False)
    env.expect.that_bool(is_wheel_platform_specific(slim_extra_whl)).equals(True)
    avail_lines = []
    avail_cond = availability_condition(avail_lines, "_maybe", "foo[x]@1.0", slim_a["packages"], "ws")
    env.expect.that_str(avail_cond).equals("@ws//_lock:_wheel_available_foo[x]@1.0")
    env.expect.that_collection(avail_lines).contains_exactly([])

def _test_merge_dependencies_paths(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_dependencies_paths_impl)

# ── Test: tool_deps populated from thin_repo (including build_tools_repo) ──

# buildifier: disable=unused-variable
def _test_tool_deps_from_thin_repo_impl(env, target):
    """tool_deps uses thin_repo (build_tools_repo or <ws>__build) and filters by known_packages."""
    backend_configs = {
        "setuptools_build": {
            "rule_bzl": "@rules_pycross//pycross/backends:setuptools.bzl",
            "tool_packages": ["setuptools", "wheel"],
        },
        "cmake_build": {
            "rule_bzl": "@rules_pycross//pycross/backends:cmake.bzl",
            "tool_packages": ["cmake", "ninja", "scikit-build-core"],
        },
    }

    # Default build repo with both setuptools and wheel in known_packages.
    cfg_default = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["setuptools", "wheel"],
            thin_repo = "uv__build",
        ),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": ["setuptools>=61"],
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = backend_configs,
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_collection(json.decode(cfg_default.macro_attrs["tool_deps"])).contains_exactly([
        "@uv__build//setuptools:pkg",
        "@uv__build//wheel:pkg",
    ])

    # Custom build_tools_repo where only cmake and scikit-build-core are in known_packages.
    cfg_custom = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["cmake", "scikit-build-core"],
            thin_repo = "custom_build_tools__build",
        ),
        {
            "build_backend": "scikit_build_core.build",
            "build_requires": ["scikit-build-core"],
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = backend_configs,
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_collection(json.decode(cfg_custom.macro_attrs["tool_deps"])).contains_exactly([
        "@custom_build_tools__build//cmake:pkg",
        "@custom_build_tools__build//scikit_build_core:pkg",
    ])

    # Custom build_tools_repo with none of the backend's tool_packages emits an explicit empty list
    # so the backend rule does not receive unexpected defaults.
    cfg_empty = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = [],
            thin_repo = "custom_build_tools__build",
        ),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": [],
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = backend_configs,
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_collection(json.decode(cfg_empty.macro_attrs["tool_deps"])).contains_exactly([])

    # override_backend_configs tool_deps replace the defaults per tool package name;
    # other tools keep their defaults, and keys are normalized.
    cfg_override = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["setuptools", "wheel"],
            thin_repo = "uv__build",
            override_backend_configs = json.encode({
                "setuptools_build": {
                    "tool_deps": json.encode({"SetupTools": "@@custom//setuptools:pkg"}),
                },
            }),
        ),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": [],
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = backend_configs,
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_collection(json.decode(cfg_override.macro_attrs["tool_deps"])).contains_exactly([
        "@@custom//setuptools:pkg",
        "@uv__build//wheel:pkg",
    ])

    # Override tool_deps can add tools missing from the lock, including repairwheel.
    cfg_add = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["cmake"],
            thin_repo = "uv__build",
            override_backend_configs = json.encode({
                "cmake_build": {
                    "tool_deps": json.encode({
                        "ninja": "@@other//ninja:pkg",
                        "repairwheel": "@@other//repairwheel:pkg",
                    }),
                },
            }),
        ),
        {
            "build_backend": "scikit_build_core.build",
            "build_requires": [],
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = backend_configs,
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_collection(json.decode(cfg_add.macro_attrs["tool_deps"])).contains_exactly([
        "@@other//ninja:pkg",
        "@@other//repairwheel:pkg",
        "@uv__build//cmake:pkg",
    ])

def _test_tool_deps_from_thin_repo(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_tool_deps_from_thin_repo_impl)

# ── Test: unknown tool_deps override key fails ──────────────────────

def _unknown_tool_dep_subject_impl(ctx):  # @unused
    compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["setuptools", "wheel"],
            override_backend_configs = json.encode({
                "setuptools_build": {
                    "tool_deps": json.encode({"pg_config": "@@//:pg_config"}),
                },
            }),
        ),
        {"build_backend": "setuptools.build_meta", "build_requires": []},
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = {
            "setuptools_build": {
                "rule_bzl": "@rules_pycross//pycross/backends:setuptools.bzl",
                "tool_packages": ["setuptools", "wheel"],
            },
        },
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    return []

_unknown_tool_dep_subject = rule(implementation = _unknown_tool_dep_subject_impl)

def _test_tool_deps_override_unknown_key_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("has unknown tool package 'pg_config'; setuptools_build accepts: repairwheel, setuptools, wheel"),
    )

def _test_tool_deps_override_unknown_key(name):
    util.helper_target(_unknown_tool_dep_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_tool_deps_override_unknown_key_impl,
        expect_failure = True,
    )

# ── Test: build_requires emission and backend resolution ────────────

# buildifier: disable=unused-variable
def _test_build_requires_and_backend_resolution_impl(env, target):
    """Emits only non-marker specifier-bearing build_requires, and resolves explicit/bracketed backends."""

    # 1. Versioned non-marker requires are forwarded; specifierless, marker-gated,
    #    and oldest-supported-numpy (calendar-versioned) entries are omitted.
    #    Also exercises the default @pycross_backends//:registry.bzl lookup.
    cfg_reqs = compute_sdist_build_config_for_testing(
        _make_attr(known_packages = ["setuptools", "wheel", "tomli", "numpy"]),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": [
                "setuptools>=40.8.0",
                "wheel",
                "tomli>=2.0; python_version < '3.11'",
                "oldest-supported-numpy>=2022.1",
            ],
        },
    )
    env.expect.that_str(cfg_reqs.backend_macro).equals("setuptools_build")
    env.expect.that_collection(json.decode(cfg_reqs.macro_attrs["build_requires"])).contains_exactly([
        "setuptools>=40.8.0",
    ])
    env.expect.that_collection(json.decode(cfg_reqs.macro_attrs["tool_deps"])).contains_exactly([
        "@pypi//setuptools:pkg",
        "@pypi//wheel:pkg",
    ])

    # 2. When no build_requires carry a version specifier, build_requires attr is omitted.
    cfg_no_spec = compute_sdist_build_config_for_testing(
        _make_attr(known_packages = ["setuptools", "wheel"]),
        {
            "build_backend": "setuptools.build_meta",
            "build_requires": ["setuptools", "wheel"],
        },
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = {},
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_bool("build_requires" in cfg_no_spec.macro_attrs).equals(False)

    # 3. Explicit-only registered backend (present only in backend_configs, not backend_to_rule),
    #    bracketed requires canonicalization, and repr() escaping on string override attrs.
    cfg_explicit = compute_sdist_build_config_for_testing(
        _make_attr(
            known_packages = ["setuptools"],
            build_backend = "custom_explicit_build",
            override_backend_configs = json.encode({
                "custom_explicit_build": {
                    "custom_flag": json.encode('-DFOO="bar"'),
                },
            }),
        ),
        {"build_backend": "setuptools.build_meta", "build_requires": ["setuptools"]},
        backend_to_rule = _TEST_BACKEND_TO_RULE,
        backend_configs = {
            "custom_explicit_build": {
                "rule_bzl": "//:custom.bzl",
                "tool_packages": [],
            },
        },
        default_backend = _TEST_DEFAULT_BACKEND,
    )
    env.expect.that_str(cfg_explicit.backend_macro).equals("custom_explicit_build")
    env.expect.that_str(cfg_explicit.macro_attrs["custom_flag"]).equals(repr('-DFOO="bar"'))

    cfg_bracket = compute_sdist_build_config_for_testing(
        struct(
            sdist = "@test_sdist//:file",
            deps = [],
            known_packages = ["setuptools", "setuptools-rust"],
            thin_repo = "pypi",
            build_backend = "",
            extra_build_tools = [],
            override_backend_configs = "",
            pre_build_patches = [],
            site_hooks = [],
            whldir_name = "test-1.0.whldir",
            source_dir = "",
        ),
        {"build_backend": "setuptools.build_meta", "build_requires": ["setuptools", "setuptools-rust>=1.0"]},
        backend_to_rule = {
            "setuptools.build_meta": "setuptools_build",
            "setuptools.build_meta[setuptools_rust]": "setuptools_rust_build",
        },
        backend_configs = {},
        default_backend = "pep517_build",
    )
    env.expect.that_str(cfg_bracket.backend_macro).equals("setuptools_rust_build")

def _test_build_requires_and_backend_resolution(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_requires_and_backend_resolution_impl)

# ── Test: marker-gated requires are not required ────────────────────

# buildifier: disable=unused-variable
def _test_marker_gated_requires_impl(env, target):
    """Marker-gated build-system.requires may not apply to the target, so pep517_build must not require them."""
    deps, pkgs = _build_deps_from_requires(
        ["flit_core>=3.4", "tomli; python_version < '3.11'"],
        ["flit-core", "tomli"],
        "pypi",
    )
    env.expect.that_collection(deps).contains_exactly(["@pypi//flit_core:pkg", "@pypi//tomli:pkg"])
    env.expect.that_collection(pkgs).contains_exactly(["flit-core"])

def _test_marker_gated_requires(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_gated_requires_impl)

# ── Test: select_hook_extract_patterns ──────────────────────────────

# buildifier: disable=unused-variable
def _test_select_hook_extract_patterns_impl(env, target):
    hook_files = {
        "maturin_build": ["pyproject.toml", "**/Cargo.lock"],
        "setuptools_rust_build": ["pyproject.toml", "**/Cargo.lock"],
    }

    # Explicit non-hook backend extracts nothing.
    env.expect.that_collection(
        select_hook_extract_patterns_for_testing(
            _make_attr([], build_backend = "setuptools_build"),
            hook_files,
            backend_to_rule = _TEST_BACKEND_TO_RULE,
            default_backend = _TEST_DEFAULT_BACKEND,
        ),
    ).contains_exactly([])

    # Explicit hook backend extracts only its patterns.
    env.expect.that_collection(
        select_hook_extract_patterns_for_testing(
            _make_attr([], build_backend = "maturin_build"),
            hook_files,
            backend_to_rule = _TEST_BACKEND_TO_RULE,
            default_backend = _TEST_DEFAULT_BACKEND,
        ),
    ).contains_exactly(["**/Cargo.lock", "pyproject.toml"]).in_order()

    # Auto-detect with no hook backend in backend_to_rule extracts nothing.
    env.expect.that_collection(
        select_hook_extract_patterns_for_testing(
            _make_attr([]),
            hook_files,
            backend_to_rule = _TEST_BACKEND_TO_RULE,
            default_backend = _TEST_DEFAULT_BACKEND,
        ),
    ).contains_exactly([])

    # Auto-detect with a registered hook backend deduplicates and sorts patterns.
    env.expect.that_collection(
        select_hook_extract_patterns_for_testing(
            struct(build_backend = ""),
            hook_files,
            backend_to_rule = {"maturin": "maturin_build", "setuptools.build_meta": "setuptools_build"},
            default_backend = "pep517_build",
        ),
    ).contains_exactly(["**/Cargo.lock", "pyproject.toml"]).in_order()

def _test_select_hook_extract_patterns(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_select_hook_extract_patterns_impl)

# ── Test: render_build_content emits direct rule_bzl load ───────────

# buildifier: disable=unused-variable
def _test_render_build_content_direct_load_impl(env, target):
    """_render_build_content loads the backend rule directly from rule_bzl, not @<lock_repo>//_backend."""
    rendered = render_build_content_for_testing(
        macro_attrs = {
            "name": repr("wheel_build"),
            "sdist": repr("@pypi_foo//:foo.tar.gz"),
            "deps": "[]",
            "tool_deps": '["@uv__build//setuptools:pkg"]',
        },
        backend_macro = "setuptools_build",
        rule_bzl = "@rules_pycross//pycross/backends:setuptools.bzl",
        site_paths = ["foo"],
        bin_paths = [],
    )
    env.expect.that_bool(
        'load("@rules_pycross//pycross/backends:setuptools.bzl", "setuptools_build")' in rendered,
    ).equals(True)
    env.expect.that_bool("//_backend:" in rendered).equals(False)
    env.expect.that_bool("setuptools_build(" in rendered).equals(True)

def _test_render_build_content_direct_load(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_build_content_direct_load_impl)

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
            _test_tool_deps_from_thin_repo,
            _test_tool_deps_override_unknown_key,
            _test_build_requires_and_backend_resolution,
            _test_marker_gated_requires,
            _test_select_hook_extract_patterns,
            _test_render_build_content_direct_load,
        ],
    )
