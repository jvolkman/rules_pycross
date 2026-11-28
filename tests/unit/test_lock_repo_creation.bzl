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
    "filter_package_repo_overrides_for_testing",
    "known_packages_from_lock_for_testing",
    "slim_thin_repo_overrides_for_testing",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "PASSTHROUGH_PACKAGE_ATTRS")

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "merge_workspace_locks", "slim_workspace_lock")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:repo_slots.bzl",
    "assign_fork_slots",
    "plan_workspace_remote_slots",
    "sdist_slot_repo_name",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "canonicalize_package_key", "parse_flag_arg")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_util.bzl", "split_variant_tokens", "variant_set_suffix")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:metadata.bzl", "hook_subdir_build")

# buildifier: disable=unused-variable
def _test_workspace_remote_slots_impl(env, target):
    """Workspace-scoped remote file and sdist slots stay version-free and collision-free."""
    pkgs_v1 = {
        "requests@2.32.3": {
            "wheel_candidates": [
                {"filename": "requests-2.32.3-py3-none-any.whl", "file_reference": {"key": "req_whl_v1"}},
            ],
            "sdist_file": {"key": "req_sdist_v1"},
        },
        "numpy@1.26.4": {
            "wheel_candidates": [
                {"filename": "numpy-1.26.4-cp311-cp311-manylinux_2_17_x86_64.whl", "file_reference": {"key": "np1_whl"}},
            ],
        },
        "numpy@2.2.0": {
            "wheel_candidates": [
                {"filename": "numpy-2.2.0-cp312-cp312-manylinux_2_17_x86_64.whl", "file_reference": {"key": "np2_whl"}},
            ],
        },
        "numpy[extra]@2.2.0": {},
        "torch@2.9.1~aaaa1111": {
            "wheel_candidates": [
                {"filename": "torch-2.9.1-cp312-none-macosx_11_0_arm64.whl", "file_reference": {"key": "t_a"}},
            ],
        },
        "torch@2.9.1~bbbb2222": {
            "wheel_candidates": [
                {"filename": "torch-2.9.1-cp312-none-macosx_11_0_arm64.whl", "file_reference": {"key": "t_b"}},
            ],
        },
        "buildtag@1.0.0": {
            "wheel_candidates": [
                {"filename": "buildtag-1.0.0-1-py3-none-any.whl", "file_reference": {"key": "bt1"}},
                {"filename": "buildtag-1.0.0-2-py3-none-any.whl", "file_reference": {"key": "bt2"}},
            ],
        },
        "collide@1.0.0": {
            "wheel_candidates": [
                {"filename": "collide-1.0.0-py2.py3-none-any.whl", "file_reference": {"key": "col1"}},
                {"filename": "collide-1.0.0-py2_py3-none-any.whl", "file_reference": {"key": "col2"}},
                {
                    "filename": "collide-1.0.0-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_28_x86_64.whl",
                    "file_reference": {"key": "long1"},
                },
            ],
        },
    }
    remote_v1 = {
        "req_whl_v1": {"name": "requests-2.32.3-py3-none-any.whl"},
        "req_sdist_v1": {"name": "requests-2.32.3.tar.gz"},
        "np1_whl": {"name": "numpy-1.26.4-cp311-cp311-manylinux_2_17_x86_64.whl"},
        "np2_whl": {"name": "numpy-2.2.0-cp312-cp312-manylinux_2_17_x86_64.whl"},
        "t_a": {"name": "torch-2.9.1-cp312-none-macosx_11_0_arm64.whl"},
        "t_b": {"name": "torch-2.9.1-cp312-none-macosx_11_0_arm64.whl"},
        "bt1": {"name": "buildtag-1.0.0-1-py3-none-any.whl"},
        "bt2": {"name": "buildtag-1.0.0-2-py3-none-any.whl"},
        "col1": {"name": "collide-1.0.0-py2.py3-none-any.whl"},
        "col2": {"name": "collide-1.0.0-py2_py3-none-any.whl"},
        "long1": {"name": "collide-1.0.0-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_28_x86_64.whl"},
    }

    slots_v1 = assign_fork_slots(pkgs_v1)
    env.expect.that_str(slots_v1["requests@2.32.3"]).equals("")
    env.expect.that_str(slots_v1["numpy@1.26.4"]).equals("s0")
    env.expect.that_str(slots_v1["numpy@2.2.0"]).equals("s1")
    env.expect.that_str(slots_v1["numpy[extra]@2.2.0"]).equals("s1")
    env.expect.that_str(slots_v1["torch@2.9.1~aaaa1111"]).equals("s0")
    env.expect.that_str(slots_v1["torch@2.9.1~bbbb2222"]).equals("s1")

    map_v1 = plan_workspace_remote_slots("ws_a", pkgs_v1, remote_v1, fork_slots = slots_v1)
    env.expect.that_str(map_v1["req_whl_v1"]).equals("ws_a__whl_requests_py3_none_any")
    env.expect.that_str(map_v1["req_sdist_v1"]).equals("ws_a__sdist_file_requests")
    env.expect.that_str(sdist_slot_repo_name("ws_a", "requests@2.32.3", "")).equals("ws_a__sdist_requests")
    env.expect.that_str(sdist_slot_repo_name("ws_a", "numpy@2.2.0", "s1")).equals("ws_a__sdist_numpy_s1")

    # Multi-source forks and PEP 427 build tags get distinct repo names.
    env.expect.that_bool(map_v1["t_a"] != map_v1["t_b"]).equals(True)
    env.expect.that_bool(map_v1["bt1"] != map_v1["bt2"]).equals(True)
    env.expect.that_bool(map_v1["col1"] != map_v1["col2"]).equals(True)

    # Long wheel tag names are truncated + hashed to keep repo names bounded.
    env.expect.that_bool(len(map_v1["long1"]) <= len("ws_a__whl_collide_") + 48).equals(True)

    # Workspace isolation: another workspace gets distinct repo names.
    map_ws_b = plan_workspace_remote_slots("ws_b", pkgs_v1, remote_v1, fork_slots = slots_v1)
    env.expect.that_str(map_ws_b["req_whl_v1"]).equals("ws_b__whl_requests_py3_none_any")
    env.expect.that_bool(map_v1["req_whl_v1"] != map_ws_b["req_whl_v1"]).equals(True)

    # Bumping requests 2.32.3 -> 2.32.4 and numpy 1.26.4/2.2.0 -> 1.26.5/2.2.1 preserves all repo names.
    pkgs_v2 = {
        "requests@2.32.4": {
            "wheel_candidates": [
                {"filename": "requests-2.32.4-py3-none-any.whl", "file_reference": {"key": "req_whl_v2"}},
            ],
            "sdist_file": {"key": "req_sdist_v2"},
        },
        "numpy@1.26.5": {
            "wheel_candidates": [
                {"filename": "numpy-1.26.5-cp311-cp311-manylinux_2_17_x86_64.whl", "file_reference": {"key": "np1_whl_v2"}},
            ],
        },
        "numpy@2.2.1": {
            "wheel_candidates": [
                {"filename": "numpy-2.2.1-cp312-cp312-manylinux_2_17_x86_64.whl", "file_reference": {"key": "np2_whl_v2"}},
            ],
        },
    }
    remote_v2 = {
        "req_whl_v2": {"name": "requests-2.32.4-py3-none-any.whl"},
        "req_sdist_v2": {"name": "requests-2.32.4.tar.gz"},
        "np1_whl_v2": {"name": "numpy-1.26.5-cp311-cp311-manylinux_2_17_x86_64.whl"},
        "np2_whl_v2": {"name": "numpy-2.2.1-cp312-cp312-manylinux_2_17_x86_64.whl"},
    }
    map_v2 = plan_workspace_remote_slots("ws_a", pkgs_v2, remote_v2)
    env.expect.that_str(map_v2["req_whl_v2"]).equals(map_v1["req_whl_v1"])
    env.expect.that_str(map_v2["req_sdist_v2"]).equals(map_v1["req_sdist_v1"])
    env.expect.that_str(map_v2["np1_whl_v2"]).equals(map_v1["np1_whl"])
    env.expect.that_str(map_v2["np2_whl_v2"]).equals(map_v1["np2_whl"])

