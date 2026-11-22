"""Tests for lock_repo_creation helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:lock_repo_creation.bzl",
    "compute_workspace_pkg_has_deps_for_testing",
    "remote_file_dedup_key_and_repo_name_for_testing",
)

# buildifier: disable=unused-variable
def _test_remote_file_dedup_key_and_repo_name_impl(env, target):
    """Filename-only remote files factor workspace pypi_indexes into cross-workspace dedup and repo names."""
    fn = remote_file_dedup_key_and_repo_name_for_testing
    key = "pkg-1.0-py3-none-any.whl/deadbeef"

    # Filename-only with no workspace indexes keeps the plain repo name.
    k_default, r_default = fn(key, {"name": "pkg-1.0-py3-none-any.whl"}, [])
    env.expect.that_str(r_default).equals("pypi_pkg_1_0_py3_none_any_whl_deadbeef")

    # Different workspace pypi_indexes get distinct dedup keys and distinct repo names.
    k_idx_a, r_idx_a = fn(key, {"name": "pkg-1.0-py3-none-any.whl"}, ["https://a.example.com/simple/"])
    k_idx_b, r_idx_b = fn(key, {"name": "pkg-1.0-py3-none-any.whl"}, ["https://b.example.com/simple/"])
    env.expect.that_bool(k_idx_a != k_default).equals(True)
    env.expect.that_bool(k_idx_a != k_idx_b).equals(True)
    env.expect.that_bool(r_idx_a != r_default).equals(True)
    env.expect.that_bool(r_idx_a != r_idx_b).equals(True)

    # Identical workspace pypi_indexes deduplicate together; different order does not.
    k_idx_ab, r_idx_ab = fn(key, {"name": "pkg-1.0-py3-none-any.whl"}, ["https://a.example.com/simple/", "https://b.example.com/simple/"])
    k_idx_ab2, r_idx_ab2 = fn(key, {"name": "pkg-1.0-py3-none-any.whl"}, ["https://a.example.com/simple/", "https://b.example.com/simple/"])
    k_idx_ba, r_idx_ba = fn(key, {"name": "pkg-1.0-py3-none-any.whl"}, ["https://b.example.com/simple/", "https://a.example.com/simple/"])
    env.expect.that_bool(k_idx_ab == k_idx_ab2).equals(True)
    env.expect.that_str(r_idx_ab).equals(r_idx_ab2)
    env.expect.that_bool(k_idx_ab != k_idx_ba).equals(True)
    env.expect.that_bool(r_idx_ab != r_idx_ba).equals(True)

    # Files with explicit urls or per-package index ignore workspace pypi_indexes.
    k_url, r_url = fn(key, {"name": "pkg-1.0-py3-none-any.whl", "urls": ["https://files.example.com/pkg.whl"]}, ["https://a.example.com/simple/"])
    env.expect.that_bool(k_url == k_default).equals(True)
    env.expect.that_str(r_url).equals(r_default)

    k_pkg_idx, r_pkg_idx = fn(key, {"name": "pkg-1.0-py3-none-any.whl", "index": "https://pkg.example.com/simple/"}, ["https://a.example.com/simple/"])
    env.expect.that_bool(k_pkg_idx == k_default).equals(True)
    env.expect.that_str(r_pkg_idx).equals(r_default)

def _test_remote_file_dedup_key_and_repo_name(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_remote_file_dedup_key_and_repo_name_impl)

# buildifier: disable=unused-variable
def _test_compute_workspace_pkg_has_deps_impl(env, target):
    """Multi-member workspaces record a package as having deps if any member lists marker_dependencies."""
    all_resolved_locks = {
        "ws__build": {
            "packages": {
                "pkg@1.0": {"marker_dependencies": []},
                "empty@1.0": {},
            },
        },
        "ws_app": {
            "packages": {
                "pkg@1.0": {"marker_dependencies": [{"key": "dep@1.0"}]},
            },
        },
        "other_ws": {
            "packages": {
                "pkg@1.0": {"marker_dependencies": []},
            },
        },
    }
    memberships = {
        "ws__build": "ws",
        "ws_app": "ws",
        "other_ws": "other_ws",
    }
    res = compute_workspace_pkg_has_deps_for_testing(all_resolved_locks, memberships)
    env.expect.that_bool(("ws", "pkg@1.0") in res).equals(True)
    env.expect.that_bool(("ws", "empty@1.0") in res).equals(False)
    env.expect.that_bool(("other_ws", "pkg@1.0") in res).equals(False)

def _test_compute_workspace_pkg_has_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_compute_workspace_pkg_has_deps_impl)

def lock_repo_creation_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_remote_file_dedup_key_and_repo_name,
            _test_compute_workspace_pkg_has_deps,
        ],
    )
