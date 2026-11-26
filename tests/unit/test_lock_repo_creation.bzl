"""Tests for lock_repo_creation helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:lock_contract.bzl",
    "build_repo_name",
    "is_extras_proxy",
    "local_lock_target_label",
    "lock_constraint_label",
    "pkgs_repo_name",
    "sdist_repo_name",
    "whldir_name",
)

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:lock_repo_creation.bzl",
    "extra_build_tool_names_for_testing",
    "known_packages_from_lock_for_testing",
    "remote_file_dedup_key_and_repo_name_for_testing",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "merge_workspace_locks")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "canonicalize_package_key", "parse_flag_arg")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_util.bzl", "split_variant_tokens", "variant_set_suffix")

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
def _test_merge_workspace_locks_marker_deps_impl(env, target):
    """Multi-member merge retains marker_dependencies if any member lists them."""
    ws_merged = merge_workspace_locks([
        ("ws__build", {
            "packages": {
                "pkg@1.0": {"marker_dependencies": []},
                "empty@1.0": {},
            },
        }),
        ("ws_app", {
            "packages": {
                "pkg@1.0": {"marker_dependencies": [{"key": "dep@1.0"}]},
            },
        }),
    ])
    other_merged = merge_workspace_locks([
        ("other_ws", {
            "packages": {
                "pkg@1.0": {"marker_dependencies": []},
            },
        }),
    ])
    env.expect.that_bool(bool(ws_merged["packages"]["pkg@1.0"].get("marker_dependencies"))).equals(True)
    env.expect.that_bool(bool(ws_merged["packages"]["empty@1.0"].get("marker_dependencies"))).equals(False)
    env.expect.that_bool(bool(other_merged["packages"]["pkg@1.0"].get("marker_dependencies"))).equals(False)

def _test_merge_workspace_locks_marker_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_workspace_locks_marker_deps_impl)

# buildifier: disable=unused-variable
def _test_known_packages_from_lock_impl(env, target):
    """known_packages uses sorted, deduplicated canonical pin names independent of versions."""
    lock_v1 = {
        "pins": {
            "Setuptools": "setuptools@68.0.0",
            "setuptools[extra]": "setuptools[extra]@68.0.0",
            "My_Pkg": {"cpu": "my-pkg@1.0.0", "gpu": "my-pkg@2.0.0"},
        },
        "packages": {
            "setuptools@68.0.0": {},
            "unpinned-transitive@0.1.0": {},
        },
    }
    lock_v2 = {
        "pins": {
            "my-pkg": "my-pkg@3.0.0",
            "setuptools": "setuptools@75.0.0",
        },
        "packages": {
            "setuptools@75.0.0": {},
        },
    }
    expected = ["my-pkg", "setuptools"]
    env.expect.that_collection(known_packages_from_lock_for_testing(lock_v1)).contains_exactly(expected).in_order()
    env.expect.that_collection(known_packages_from_lock_for_testing(lock_v2)).contains_exactly(expected).in_order()

    # extra_build_tools strips versions and deduplicates/sorts canonical names.
    tools_v1 = extra_build_tool_names_for_testing(["Setuptools@68.0.0", "my_tool@1.0.0", "setuptools@68.0.0"])
    tools_v2 = extra_build_tool_names_for_testing(["my-tool@2.0.0", "setuptools@75.0.0"])
    env.expect.that_collection(tools_v1).contains_exactly(["my-tool", "setuptools"]).in_order()
    env.expect.that_collection(tools_v2).contains_exactly(["my-tool", "setuptools"]).in_order()

def _test_known_packages_from_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_known_packages_from_lock_impl)

# buildifier: disable=unused-variable
def _test_lock_contract_and_helpers_impl(env, target):
    """Verify shared lock_contract, canonicalize_package_key, parse_flag_arg, and variant_util helpers."""
    env.expect.that_str(pkgs_repo_name("uv")).equals("uv__pkgs")
    env.expect.that_str(build_repo_name("uv")).equals("uv__build")
    env.expect.that_str(sdist_repo_name("uv__pkgs", "my-pkg@1.0.0~deadbeef")).equals("uv__pkgs_sdist_my_pkg_1_0_0_deadbeef")
    env.expect.that_str(local_lock_target_label("_wheel_foo@1.0")).equals("//_lock:_wheel_foo@1.0")
    env.expect.that_str(lock_constraint_label("uv__pkgs", "extra_cpu")).equals("@uv__pkgs//_lock:is_extra_cpu")
    env.expect.that_str(whldir_name("Typing_Extensions@4.12.2")).equals("typing_extensions-4.12.2.whldir")
    env.expect.that_str(whldir_name("torch@2.5.0~abcd1234")).equals("torch-2.5.0~abcd1234.whldir")
    env.expect.that_bool(is_extras_proxy("foo[bar]@1.0", {})).equals(True)
    env.expect.that_bool(is_extras_proxy("foo[bar]@1.0", {"wheel_candidates": [{"filename": "foo.whl"}]})).equals(False)
    env.expect.that_bool(is_extras_proxy("foo@1.0", {})).equals(False)

    canon = canonicalize_package_key("Foo_Bar[My_Extra]@1.0~abcd1234")
    env.expect.that_str(canon.canonical).equals("foo-bar[my-extra]@1.0~abcd1234")
    env.expect.that_bool(canon.has_version).equals(True)
    env.expect.that_bool(canon.has_tag).equals(True)
    env.expect.that_str(canonicalize_package_key("*", allow_wildcard = True).canonical).equals("*")

    parsed_flag = parse_flag_arg("--@repo//_variants:extra_a")
    env.expect.that_str(parsed_flag.label).equals("@repo//_variants:extra_a")
    env.expect.that_str(parsed_flag.value).equals("True")
    env.expect.that_bool(parsed_flag.has_value).equals(False)

    env.expect.that_str(variant_set_suffix(["b", "a"])).equals("a_b")
    env.expect.that_collection(split_variant_tokens(" a , , b ")).contains_exactly(["a", "b"]).in_order()
    env.expect.that_collection(split_variant_tokens("")).contains_exactly([])

def _test_lock_contract_and_helpers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_lock_contract_and_helpers_impl)

def _empty_workspace_repo_subject_impl(_ctx):
    lock_constraint_label("", "extra_cpu")
    return []

_empty_workspace_repo_subject = rule(implementation = _empty_workspace_repo_subject_impl)

def _test_lock_contract_rejects_empty_workspace_repo_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("lock_target_label requires a non-empty repository name"),
    )

def _test_lock_contract_rejects_empty_workspace_repo(name):
    util.helper_target(_empty_workspace_repo_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_lock_contract_rejects_empty_workspace_repo_impl,
        expect_failure = True,
    )

def lock_repo_creation_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_remote_file_dedup_key_and_repo_name,
            _test_merge_workspace_locks_marker_deps,
            _test_known_packages_from_lock,
            _test_lock_contract_and_helpers,
            _test_lock_contract_rejects_empty_workspace_repo,
        ],
    )
