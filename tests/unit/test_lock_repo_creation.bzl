"""Tests for lock_repo_creation helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:lock_contract.bzl",
    "build_repo_name",
    "is_extras_proxy",
    "member_constraint_label",
    "spoke_repo_name",
    "spoke_slot_label",
    "state_constraint_label",
    "state_repo_name",
    "whldir_name",
)

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:lock_repo_creation.bzl",
    "extra_build_tool_names_for_testing",
    "filter_package_repo_overrides_for_testing",
    "filter_spoke_overrides_for_testing",
    "known_packages_from_lock_for_testing",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "PASSTHROUGH_PACKAGE_ATTRS")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:repo_slots.bzl",
    "assign_fork_slots",
    "plan_workspace_remote_slots",
    "sdist_slot_repo_name",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:spoke_repo.bzl", "build_spoke_payloads")

# buildifier: disable=bzl-visibility
load("//pycross/private:state_repo.bzl", "merge_workspace_locks", "slim_member_lock", "spoke_hook_backend_subdirs")

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
    env.expect.that_str(state_repo_name("uv")).equals("uv__state")
    env.expect.that_str(spoke_repo_name("uv", "my-pkg")).equals("uv__pkg_my_pkg")
    env.expect.that_str(build_repo_name("uv")).equals("uv__build")
    env.expect.that_str(state_constraint_label("uv__state", "extra_cpu")).equals("@uv__state//:is_extra_cpu")
    env.expect.that_str(member_constraint_label("uv__state", "res_deadbeef", {"res_deadbeef": "sys_platform == 'linux'"})).equals("//_markers:is_res_deadbeef")
    env.expect.that_str(member_constraint_label("uv__state", "extra_cpu", {"res_deadbeef": "sys_platform == 'linux'"})).equals("@uv__state//:is_extra_cpu")
    env.expect.that_str(spoke_slot_label("uv", "my-pkg", "pkg")).equals("@uv__pkg_my_pkg//:pkg")
    env.expect.that_str(spoke_slot_label("uv", "my-pkg@s1", "wheel")).equals("@uv__pkg_my_pkg//:wheel_s1")
    env.expect.that_str(spoke_slot_label("uv", "my-pkg[opt]@s0", "raw")).equals("@uv__pkg_my_pkg//:_raw_[opt]_s0")
    env.expect.that_str(spoke_slot_label("uv", "my-pkg@s0", "hook", subdir = "_cargo")).equals("@uv__pkg_my_pkg//_cargo:pkg_s0")
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
    state_constraint_label("", "extra_cpu")
    return []

_empty_workspace_repo_subject = rule(implementation = _empty_workspace_repo_subject_impl)

def _test_lock_contract_rejects_empty_workspace_repo_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("state_target_label requires a non-empty repository name"),
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
def _test_spoke_payload_passthrough_and_isolation_impl(env, target):
    """build_spoke_payloads forwards all non-sdist PASSTHROUGH_PACKAGE_ATTRS and ignores sdist-only fields."""
    pkgs_v1 = {
        "default-pkg@1.0": {
            "name": "default-pkg",
            "version": "1.0",
            "wheel_candidates": [{"filename": "default_pkg-1.0-py3-none-any.whl", "file_reference": {"key": "k1"}}],
            "extra_build_tools": ["cython@3.0.0"],
            "build_backend": "setuptools_build",
            "build_mode": "auto",
            "build_tools_repo": "uv__build",
            "pre_build_patches": ["@@//patches:a.patch"],
            "site_hooks": ["import foo"],
            "source_dir": "sub/dir",
        },
        "full-pkg@2.0": {
            "name": "full-pkg",
            "version": "2.0",
            "marker_dependencies": [{"key": "default-pkg@1.0", "marker": "sys_platform == 'linux'"}],
            "wheel_candidates": [{"filename": "full_pkg-2.0-cp312-cp312-manylinux.whl", "file_reference": {"key": "k2"}}],
            "sdist_file": {"key": "s2"},
            "build_target": "@@//custom:full",
            "build_mode": "never",
            "install_exclude_globs": ["tests/**"],
            "post_install_patches": ["@@//patches:post.patch"],
            "site_paths": ["full_pkg"],
            "bin_paths": ["full-cli"],
            "data_paths": ["share"],
            "include_paths": ["full.h"],
            "wheel_library_tags": ["manual"],
            "precompile": "enabled",
        },
    }
    rmap = {"k1": "@ws__whl_default_pkg_py3_none_any//:wheel", "k2": "@ws__whl_full_pkg_cp312//:wheel", "s2": "@ws__sdist_file_full_pkg//file:f.tar.gz"}
    slots = assign_fork_slots(pkgs_v1)
    spokes_v1 = build_spoke_payloads("ws", "ws__state", pkgs_v1, rmap, {}, slots)

    # Editing sdist-only fields leaves spoke payloads byte-identical.
    pkgs_v2 = {k: dict(v) for k, v in pkgs_v1.items()}
    pkgs_v2["default-pkg@1.0"]["extra_build_tools"] = ["cython@3.1.0"]
    pkgs_v2["default-pkg@1.0"]["pre_build_patches"] = ["@@//patches:b.patch"]
    pkgs_v2["default-pkg@1.0"]["site_hooks"] = ["import baz"]
    pkgs_v2["default-pkg@1.0"]["build_backend"] = "meson_build"
    pkgs_v2["default-pkg@1.0"]["build_tools_repo"] = "other__build"
    pkgs_v2["default-pkg@1.0"]["source_dir"] = "other/dir"
    spokes_v2 = build_spoke_payloads("ws", "ws__state", pkgs_v2, rmap, {}, slots)
    env.expect.that_str(json.encode(spokes_v2["default-pkg"].payload)).equals(json.encode(spokes_v1["default-pkg"].payload))

    full_entry = spokes_v1["full-pkg"].payload["entries"][0]
    env.expect.that_str(full_entry["sdist_build_target"]).equals("@@//custom:full")
    env.expect.that_str(full_entry["precompile"]).equals("enabled")
    env.expect.that_collection(full_entry["post_install_patches"]).contains_exactly(["@@//patches:post.patch"])

    # Drift guard: every PASSTHROUGH_PACKAGE_ATTRS key is either sdist-only, consumed by build_spoke_payloads
    # (`build_target`/`build_mode`), or forwarded directly into the spoke entry.
    all_passthrough_pkg = {
        field: (["val"] if type(default) == "list" else "never" if field == "build_mode" else "val")
        for field, (default, _mode) in PASSTHROUGH_PACKAGE_ATTRS.items()
    }
    drift_entry = build_spoke_payloads(
        "ws",
        "ws__state",
        {"drift@1.0": all_passthrough_pkg},
        {},
        {},
        {"drift@1.0": ""},
    )["drift"].payload["entries"][0]
    for field in PASSTHROUGH_PACKAGE_ATTRS:
        if field in _SDIST_ONLY_PASSTHROUGH_ATTRS or field in ("build_mode", "build_target"):
            continue
        env.expect.where(field = field).that_bool(field in drift_entry).equals(True)

def _test_spoke_payload_passthrough_and_isolation(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_spoke_payload_passthrough_and_isolation_impl)

# buildifier: disable=unused-variable
def _test_filter_and_slim_repo_overrides_impl(env, target):
    """Spoke override filtering isolates overrides per canonical package and slim_member_lock precomputes hook_subdirs."""
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
    spoke_hooks = {
        "maturin_build": True,
        "setuptools_rust_build": True,
        "custom_subdir_build": True,
    }

    # 1. C/C++ overrides without package_repo hooks are completely stripped.
    cc_only = {
        "*": {"setuptools_build": {"copts": '["-O2"]'}},
        "numpy": {"meson_build": {"build_env": '{"FOO": "1"}'}},
        "scipy@1.14.0": {"cmake_build": {"cmake_args": '["-DFOO=ON"]'}},
    }
    env.expect.that_dict(filter_package_repo_overrides_for_testing(cc_only, hooks)).contains_exactly({})
    env.expect.that_dict(filter_spoke_overrides_for_testing(cc_only, spoke_hooks, "numpy")).contains_exactly({})

    # 2. Spoke override filtering scopes each spoke to only "*", "<name>", and "<name>@*".
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
    jiter_overrides = filter_spoke_overrides_for_testing(mixed_v1, spoke_hooks, "jiter")
    env.expect.that_dict(jiter_overrides).contains_exactly({
        "*": {"maturin_build": {"build_env": '{"RUSTFLAGS": "-C target-cpu=native"}'}},
        "jiter": {"maturin_build": {"cargo_lock": '"@@//cargo:jiter.lock"', "copts": '["-O2"]'}},
    })
    crypto_overrides = filter_spoke_overrides_for_testing(mixed_v1, spoke_hooks, "cryptography")
    env.expect.that_dict(crypto_overrides).contains_exactly({
        "*": {"maturin_build": {"build_env": '{"RUSTFLAGS": "-C target-cpu=native"}'}},
        "cryptography@43.0.0": {"setuptools_rust_build": {"cargo_lock": '"@@//cargo:crypto.lock"'}},
    })

    # 3. spoke_hook_backend_subdirs supports both explicit subdirs and legacy cargo backends.
    backend_subdirs = spoke_hook_backend_subdirs(hooks, hook_subdirs)
    env.expect.that_dict(backend_subdirs).contains_exactly({
        "maturin_build": "_cargo",
        "setuptools_rust_build": "_cargo",
        "custom_subdir_build": "_custom",
    })
    env.expect.that_dict(spoke_hook_backend_subdirs({"maturin_build": True}, {})).contains_exactly({
        "maturin_build": "_cargo",
    })

    # 4. slim_member_lock precomputes version-free hook_subdirs invariant across override flag edits,
    #    and hook_subdir_build points at @ws__pkg_<name>//<subdir>:pkg.
    member_lock = {
        "pins": {"jiter": "jiter@0.5.0", "cryptography": "cryptography@43.0.0", "other": "other@1.0.0"},
        "packages": {
            "jiter@0.5.0": {"sdist_file": {"key": "s1"}},
            "cryptography@43.0.0": {"sdist_file": {"key": "s2"}},
            "other@1.0.0": {"sdist_file": {"key": "s3"}},
        },
    }
    mixed_v2 = dict(mixed_v1)
    mixed_v2["jiter"] = {"maturin_build": {"cargo_lock": '"@@//cargo:jiter_new.lock"', "copts": '["-O3"]'}}
    slim_v1 = slim_member_lock(member_lock, member_lock["packages"], ws_overrides = mixed_v1, spoke_hook_subdirs = backend_subdirs)
    slim_v2 = slim_member_lock(member_lock, member_lock["packages"], ws_overrides = mixed_v2, spoke_hook_subdirs = backend_subdirs)
    env.expect.that_str(json.encode(slim_v2)).equals(json.encode(slim_v1))

    grouped_pins = {
        "jiter": {"base_target": {"": "jiter"}, "extras": {}},
        "cryptography": {"base_target": {"": "cryptography"}, "extras": {}},
        "other": {"base_target": {"": "other"}, "extras": {}},
    }
    cargo = hook_subdir_build(grouped_pins, slim_v1["packages"], "ws", subdir = "_cargo")
    env.expect.that_bool(cargo != None).equals(True)
    env.expect.that_str(cargo.build).contains('actual = "@ws__pkg_jiter//_cargo:pkg"')
    env.expect.that_str(cargo.build).contains('actual = "@ws__pkg_cryptography//_cargo:pkg"')

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
            _test_spoke_payload_passthrough_and_isolation,
            _test_filter_and_slim_repo_overrides,
        ],
    )