def _test_workspace_remote_slots(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_workspace_remote_slots_impl)

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

_SDIST_ONLY_PASSTHROUGH_ATTRS = {
    "build_backend": True,
    "build_tools_repo": True,
    "pre_build_patches": True,
    "site_hooks": True,
}

# buildifier: disable=unused-variable
def _test_slim_workspace_lock_impl(env, target):
    """slim_workspace_lock drops sdist-only/default fields and keeps package_repo fields intact."""
    merged_v1 = {
        "packages": {
            "default-pkg@1.0": {
                "name": "default-pkg",
                "version": "1.0",
                "marker_dependencies": [],
                "wheel_candidates": [{"filename": "default_pkg-1.0-py3-none-any.whl", "file_reference": {"key": "k1"}}],
                "sdist_file": None,
                "availability_markers": [],
                "extra_build_tools": ["cython@3.0.0"],
                "build_backend": "setuptools_build",
                "build_target": None,
                "build_mode": "auto",
                "build_tools_repo": "uv__build",
                "install_exclude_globs": [],
                "post_install_patches": [],
                "pre_build_patches": ["@@//patches:a.patch"],
                "site_hooks": ["import foo"],
                "site_paths": [],
                "bin_paths": [],
                "data_paths": [],
                "include_paths": [],
                "wheel_library_tags": [],
                "precompile": "",
                "source_dir": "sub/dir",
            },
            "full-pkg@2.0": {
                "name": "full-pkg",
                "version": "2.0",
                "marker_dependencies": [{"key": "dep@1.0", "marker": "sys_platform == 'linux'"}],
                "wheel_candidates": [{"filename": "full_pkg-2.0-cp312-cp312-manylinux.whl", "file_reference": {"key": "k2"}}],
                "sdist_file": {"key": "s2"},
                "availability_markers": ["sys_platform == 'linux'"],
                "cycle_group": "group_1234",
                "extra_build_tools": ["setuptools@68.0.0"],
                "build_backend": "cmake_build",
                "build_target": "@@//custom:full",
                "build_mode": "never",
                "build_tools_repo": "custom__build",
                "install_exclude_globs": ["tests/**"],
                "post_install_patches": ["@@//patches:post.patch"],
                "pre_build_patches": ["@@//patches:pre.patch"],
                "site_hooks": ["import bar"],
                "site_paths": ["full_pkg"],
                "bin_paths": ["full-cli"],
                "data_paths": ["share"],
                "include_paths": ["full.h"],
                "wheel_library_tags": ["manual"],
                "precompile": "enabled",
                "source_dir": "packages/full",
            },
            "always-pkg@3.0": {
                "name": "always-pkg",
                "version": "3.0",
                "sdist_file": {"key": "s3"},
                "build_mode": "always",
                "extra_build_tools": ["wheel@0.43.0"],
            },
        },
        "cycle_groups": {"group_1234": ["full-pkg@2.0", "other@1.0"]},
        "resolution_marker_exprs": {"res_foo_1_0": "sys_platform == 'linux'"},
        "variant_items": {"extra_app_cpu": True},
        "variant_sets": [{"qnames": ["extra_app_cpu"], "flags": {}, "member_flags": {}}],
        "member_variant_flags": {"app": {"extra_cpu": True}},
    }

    slim_v1 = slim_workspace_lock(merged_v1)

    # Top-level non-package keys are preserved unchanged.
    env.expect.that_dict(slim_v1["cycle_groups"]).contains_exactly(merged_v1["cycle_groups"])
    env.expect.that_dict(slim_v1["resolution_marker_exprs"]).contains_exactly(merged_v1["resolution_marker_exprs"])
    env.expect.that_dict(slim_v1["variant_items"]).contains_exactly(merged_v1["variant_items"])
    env.expect.that_collection(slim_v1["variant_sets"]).contains_exactly(merged_v1["variant_sets"])
    env.expect.that_dict(slim_v1["member_variant_flags"]).contains_exactly(merged_v1["member_variant_flags"])

    # Default/empty and sdist-only fields are dropped; only wheel_candidates remains on default-pkg.
    env.expect.that_collection(slim_v1["packages"]["default-pkg@1.0"].keys()).contains_exactly([
        "wheel_candidates",
    ])

    # All non-default package_repo fields are preserved on full-pkg; sdist-only & name/version dropped.
    slim_full = slim_v1["packages"]["full-pkg@2.0"]
    env.expect.that_collection(slim_full.keys()).contains_exactly([
        "availability_markers",
        "bin_paths",
        "build_mode",
        "build_target",
        "cycle_group",
        "data_paths",
        "include_paths",
        "install_exclude_globs",
        "marker_dependencies",
        "post_install_patches",
        "precompile",
        "sdist_file",
        "site_paths",
        "wheel_candidates",
        "wheel_library_tags",
    ])
    env.expect.that_str(slim_full["build_mode"]).equals("never")
    env.expect.that_str(slim_full["precompile"]).equals("enabled")
    env.expect.that_collection(slim_full["post_install_patches"]).contains_exactly(["@@//patches:post.patch"])
    env.expect.that_str(slim_v1["packages"]["always-pkg@3.0"]["build_mode"]).equals("always")

    # Bumping extra_build_tools versions or editing sdist-only fields leaves slim_workspace_lock identical.
    merged_v2 = dict(merged_v1)
    merged_v2["packages"] = {k: dict(v) for k, v in merged_v1["packages"].items()}
    merged_v2["packages"]["default-pkg@1.0"]["extra_build_tools"] = ["cython@3.1.0"]
    merged_v2["packages"]["default-pkg@1.0"]["pre_build_patches"] = ["@@//patches:b.patch"]
    merged_v2["packages"]["default-pkg@1.0"]["site_hooks"] = ["import baz"]
    merged_v2["packages"]["full-pkg@2.0"]["extra_build_tools"] = ["setuptools@75.0.0"]
    merged_v2["packages"]["full-pkg@2.0"]["build_backend"] = "meson_build"
    merged_v2["packages"]["full-pkg@2.0"]["build_tools_repo"] = "other__build"
    merged_v2["packages"]["full-pkg@2.0"]["source_dir"] = "other/dir"
    env.expect.that_str(json.encode(slim_workspace_lock(merged_v2))).equals(json.encode(slim_v1))

    # Drift guard: every PASSTHROUGH_PACKAGE_ATTRS key must either be retained by
    # slim_workspace_lock or explicitly classified as sdist-repo-only.
    all_passthrough_pkg = {
        field: (["val"] if type(default) == "list" else "never" if field == "build_mode" else "val")
        for field, (default, _mode) in PASSTHROUGH_PACKAGE_ATTRS.items()
    }
    slim_passthrough = slim_workspace_lock({"packages": {"drift@1.0": all_passthrough_pkg}})["packages"]["drift@1.0"]
    env.expect.that_collection(slim_passthrough.keys()).contains_exactly([
        field
        for field in PASSTHROUGH_PACKAGE_ATTRS
        if field not in _SDIST_ONLY_PASSTHROUGH_ATTRS
    ])

def _test_slim_workspace_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_slim_workspace_lock_impl)

# buildifier: disable=unused-variable
def _test_filter_and_slim_repo_overrides_impl(env, target):
    """Filter non-hook overrides for package_repo and strip attr values for thin_package_repo."""
    hooks = {
        "maturin_build": True,
        "setuptools_rust_build": True,
        "custom_subdir_build": True,
        "no_subdir_hook_build": True,
    }
    hook_subdirs = {
        "maturin_build": "_cargo",
        "setuptools_rust_build": "_cargo",
        "custom_subdir_build": "_custom",
        "no_subdir_hook_build": "",
    }

    # 1. C/C++ overrides without package_repo hooks are completely stripped from both.
    cc_only = {
        "*": {"setuptools_build": {"copts": '["-O2"]'}},
        "numpy": {"meson_build": {"build_env": '{"FOO": "1"}'}},
        "scipy@1.14.0": {"cmake_build": {"cmake_args": '["-DFOO=ON"]'}},
    }
    env.expect.that_dict(filter_package_repo_overrides_for_testing(cc_only, hooks)).contains_exactly({})
    env.expect.that_dict(slim_thin_repo_overrides_for_testing(cc_only, hooks, hook_subdirs)).contains_exactly({})

    # 2. Hook-backed overrides preserve full attrs for package_repo and strip to {} for thin_package_repo.
    #    A hook backend with package_repo_hook_subdir = "" is kept for package_repo and omitted from thin_package_repo.
    mixed_v1 = {
        "*": {
            "setuptools_build": {"copts": '["-O2"]'},
            "maturin_build": {"build_env": '{"RUSTFLAGS": "-C target-cpu=native"}'},
        },
        "jiter": {
            "maturin_build": {"cargo_lock": '"@@//cargo:jiter.lock"', "copts": '["-O2"]'},
            "setuptools_build": {"copts": '["-Wall"]'},
        },
        "cryptography@43.0.0": {
            "setuptools_rust_build": {"cargo_lock": '"@@//cargo:crypto.lock"'},
        },
        "custom-pkg": {
            "custom_subdir_build": {"flag": '"v1"'},
        },
        "nosubdir-pkg": {
            "no_subdir_hook_build": {"opt": '"x"'},
        },
    }
    pkg_filtered = filter_package_repo_overrides_for_testing(mixed_v1, hooks)
    env.expect.that_dict(pkg_filtered).contains_exactly({
        "*": {"maturin_build": {"build_env": '{"RUSTFLAGS": "-C target-cpu=native"}'}},
        "jiter": {"maturin_build": {"cargo_lock": '"@@//cargo:jiter.lock"', "copts": '["-O2"]'}},
        "cryptography@43.0.0": {"setuptools_rust_build": {"cargo_lock": '"@@//cargo:crypto.lock"'}},
        "custom-pkg": {"custom_subdir_build": {"flag": '"v1"'}},
        "nosubdir-pkg": {"no_subdir_hook_build": {"opt": '"x"'}},
    })

    thin_v1 = slim_thin_repo_overrides_for_testing(mixed_v1, hooks, hook_subdirs)
    env.expect.that_dict(thin_v1).contains_exactly({
        "*": {"maturin_build": {}},
        "jiter": {"maturin_build": {}},
        "cryptography@43.0.0": {"setuptools_rust_build": {}},
        "custom-pkg": {"custom_subdir_build": {}},
    })

    # Changing copts, cargo_lock, build_env, or C/C++ overrides leaves thin_repo_overrides identical.
    mixed_v2 = {
        "*": {
            "setuptools_build": {"copts": '["-O3"]'},
            "maturin_build": {"build_env": '{"RUSTFLAGS": "-C opt-level=3"}'},
        },
        "jiter": {
            "maturin_build": {"cargo_lock": '"@@//cargo:jiter_new.lock"', "copts": '["-O3"]'},
        },
        "cryptography@43.0.0": {
            "setuptools_rust_build": {"cargo_lock": '"@@//cargo:crypto_v2.lock"'},
        },
        "custom-pkg": {
            "custom_subdir_build": {"flag": '"v2"'},
        },
        "nosubdir-pkg": {
            "no_subdir_hook_build": {"opt": '"y"'},
        },
    }
    env.expect.that_str(json.encode(slim_thin_repo_overrides_for_testing(mixed_v2, hooks, hook_subdirs))).equals(
        json.encode(thin_v1),
    )

    # 3. Legacy cargo backends without an entry in hook_subdirs still map to thin-repo overrides.
    thin_legacy = slim_thin_repo_overrides_for_testing(
        {"jiter": {"maturin_build": {"cargo_lock": '"@@//:Cargo.lock"'}}},
        {"maturin_build": True},
        {},
    )
    env.expect.that_dict(thin_legacy).contains_exactly({"jiter": {"maturin_build": {}}})

    # 4. hook_subdir_build produces identical _cargo/BUILD.bazel for full vs slimmed overrides.
    grouped_pins = {
        "jiter": {"base_target": {"": "jiter@0.5.0"}, "extras": {}},
        "cryptography": {"base_target": {"": "cryptography@43.0.0"}, "extras": {}},
        "other": {"base_target": {"": "other@1.0.0"}, "extras": {}},
    }
    packages = {
        "jiter@0.5.0": {"sdist_file": True},
        "cryptography@43.0.0": {"sdist_file": True},
        "other@1.0.0": {"sdist_file": True},
    }
    full_cargo = hook_subdir_build(
        grouped_pins,
        packages,
        mixed_v1,
        "ws__pkgs",
        hook_backends = ["maturin_build", "setuptools_rust_build"],
        subdir = "_cargo",
    )
    slim_cargo = hook_subdir_build(
        grouped_pins,
        packages,
        thin_v1,
        "ws__pkgs",
        hook_backends = ["maturin_build", "setuptools_rust_build"],
        subdir = "_cargo",
    )
    env.expect.that_bool(full_cargo != None and slim_cargo != None).equals(True)
    env.expect.that_str(slim_cargo.build).equals(full_cargo.build)

def _test_filter_and_slim_repo_overrides(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_filter_and_slim_repo_overrides_impl)

def lock_repo_creation_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_workspace_remote_slots,
            _test_merge_workspace_locks_marker_deps,
            _test_known_packages_from_lock,
            _test_lock_contract_and_helpers,
            _test_lock_contract_rejects_empty_workspace_repo,
            _test_slim_workspace_lock,
            _test_filter_and_slim_repo_overrides,
        ],
    )
