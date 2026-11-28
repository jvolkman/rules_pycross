"""Tests for spoke_repo, member _markers, and variant-reset lock rendering."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:repo_slots.bzl", "assign_fork_slots", "sdist_slot_repo_name")

# buildifier: disable=bzl-visibility
load("//pycross/private:spoke_repo.bzl", "build_spoke_payloads", "render_spoke_build")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "marker_evaluator_name", "sanitize_name", "sdist_builds_disallowed")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private/lock_render:reset_plan.bzl",
    "compute_workspace_reset_states",
    "conflict_pairs",
    "marker_depends_on_variants",
    "render_state_reset_bzl",
)

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:markers.bzl", "render_member_markers_build")

def _render_spokes(lock, repo_map, workspace_name = "ws", has_variants = False, reset_conflict_sets = None):
    pkgs = lock.get("packages", {})
    slots = assign_fork_slots(pkgs)
    sdist_repo_map = {}
    for pkg_key, pkg in sorted(pkgs.items()):
        if pkg.get("build_target") or sdist_builds_disallowed(pkg):
            continue
        if pkg.get("sdist_file"):
            sdist_repo_map[pkg_key] = "@{}//:wheel".format(sdist_slot_repo_name(workspace_name, pkg_key, slots.get(pkg_key, "")))
    state_repo = workspace_name + "__state"
    reset_states = (
        compute_workspace_reset_states(
            pkgs,
            repo_map,
            conflict_pairs(reset_conflict_sets),
            workspace_name,
            slots,
        ) if reset_conflict_sets else None
    )
    spokes = build_spoke_payloads(
        workspace_name,
        state_repo,
        pkgs,
        repo_map,
        sdist_repo_map,
        slots,
        cycle_groups = lock.get("cycle_groups"),
        has_variants = has_variants or bool(reset_conflict_sets),
        reset_states = reset_states,
    )
    rendered = {name: render_spoke_build(s.payload) for name, s in spokes.items()}
    return struct(
        spokes = rendered,
        payloads = {name: s.payload for name, s in spokes.items()},
        all = "\n".join([rendered[k] for k in sorted(rendered.keys())]),
        slots = slots,
        reset_states = reset_states,
    )

# buildifier: disable=unused-variable
def _test_render_lock_impl(env, target):
    """Verify basic spoke rendering with wheel_candidates (wheel selection via pycross_wheel_chooser)."""
    lock = {
        "packages": {
            "foo@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "foo_wheel"},
                    },
                ],
            },
        },
    }
    res = _render_spokes(lock, {"foo_wheel": "@my_repo//foo:wheel"}).spokes["foo"]

    env.expect.that_bool("pycross_wheel_library(" in res).equals(True)
    env.expect.that_bool("pycross_wheel_chooser(" in res).equals(True)
    env.expect.that_str(res).contains('name = "wheel",')
    env.expect.that_str(res).contains('package = "foo@1.0",')

def _test_render_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_rendering_impl(env, target):
    """Verify unconditional cycle groups render direct cross-spoke pycross_library_proxy targets."""
    lock = {
        "cycle_groups": {
            "cycle_group_abc123": ["alpha@1.0", "beta@2.0"],
        },
        "packages": {
            "alpha@1.0": {
                "cycle_group": "cycle_group_abc123",
                "marker_dependencies": [{"key": "beta@2.0", "marker": None}],
                "wheel_candidates": [{"filename": "alpha-1.0-py3-none-any.whl", "file_reference": {"key": "alpha_wheel"}}],
            },
            "beta@2.0": {
                "cycle_group": "cycle_group_abc123",
                "marker_dependencies": [{"key": "alpha@1.0", "marker": None}],
                "wheel_candidates": [{"filename": "beta-2.0-py3-none-any.whl", "file_reference": {"key": "beta_wheel"}}],
            },
        },
    }
    out = _render_spokes(lock, {"alpha_wheel": "@repo//alpha:wheel", "beta_wheel": "@repo//beta:wheel"})
    alpha = out.spokes["alpha"]
    beta = out.spokes["beta"]

    env.expect.that_bool("pycross_cycle_dep_needed" in out.all).equals(False)
    env.expect.that_bool("_EDGES" in out.all).equals(False)

    env.expect.that_str(alpha).contains(
        'pycross_library_proxy(\n    name = "pkg",\n    actual = ":_raw",\n    deps = [\n        "@ws__pkg_beta//:_raw",\n    ],\n)',
    )
    env.expect.that_str(beta).contains(
        'pycross_library_proxy(\n    name = "pkg",\n    actual = ":_raw",\n    deps = [\n        "@ws__pkg_alpha//:_raw",\n    ],\n)',
    )

    # Cycled package deps exclude same-cycle members from _deps list.
    alpha_deps_section = alpha.split("_deps = [")[1].split("]")[0] if "_deps = [" in alpha else ""
    env.expect.that_bool("beta" not in alpha_deps_section).equals(True)

    # dist_info for cycle members points directly at :_raw, bypassing the cycle proxy.
    alpha_di = alpha.split('name = "dist_info"')[1].split(")", 1)[0]
    env.expect.that_str(alpha_di).contains('pkg = ":_raw"')

def _test_cycle_group_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_group_rendering_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_marker_specific_rendering_impl(env, target):
    """Verify 1-hop marker cycle reuses local _marker_eval_*_match and multi-hop emits _CYCLE_EDGES_JSON."""
    lock = {
        "cycle_groups": {
            "cycle_group_abc": ["alpha@1.0", "beta@2.0", "appnope@1.0"],
        },
        "packages": {
            "alpha@1.0": {
                "cycle_group": "cycle_group_abc",
                "marker_dependencies": [
                    {"key": "beta@2.0", "marker": None},
                    {"key": "appnope@1.0", "marker": 'sys_platform == "darwin"'},
                ],
                "wheel_candidates": [{"filename": "alpha-1.0-py3-none-any.whl", "file_reference": {"key": "alpha_wheel"}}],
            },
            "beta@2.0": {
                "cycle_group": "cycle_group_abc",
                "marker_dependencies": [{"key": "alpha@1.0", "marker": None}],
                "wheel_candidates": [{"filename": "beta-2.0-py3-none-any.whl", "file_reference": {"key": "beta_wheel"}}],
            },
            "appnope@1.0": {
                "cycle_group": "cycle_group_abc",
                "marker_dependencies": [{"key": "alpha@1.0", "marker": None}],
                "wheel_candidates": [{"filename": "appnope-1.0-py3-none-any.whl", "file_reference": {"key": "appnope_wheel"}}],
            },
        },
    }
    repo_map = {
        "alpha_wheel": "@repo//alpha:wheel",
        "beta_wheel": "@repo//beta:wheel",
        "appnope_wheel": "@repo//appnope:wheel",
    }
    out = _render_spokes(lock, repo_map)
    darwin_match = marker_evaluator_name('sys_platform == "darwin"') + "_match"
    env.expect.that_bool("_cycle_needed_" in out.all).equals(False)
    env.expect.that_bool("_EDGES_JSON" in out.all).equals(False)
    env.expect.that_bool("cycle_dep_needed.bzl" in out.all).equals(False)
    env.expect.that_str(out.spokes["alpha"]).contains('":{}": ["@ws__pkg_appnope//:_raw"]'.format(darwin_match))
    env.expect.that_str(out.spokes["beta"]).contains('":{}": ["@ws__pkg_appnope//:_raw"]'.format(darwin_match))

    # Multi-hop conditional cycle (a -> b [darwin] -> c [py<3.13] -> a) emits _CYCLE_EDGES_JSON.
    mh_lock = {
        "cycle_groups": {"cycle_group_mh": ["a@1.0", "b@1.0", "c@1.0"]},
        "packages": {
            "a@1.0": {
                "cycle_group": "cycle_group_mh",
                "marker_dependencies": [{"key": "b@1.0", "marker": 'sys_platform == "darwin"'}],
                "wheel_candidates": [{"filename": "a-1.0-py3-none-any.whl", "file_reference": {"key": "alpha_wheel"}}],
            },
            "b@1.0": {
                "cycle_group": "cycle_group_mh",
                "marker_dependencies": [{"key": "c@1.0", "marker": "python_version < '3.13'"}],
                "wheel_candidates": [{"filename": "b-1.0-py3-none-any.whl", "file_reference": {"key": "beta_wheel"}}],
            },
            "c@1.0": {
                "cycle_group": "cycle_group_mh",
                "marker_dependencies": [{"key": "a@1.0", "marker": None}],
                "wheel_candidates": [{"filename": "c-1.0-py3-none-any.whl", "file_reference": {"key": "appnope_wheel"}}],
            },
        },
    }
    mh_a = _render_spokes(mh_lock, repo_map).spokes["a"]
    env.expect.that_str(mh_a).contains('load("@rules_pycross//pycross/private:cycle_dep_needed.bzl", "pycross_cycle_dep_needed")')
    env.expect.that_int(mh_a.count("_CYCLE_EDGES_JSON = ")).equals(1)
    env.expect.that_str(mh_a).contains('name = "_cycle_needed_a_c",')
    env.expect.that_str(mh_a).contains("edges = _CYCLE_EDGES_JSON,")
    env.expect.that_str(mh_a).contains('":_cycle_needed_a_c_match": ["@ws__pkg_c//:_raw"]')

def _test_cycle_group_marker_specific_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_group_marker_specific_rendering_impl)

# buildifier: disable=unused-variable
def _test_extras_rendering_impl(env, target):
    """Verify extras generate version-free pycross_library_proxy targets named [extra_name] inside the spoke."""
    lock = {
        "packages": {
            "mylib@1.0": {
                "marker_dependencies": [],
                "wheel_candidates": [{"filename": "mylib-1.0-py3-none-any.whl", "file_reference": {"key": "mylib_wheel"}}],
            },
            "mylib[test]@1.0": {
                "marker_dependencies": [{"key": "pytest@7.0", "marker": None}],
            },
            "mylib[dev]@1.0": {
                "marker_dependencies": [
                    {"key": "black@23.0", "marker": None},
                    {"key": "mypy@1.5", "marker": 'sys_platform == "linux"'},
                ],
            },
            "pytest@7.0": {"wheel_candidates": [{"filename": "pytest-7.0-py3-none-any.whl", "file_reference": {"key": "pytest_wheel"}}]},
            "black@23.0": {"wheel_candidates": [{"filename": "black-23.0-py3-none-any.whl", "file_reference": {"key": "black_wheel"}}]},
            "mypy@1.5": {"wheel_candidates": [{"filename": "mypy-1.5-py3-none-any.whl", "file_reference": {"key": "mypy_wheel"}}]},
        },
    }
    repo_map = {
        "mylib_wheel": "@repo//mylib:wheel",
        "pytest_wheel": "@repo//pytest:wheel",
        "black_wheel": "@repo//black:wheel",
        "mypy_wheel": "@repo//mypy:wheel",
    }
    mylib = _render_spokes(lock, repo_map).spokes["mylib"]

    env.expect.that_str(mylib).contains('name = "[test]"')
    env.expect.that_str(mylib).contains('"@ws__pkg_pytest//:pkg"')
    env.expect.that_str(mylib).contains('name = "[dev]"')
    env.expect.that_str(mylib).contains('"@ws__pkg_black//:pkg"')
    env.expect.that_str(mylib).contains('"@ws__pkg_mypy//:pkg"')
    env.expect.that_bool("select({" in mylib).equals(True)
    env.expect.that_bool("pycross_library_proxy" in mylib).equals(True)
    env.expect.that_bool("[_all_]" in mylib).equals(False)

def _test_extras_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_rendering_impl)

# buildifier: disable=unused-variable
def _test_spoke_build_format_impl(env, target):
    """Verify spoke rendering emits direct root BUILD.bazel files with minimal loads (no def targets())."""
    lock = {
        "packages": {
            "numpy@1.26.4": {
                "wheel_candidates": [{"filename": "numpy-1.26.4-py3-none-any.whl", "file_reference": {"key": "numpy_wheel"}}],
            },
            "pandas@2.1.0": {
                "wheel_candidates": [{"filename": "pandas-2.1.0-py3-none-any.whl", "file_reference": {"key": "pandas_wheel"}}],
            },
        },
    }
    out = _render_spokes(lock, {"numpy_wheel": "@repo//numpy:wheel", "pandas_wheel": "@repo//pandas:wheel"})
    np_build = out.spokes["numpy"]
    pd_build = out.spokes["pandas"]

    env.expect.that_bool("def targets():" in np_build).equals(False)
    env.expect.that_str(np_build).contains('package_name = "numpy"')
    env.expect.that_str(np_build).contains('package_version = "1.26.4"')
    env.expect.that_str(pd_build).contains('package_name = "pandas"')
    env.expect.that_str(pd_build).contains('package_version = "2.1.0"')
    env.expect.that_str(np_build).contains("pycross_dist_info(")

    # Pure universal wheel with no markers skips unused pep508_evaluator and wheel_chooser loads.
    env.expect.that_bool("pycross_pep508_evaluator" in np_build).equals(False)
    env.expect.that_bool("pycross_wheel_chooser" in np_build).equals(False)

def _test_spoke_build_format(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_spoke_build_format_impl)

# buildifier: disable=unused-variable
def _test_no_cycles_no_cycle_targets_impl(env, target):
    """When there are no cycles, no _cycle_ targets are emitted and :_raw aliases :pkg."""
    lock = {
        "packages": {
            "a@1.0": {
                "marker_dependencies": [{"key": "b@2.0", "marker": None}],
                "wheel_candidates": [{"filename": "a-1.0-py3-none-any.whl", "file_reference": {"key": "a_wheel"}}],
            },
            "b@2.0": {
                "wheel_candidates": [{"filename": "b-2.0-py3-none-any.whl", "file_reference": {"key": "b_wheel"}}],
            },
        },
    }
    a_build = _render_spokes(lock, {"a_wheel": "@repo//a:wheel", "b_wheel": "@repo//b:wheel"}).spokes["a"]
    env.expect.that_bool("_cycle_" not in a_build).equals(True)
    env.expect.that_str(a_build).contains('name = "pkg"')
    env.expect.that_str(a_build).contains('name = "_raw",\n    actual = ":pkg",')

def _test_no_cycles_no_cycle_targets(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_cycles_no_cycle_targets_impl)

# buildifier: disable=unused-variable
def _test_marker_deps_rendering_impl(env, target):
    """Verify marker_dependencies renders evaluator + config_setting + select and universal fast path."""
    lock = {
        "packages": {
            "foo@1.0": {
                "marker_dependencies": [
                    {"key": "bar@2.0", "marker": None},
                    {"key": "baz@3.0", "marker": 'sys_platform == "linux"'},
                ],
                "wheel_candidates": [{"filename": "foo-1.0-py3-none-any.whl", "file_reference": {"key": "foo_wheel"}}],
            },
            "bar@2.0": {"wheel_candidates": [{"filename": "bar-2.0-py3-none-any.whl", "file_reference": {"key": "bar_wheel"}}]},
            "baz@3.0": {"wheel_candidates": [{"filename": "baz-3.0-py3-none-any.whl", "file_reference": {"key": "baz_wheel"}}]},
        },
    }
    foo = _render_spokes(lock, {"foo_wheel": "@repo//foo:wheel", "bar_wheel": "@repo//bar:wheel", "baz_wheel": "@repo//baz:wheel"}).spokes["foo"]

    env.expect.that_str(foo).contains("pycross_pep508_evaluator")
    env.expect.that_str(foo).contains("_marker_eval_")
    env.expect.that_str(foo).contains("sys_platform")
    env.expect.that_str(foo).contains("_match")
    env.expect.that_str(foo).contains('"@ws__pkg_bar//:pkg"')
    env.expect.that_str(foo).contains('"@ws__pkg_baz//:pkg"')
    env.expect.that_bool("select({" in foo).equals(True)

    # Single universal py3-none-any wheel bypasses pycross_wheel_chooser with a direct alias.
    env.expect.that_bool("_wheel_chooser" in foo).equals(False)
    env.expect.that_str(foo).contains('name = "_wheel_sel",\n    actual = "@repo//foo:wheel",')

def _test_marker_deps_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_deps_rendering_impl)

# buildifier: disable=unused-variable
def _test_multi_platform_repo_map_impl(env, target):
    """Verify multi-platform repo_map entries render cleanly in spoke wheel chooser."""
    lock = {
        "packages": {
            "crypto@1.0": {
                "wheel_candidates": [
                    {"filename": "crypto-1.0-cp311-cp311-manylinux_2_17_x86_64.whl", "file_reference": {"key": "crypto_linux_x86"}},
                    {"filename": "crypto-1.0-cp311-cp311-win_amd64.whl", "file_reference": {"key": "crypto_win"}},
                    {"filename": "crypto-1.0-cp311-cp311-win32.whl", "file_reference": {"key": "crypto_win32"}},
                    {"filename": "crypto-1.0-cp311-cp311-macosx_11_0_arm64.whl", "file_reference": {"key": "crypto_macos"}},
                ],
            },
        },
    }
    repo_map = {
        "crypto_linux_x86": "@pypi_crypto_linux//:wheel",
        "crypto_win": "@pypi_crypto_win//:wheel",
        "crypto_win32": "@pypi_crypto_win32//:wheel",
        "crypto_macos": "@pypi_crypto_macos//:wheel",
    }
    res = _render_spokes(lock, repo_map).spokes["crypto"]
    env.expect.that_str(res).contains("@pypi_crypto_linux//:wheel")
    env.expect.that_str(res).contains("@pypi_crypto_win//:wheel")
    env.expect.that_str(res).contains("@pypi_crypto_win32//:wheel")
    env.expect.that_str(res).contains("@pypi_crypto_macos//:wheel")
    env.expect.that_str(res).contains('name = "_wheel_chooser"')

def _test_multi_platform_repo_map(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_multi_platform_repo_map_impl)

# buildifier: disable=unused-variable
def _test_available_config_setting_group_impl(env, target):
    """Verify _wheel_available config_setting_group is emitted for wheel-only packages without sdist."""
    lock = {
        "packages": {
            "platform_pkg@1.0": {
                "wheel_candidates": [
                    {"filename": "platform_pkg-1.0-cp310-cp310-manylinux_2_17_x86_64.whl", "file_reference": {"key": "plat_linux"}},
                    {"filename": "platform_pkg-1.0-cp310-cp310-win_amd64.whl", "file_reference": {"key": "plat_win"}},
                ],
            },
            "sdist_pkg@2.0": {
                "sdist_file": {"key": "sdist_key"},
                "wheel_candidates": [
                    {"filename": "sdist_pkg-2.0-cp310-cp310-manylinux_2_17_x86_64.whl", "file_reference": {"key": "sdist_linux"}},
                ],
            },
        },
    }
    repo_map = {
        "plat_linux": "@repo//plat:linux_wheel",
        "plat_win": "@repo//plat:win_wheel",
        "sdist_linux": "@repo//sdist:linux_wheel",
        "sdist_key": "@repo//sdist:sdist",
    }
    out = _render_spokes(lock, repo_map)
    plat_build = out.spokes["platform-pkg"]
    sdist_build = out.spokes["sdist-pkg"]

    env.expect.that_str(plat_build).contains('name = "_wheel_available"')
    env.expect.that_bool('"_available_' in plat_build).equals(False)
    env.expect.that_bool("config_setting_group(" in plat_build).equals(True)
    env.expect.that_bool("selects" in plat_build).equals(True)

    env.expect.that_bool("_wheel_available" in sdist_build).equals(False)
    env.expect.that_bool("selects" in sdist_build).equals(False)

def _test_available_config_setting_group(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_available_config_setting_group_impl)

# buildifier: disable=unused-variable
def _test_extras_inherit_base_available_impl(env, target):
    """Extras of a wheel-only package rely on the base's _wheel_available group."""
    lock = {
        "packages": {
            "plat@1.0": {
                "wheel_candidates": [{"filename": "plat-1.0-cp310-cp310-win_amd64.whl", "file_reference": {"key": "plat_win"}}],
            },
            "plat[extra]@1.0": {},
        },
    }
    res = _render_spokes(lock, {"plat_win": "@repo//plat:win_wheel"}).spokes["plat"]
    env.expect.that_str(res).contains('name = "_wheel_available"')
    env.expect.that_bool('"_available_' in res).equals(False)

def _test_extras_inherit_base_available(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_inherit_base_available_impl)

# buildifier: disable=unused-variable
def _test_build_mode_never_no_sdist_fallback_impl(env, target):
    """build_mode = "never" packages don't fall back to the sdist build and get _wheel_available."""
    lock = {
        "packages": {
            "pkg@1.0": {
                "sdist_file": {"key": "sdist_key"},
                "build_mode": "never",
                "wheel_candidates": [{"filename": "pkg-1.0-cp310-cp310-win_amd64.whl", "file_reference": {"key": "pkg_win"}}],
            },
        },
    }
    res = _render_spokes(lock, {"pkg_win": "@repo//pkg:win_wheel", "sdist_key": "@repo//pkg:sdist"}).spokes["pkg"]
    env.expect.that_bool("ws__sdist_" in res).equals(False)
    env.expect.that_str(res).contains("@rules_pycross//pycross/private:no_match_error")
    env.expect.that_str(res).contains('name = "_wheel_available"')

def _test_build_mode_never_no_sdist_fallback(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_mode_never_no_sdist_fallback_impl)

# buildifier: disable=unused-variable
def _test_resolution_marker_member_rendering_impl(env, target):
    """Verify member-local _markers/BUILD.bazel renders resolution_marker_exprs and compound groups."""
    markers = render_member_markers_build(
        {},
        {
            "res_aaaa1111": "sys_platform == 'linux'",
            "res_bbbb2222": "sys_platform == 'darwin'",
            "extra_science_res_aaaa1111": {
                "variant": "extra_science",
                "marker": "res_aaaa1111",
            },
        },
        "ws__state",
        has_variants = True,
    )
    env.expect.that_str(markers).contains("pycross_pep508_evaluator(")
    env.expect.that_str(markers).contains('name = "_res_eval_res_aaaa1111"')
    env.expect.that_str(markers).contains('name = "_res_eval_res_bbbb2222"')
    env.expect.that_str(markers).contains('name = "is_res_aaaa1111"')
    env.expect.that_str(markers).contains('name = "is_res_bbbb2222"')
    env.expect.that_str(markers).contains("selects.config_setting_group(")
    env.expect.that_str(markers).contains('name = "is_extra_science_res_aaaa1111"')
    env.expect.that_str(markers).contains("match_all")
    env.expect.that_str(markers).contains('"@ws__state//:is_extra_science"')
    env.expect.that_str(markers).contains('":is_res_aaaa1111"')
    env.expect.that_str(markers).contains('load("@bazel_skylib//lib:selects.bzl"')

def _test_resolution_marker_member_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_resolution_marker_member_rendering_impl)

# buildifier: disable=unused-variable
def _test_wheel_library_tags_and_precompile_rendering_impl(env, target):
    """Verify wheel_library_tags and precompile render on pycross_wheel_library only when non-empty."""
    lock = {
        "packages": {
            "compiled@1.0": {
                "wheel_candidates": [{"filename": "compiled-1.0-py3-none-any.whl", "file_reference": {"key": "compiled_wheel"}}],
                "wheel_library_tags": ["no-remote", "custom-tag"],
                "precompile": "enabled",
            },
            "default_pkg@1.0": {
                "wheel_candidates": [{"filename": "default_pkg-1.0-py3-none-any.whl", "file_reference": {"key": "default_wheel"}}],
                "precompile": "",
            },
        },
    }
    out = _render_spokes(lock, {"compiled_wheel": "@my_repo//compiled:wheel", "default_wheel": "@my_repo//default_pkg:wheel"})
    compiled = out.spokes["compiled"]
    default_pkg = out.spokes["default-pkg"]
    env.expect.that_str(compiled).contains("tags = [")
    env.expect.that_str(compiled).contains('"no-remote",')
    env.expect.that_str(compiled).contains('"custom-tag",')
    env.expect.that_str(compiled).contains('precompile = "enabled",')
    env.expect.that_bool("precompile =" in default_pkg).equals(False)

def _test_wheel_library_tags_and_precompile_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_library_tags_and_precompile_rendering_impl)

# buildifier: disable=unused-variable
def _test_epoch_sdist_repo_name_impl(env, target):
    """Version-free sdist slot repo names avoid epoch punctuation issues."""
    lock = {
        "packages": {
            "foo@1!2.0": {
                "sdist_file": {"key": "foo_sdist"},
                "wheel_candidates": [],
            },
        },
    }
    res = _render_spokes(lock, {"foo_sdist": "@repo//file:foo-1!2.0.tar.gz"}, workspace_name = "uv").spokes["foo"]
    env.expect.that_str(res).contains("@uv__sdist_foo//:wheel")

def _test_epoch_sdist_repo_name(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_epoch_sdist_repo_name_impl)

# buildifier: disable=unused-variable
def _test_conflict_state_rendering_impl(env, target):
    """Verify variants is emitted only on __variant_-referencing evaluators across spokes and member _markers."""
    t_cuda = "__variant_group_cuda"
    conflict_marker = "sys_platform == 'linux' and extra == '{}'".format(t_cuda)
    plain_extra_marker = "extra == 'cudart'"
    plain_marker = "sys_platform == 'darwin'"
    lock = {
        "cycle_groups": {"cycle_group_c1": ["cyca@1.0", "cycb@1.0", "cycc@1.0"]},
        "packages": {
            "cuda-toolkit@13.0.2": {
                "availability_markers": [conflict_marker],
                "wheel_candidates": [{"filename": "cuda_toolkit-13.0.2-py3-none-any.whl", "file_reference": {"key": "ct_whl"}}],
            },
            "cuda-toolkit[cudart]@13.0.2": {
                "marker_dependencies": [
                    {"key": "dep_a@1.0", "marker": conflict_marker},
                    {"key": "dep_b@1.0", "marker": plain_marker},
                    {"key": "dep_b@1.0", "marker": plain_extra_marker},
                ],
            },
            "dep_a@1.0": {"wheel_candidates": [{"filename": "dep_a-1.0-py3-none-any.whl", "file_reference": {"key": "da_whl"}}]},
            "dep_b@1.0": {"wheel_candidates": [{"filename": "dep_b-1.0-py3-none-any.whl", "file_reference": {"key": "db_whl"}}]},
            "cyca@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [{"key": "cycb@1.0", "marker": conflict_marker}],
                "wheel_candidates": [{"filename": "cyca-1.0-py3-none-any.whl", "file_reference": {"key": "ca_whl"}}],
            },
            "cycb@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [{"key": "cycc@1.0", "marker": plain_marker}],
                "wheel_candidates": [{"filename": "cycb-1.0-py3-none-any.whl", "file_reference": {"key": "cb_whl"}}],
            },
            "cycc@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [{"key": "cyca@1.0", "marker": None}],
                "wheel_candidates": [{"filename": "cycc-1.0-py3-none-any.whl", "file_reference": {"key": "cc_whl"}}],
            },
        },
        "resolution_marker_exprs": {
            "res_fork_conflict": conflict_marker,
            "res_fork_plain": plain_marker,
        },
    }
    repo_map = {
        "ct_whl": "@repo//ct:wheel",
        "da_whl": "@repo//da:wheel",
        "db_whl": "@repo//db:wheel",
        "ca_whl": "@repo//ca:wheel",
        "cb_whl": "@repo//cb:wheel",
        "cc_whl": "@repo//cc:wheel",
    }
    spokes_with = _render_spokes(lock, repo_map, has_variants = True)
    spokes_without = _render_spokes(lock, repo_map, has_variants = False)
    markers_with = render_member_markers_build(lock["packages"], lock["resolution_marker_exprs"], "ws__state", has_variants = True)
    markers_without = render_member_markers_build(lock["packages"], lock["resolution_marker_exprs"], "ws__state", has_variants = False)

    env.expect.that_int((spokes_without.all + markers_without).count('variants = ["@ws__state//:_variant_state"]')).equals(0)

    # Spoke evaluators with variants:
    # - cuda-toolkit[cudart] conflict_marker evaluator (1)
    # - cyca conflict_marker evaluator (1) + multi-hop pycross_cycle_dep_needed (1)
    # - cycb & cycc multi-hop pycross_cycle_dep_needed evaluators also get variants when emitted.
    env.expect.that_int(spokes_with.spokes["cuda-toolkit"].count('variants = ["@ws__state//:_variant_state"]')).equals(1)
    env.expect.that_str(spokes_with.spokes["cyca"]).contains('variants = ["@ws__state//:_variant_state"]')

    # Member _markers evaluators with variants: availability_markers conflict_marker (1) + res_fork_conflict (1),
    # and NOT res_fork_plain.
    env.expect.that_int(markers_with.count('variants = ["@ws__state//:_variant_state"]')).equals(2)

def _test_conflict_state_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_conflict_state_rendering_impl)

# --- Variant reset ---

def _whl(name, filename):
    return {"filename": filename, "file_reference": {"key": name}}

_RESET_SETS = [["extra_app_cpu", "extra_app_gpu"]]

def _reset_lock(packages, cycle_groups = None):
    repo_map = {}
    for pkg in packages.values():
        for c in pkg.get("wheel_candidates", []):
            repo_map[c["file_reference"]["key"]] = "@r//{}:wheel".format(c["file_reference"]["key"])
        if pkg.get("sdist_file"):
            repo_map[pkg["sdist_file"]["key"]] = "@r//{}:sdist".format(pkg["sdist_file"]["key"])
    lock = {"packages": packages}
    if cycle_groups:
        lock["cycle_groups"] = cycle_groups
    return _render_spokes(lock, repo_map, reset_conflict_sets = _RESET_SETS)

def _library(spoke_build, target_name):
    """The rule kind and gate of a spoke's library target."""
    for kind in ("pycross_resettable_wheel_library(", "pycross_wheel_library("):
        marker = '{}\n    name = "{}",'.format(kind, target_name)
        if marker in spoke_build:
            body = spoke_build.split(marker)[1].split("\n)")[0]
            gate = body.split("reset_gate = ")[1].split(",")[0] if "reset_gate = " in body else None
            return (kind[:-1], gate)
    return (None, None)

# buildifier: disable=unused-variable
def _test_reset_plan_impl(env, target):
    """Packages that don't depend on variants install with them reset; others don't."""
    out = _reset_lock({
        "leaf@1.0": {"wheel_candidates": [_whl("leaf_whl", "leaf-1.0-py3-none-any.whl")]},
        "uses-leaf@1.0": {
            "wheel_candidates": [_whl("uses_whl", "uses_leaf-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "leaf@1.0", "marker": "sys_platform == 'win32' or (extra == '__variant_extra_app_cpu' and extra == '__variant_extra_app_gpu')"}],
        },
        "gated@1.0": {
            "wheel_candidates": [_whl("gated_whl", "gated-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "leaf@1.0", "marker": "extra == '__variant_extra_app_cpu'"}],
        },
        "above-gated@1.0": {
            "wheel_candidates": [_whl("above_whl", "above_gated-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "gated@1.0"}],
        },
        "patched@1.0": {
            "wheel_candidates": [_whl("patched_whl", "patched-1.0-py3-none-any.whl")],
            "post_install_patches": ["//:p.patch"],
        },
        "no-wheel@1.0": {"sdist_file": {"key": "no_wheel_sdist"}},
        "above-no-wheel@1.0": {
            "wheel_candidates": [_whl("above_nw_whl", "above_no_wheel-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "no-wheel@1.0"}],
        },
        "cyc@1.0": {
            "wheel_candidates": [_whl("cyc_whl", "cyc-1.0-py3-none-any.whl")],
            "cycle_group": "cycle_group_x",
        },
        "above-cyc@1.0": {
            "wheel_candidates": [_whl("above_cyc_whl", "above_cyc-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "cyc@1.0"}],
        },
    })
    sp = out.spokes
    env.expect.that_str(sp["leaf"]).contains('load("@ws__state//:reset.bzl", "pycross_resettable_wheel_library")')
    env.expect.that_collection(_library(sp["leaf"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["uses-leaf"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_str(_library(sp["gated"], "pkg")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(sp["above-gated"], "pkg")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(sp["patched"], "pkg")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(sp["above-no-wheel"], "pkg")[0]).equals("pycross_wheel_library")
    env.expect.that_collection(_library(sp["cyc"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-cyc"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()

def _test_reset_plan(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_plan_impl)

# buildifier: disable=unused-variable
def _test_marker_depends_on_variants_cache_impl(env, target):
    """marker_depends_on_variants memoizes results and parsed ASTs."""
    pairs = conflict_pairs(_RESET_SETS)
    cache = {}
    parse_cache = {}
    markers = [
        ("extra == '__variant_extra_app_cpu'", True),
        ("sys_platform == 'win32' or (extra == '__variant_extra_app_cpu' and extra == '__variant_extra_app_gpu')", False),
        ("sys_platform == 'linux'", False),
    ]
    for marker, expected in markers:
        env.expect.that_bool(marker_depends_on_variants(marker, pairs, cache = cache, parse_cache = parse_cache)).equals(expected)
        env.expect.that_bool(marker_depends_on_variants(marker, pairs, cache = cache, parse_cache = parse_cache)).equals(expected)
    env.expect.that_dict(cache).contains_exactly({m: exp for m, exp in markers})
    env.expect.that_collection(parse_cache.keys()).contains_exactly([markers[0][0], markers[1][0]])

    sentinel_t = "invalid syntax __variant_t ==="
    sentinel_f = "invalid syntax __variant_f ==="
    cache[sentinel_t] = True
    cache[sentinel_f] = False
    env.expect.that_bool(marker_depends_on_variants(sentinel_t, pairs, cache = cache, parse_cache = parse_cache)).equals(True)
    env.expect.that_bool(marker_depends_on_variants(sentinel_f, pairs, cache = cache, parse_cache = parse_cache)).equals(False)

def _test_marker_depends_on_variants_cache(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_depends_on_variants_cache_impl)

# buildifier: disable=unused-variable
def _test_reset_cycles_impl(env, target):
    """Cycle members reset their :_raw installs independently; callers reset across pure/gated SCCs."""
    out = _reset_lock(
        {
            "pure-a@1.0": {
                "wheel_candidates": [_whl("pa", "pure_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_pure",
                "marker_dependencies": [{"key": "pure-b@1.0"}],
            },
            "pure-b@1.0": {
                "wheel_candidates": [_whl("pb", "pure_b-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_pure",
                "marker_dependencies": [{"key": "pure-a@1.0", "marker": "sys_platform == 'win32'"}],
            },
            "above-pure@1.0": {
                "wheel_candidates": [_whl("ap", "above_pure-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "pure-a@1.0"}],
            },
            "var-a@1.0": {
                "wheel_candidates": [_whl("va", "var_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_var",
                "marker_dependencies": [{"key": "var-b@1.0", "marker": "extra == '__variant_extra_app_cpu'"}],
            },
            "var-b@1.0": {
                "wheel_candidates": [_whl("vb", "var_b-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_var",
                "marker_dependencies": [{"key": "var-a@1.0"}],
            },
            "above-var@1.0": {
                "wheel_candidates": [_whl("av", "above_var-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "var-a@1.0"}],
            },
            "mix-a@1.0": {
                "wheel_candidates": [_whl("ma", "mix_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_mix",
                "marker_dependencies": [{"key": "mix-b@1.0"}],
            },
            "mix-b@1.0": {
                "sdist_file": {"key": "mb_sdist"},
                "cycle_group": "cycle_mix",
                "marker_dependencies": [{"key": "mix-a@1.0"}],
            },
            "above-mix@1.0": {
                "wheel_candidates": [_whl("am", "above_mix-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "mix-a@1.0"}],
            },
            "gate-a@1.0": {
                "wheel_candidates": [_whl("ga", "gate_a-1.0-cp312-cp312-manylinux_2_17_x86_64.whl")],
                "sdist_file": {"key": "ga_sdist"},
                "cycle_group": "cycle_gate",
                "marker_dependencies": [{"key": "gate-b@1.0"}],
            },
            "gate-b@1.0": {
                "wheel_candidates": [_whl("gb", "gate_b-1.0-cp312-cp312-manylinux_2_17_x86_64.whl")],
                "sdist_file": {"key": "gb_sdist"},
                "cycle_group": "cycle_gate",
                "marker_dependencies": [{"key": "gate-a@1.0"}],
            },
            "above-gate@1.0": {
                "wheel_candidates": [_whl("ag", "above_gate-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "gate-a@1.0"}],
            },
            "c1-a@1.0": {
                "wheel_candidates": [_whl("c1a", "c1_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_c1",
                "marker_dependencies": [{"key": "c1-b@1.0"}, {"key": "c2-a@1.0"}],
            },
            "c1-b@1.0": {
                "wheel_candidates": [_whl("c1b", "c1_b-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_c1",
                "marker_dependencies": [{"key": "c1-a@1.0"}],
            },
            "c2-a@1.0": {
                "wheel_candidates": [_whl("c2a", "c2_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_c2",
                "marker_dependencies": [{"key": "c2-b@1.0"}],
            },
            "c2-b@1.0": {
                "wheel_candidates": [_whl("c2b", "c2_b-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_c2",
                "marker_dependencies": [{"key": "c2-a@1.0"}],
            },
            "above-chain@1.0": {
                "wheel_candidates": [_whl("ach", "above_chain-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "c1-a@1.0"}],
            },
            "bad-sdist@1.0": {
                "sdist_file": {"key": "bad_sdist"},
                "cycle_group": "cycle_bad2",
                "marker_dependencies": [{"key": "bad-w@1.0"}],
            },
            "bad-w@1.0": {
                "wheel_candidates": [_whl("bw", "bad_w-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_bad2",
                "marker_dependencies": [{"key": "bad-sdist@1.0"}],
            },
            "bad1-a@1.0": {
                "wheel_candidates": [_whl("b1a", "bad1_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_bad1",
                "marker_dependencies": [{"key": "bad1-b@1.0"}, {"key": "bad-w@1.0"}],
            },
            "bad1-b@1.0": {
                "wheel_candidates": [_whl("b1b", "bad1_b-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_bad1",
                "marker_dependencies": [{"key": "bad1-a@1.0"}],
            },
            "above-bad-chain@1.0": {
                "wheel_candidates": [_whl("abc", "above_bad_chain-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "bad1-a@1.0"}],
            },
            "sdist-leaf@1.0": {"sdist_file": {"key": "sl_sdist"}},
            "cond-a@1.0": {
                "wheel_candidates": [_whl("ca", "cond_a-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_cond",
                "marker_dependencies": [
                    {"key": "cond-b@1.0"},
                    {"key": "sdist-leaf@1.0", "marker": "sys_platform == 'win32'"},
                ],
            },
            "cond-b@1.0": {
                "wheel_candidates": [_whl("cb", "cond_b-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_cond",
                "marker_dependencies": [{"key": "cond-a@1.0"}],
            },
            "above-cond@1.0": {
                "wheel_candidates": [_whl("ac", "above_cond-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "cond-a@1.0"}],
            },
            "ex-same@1.0": {
                "wheel_candidates": [_whl("es", "ex_same-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_ex_same",
                "marker_dependencies": [{"key": "ex-same[x]@1.0"}],
            },
            "ex-same[x]@1.0": {
                "cycle_group": "cycle_ex_same",
                "marker_dependencies": [{"key": "ex-same@1.0"}],
            },
            "above-ex-same@1.0": {
                "wheel_candidates": [_whl("aes", "above_ex_same-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "ex-same[x]@1.0"}],
            },
            "plain-base@1.0": {"wheel_candidates": [_whl("plb", "plain_base-1.0-py3-none-any.whl")]},
            "plain-base[x]@1.0": {
                "cycle_group": "cycle_ex_ext",
                "marker_dependencies": [{"key": "ex-ext-peer@1.0"}],
            },
            "ex-ext-peer@1.0": {
                "wheel_candidates": [_whl("eep", "ex_ext_peer-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_ex_ext",
                "marker_dependencies": [{"key": "plain-base[x]@1.0"}],
            },
            "above-ex-ext@1.0": {
                "wheel_candidates": [_whl("aee", "above_ex_ext-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "plain-base[x]@1.0"}],
            },
            "pure-a[x]@1.0": {
                "cycle_group": "cycle_ex_cycbase",
                "marker_dependencies": [{"key": "ex-cyc-peer@1.0"}],
            },
            "ex-cyc-peer@1.0": {
                "wheel_candidates": [_whl("ecp", "ex_cyc_peer-1.0-py3-none-any.whl")],
                "cycle_group": "cycle_ex_cycbase",
                "marker_dependencies": [{"key": "pure-a[x]@1.0"}],
            },
            "above-ex-cycbase@1.0": {
                "wheel_candidates": [_whl("aecb", "above_ex_cycbase-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "pure-a[x]@1.0"}],
            },
            "pure-b[y]@1.0": {},
            "above-noncyc-extra@1.0": {
                "wheel_candidates": [_whl("ance", "above_noncyc_extra-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "pure-b[y]@1.0"}],
            },
        },
        cycle_groups = {
            "cycle_pure": ["pure-a@1.0", "pure-b@1.0"],
            "cycle_var": ["var-a@1.0", "var-b@1.0"],
            "cycle_mix": ["mix-a@1.0", "mix-b@1.0"],
            "cycle_gate": ["gate-a@1.0", "gate-b@1.0"],
            "cycle_c1": ["c1-a@1.0", "c1-b@1.0"],
            "cycle_c2": ["c2-a@1.0", "c2-b@1.0"],
            "cycle_bad1": ["bad1-a@1.0", "bad1-b@1.0"],
            "cycle_bad2": ["bad-sdist@1.0", "bad-w@1.0"],
            "cycle_cond": ["cond-a@1.0", "cond-b@1.0"],
            "cycle_ex_same": ["ex-same@1.0", "ex-same[x]@1.0"],
            "cycle_ex_ext": ["plain-base[x]@1.0", "ex-ext-peer@1.0"],
            "cycle_ex_cycbase": ["pure-a[x]@1.0", "ex-cyc-peer@1.0"],
        },
    )
    sp = out.spokes

    env.expect.that_collection(_library(sp["pure-a"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["pure-b"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-pure"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_str(sp["pure-a"]).contains('pycross_library_proxy(\n    name = "pkg",\n    actual = ":_raw",')

    env.expect.that_collection(_library(sp["var-a"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["var-b"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_str(_library(sp["above-var"], "pkg")[0]).equals("pycross_wheel_library")

    env.expect.that_collection(_library(sp["mix-a"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_str(_library(sp["mix-b"], "_raw")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(sp["above-mix"], "pkg")[0]).equals("pycross_wheel_library")

    env.expect.that_collection(_library(sp["gate-a"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", '":_raw_reset_gate"']).in_order()
    env.expect.that_collection(_library(sp["gate-b"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", '":_raw_reset_gate"']).in_order()
    scc_gate = sp["gate-a"].split('name = "_scc_reset_gate",')[1].split(")")[0]
    env.expect.that_str(scc_gate).contains('":_raw_reset_gate"')
    env.expect.that_str(scc_gate).contains('"@ws__pkg_gate_b//:_raw_reset_gate"')
    env.expect.that_str(sp["above-gate"]).contains('actual = "@ws__pkg_gate_a//:_reset_gate"')
    env.expect.that_collection(_library(sp["above-gate"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", '":_reset_gate"']).in_order()

    env.expect.that_collection(_library(sp["c1-a"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["c2-b"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-chain"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()

    env.expect.that_str(_library(sp["bad1-a"], "_raw")[0]).equals("pycross_wheel_library")
    env.expect.that_collection(_library(sp["bad1-b"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["bad-w"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_str(_library(sp["above-bad-chain"], "pkg")[0]).equals("pycross_wheel_library")

    env.expect.that_collection(_library(sp["cond-a"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", '":_raw_reset_gate"']).in_order()
    env.expect.that_str(sp["cond-a"]).contains("_nomatch")
    env.expect.that_collection(_library(sp["above-cond"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", '":_reset_gate"']).in_order()

    env.expect.that_collection(_library(sp["ex-same"], "_raw")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-ex-same"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-ex-ext"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-ex-cycbase"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(sp["above-noncyc-extra"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()

    sdist_extra_out = _reset_lock(
        {
            "ext@1.0": {
                "sdist_file": {"key": "ext_sdist"},
                "cycle_group": "cycle_ext",
                "marker_dependencies": [{"key": "ext[x]@1.0"}],
            },
            "ext[x]@1.0": {
                "cycle_group": "cycle_ext",
                "marker_dependencies": [{"key": "ext@1.0"}],
            },
            "above-ext@1.0": {
                "wheel_candidates": [_whl("ae", "above_ext-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "ext[x]@1.0"}],
            },
        },
        cycle_groups = {"cycle_ext": ["ext@1.0", "ext[x]@1.0"]},
    )
    env.expect.that_bool("reset.bzl" in sdist_extra_out.all).equals(False)
    env.expect.that_str(_library(sdist_extra_out.spokes["above-ext"], "pkg")[0]).equals("pycross_wheel_library")

def _test_reset_cycles(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_cycles_impl)

# buildifier: disable=unused-variable
def _test_reset_gates_impl(env, target):
    """Packages that can fall back to an sdist only reset where a wheel matches."""
    out = _reset_lock({
        "one@1.0": {
            "wheel_candidates": [_whl("one_whl", "one-1.0-cp312-cp312-manylinux_2_17_x86_64.whl")],
            "sdist_file": {"key": "one_sdist"},
        },
        "pure@1.0": {
            "wheel_candidates": [_whl("pure_whl", "pure-1.0-py3-none-any.whl")],
            "sdist_file": {"key": "pure_sdist"},
        },
        "win@1.0": {
            "wheel_candidates": [
                _whl("win_whl", "win-1.0-cp312-cp312-win_amd64.whl"),
                _whl("win_whl32", "win-1.0-cp312-cp312-win32.whl"),
            ],
            "sdist_file": {"key": "win_sdist"},
        },
        "many@1.0": {
            "wheel_candidates": [
                _whl("m1", "many-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"),
                _whl("m2", "many-1.0-cp312-cp312-macosx_11_0_arm64.whl"),
                _whl("m3", "many-1.0-cp312-cp312-win_amd64.whl"),
            ],
            "sdist_file": {"key": "many_sdist"},
        },
        "one[ext]@1.0": {"marker_dependencies": [{"key": "one@1.0"}]},
        "uses-extra@1.0": {
            "wheel_candidates": [_whl("uses_extra_whl", "uses_extra-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "one[ext]@1.0"}],
        },
        "top@1.0": {
            "wheel_candidates": [_whl("top_whl", "top-1.0-py3-none-any.whl")],
            "marker_dependencies": [
                {"key": "one@1.0"},
                {"key": "win@1.0", "marker": "sys_platform == 'win32'"},
                {"key": "win@1.0", "marker": "sys_platform == 'cygwin'"},
            ],
        },
        "no-wheel@1.0": {"sdist_file": {"key": "no_wheel_sdist"}},
        "blocked@1.0": {
            "wheel_candidates": [
                _whl("blk_whl1", "blocked-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"),
                _whl("blk_whl2", "blocked-1.0-cp312-cp312-win_amd64.whl"),
            ],
            "sdist_file": {"key": "blk_sdist"},
            "marker_dependencies": [{"key": "no-wheel@1.0"}],
        },
        "cond-blocked@1.0": {
            "wheel_candidates": [_whl("cb_whl", "cond_blocked-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "no-wheel@1.0", "marker": "sys_platform == 'win32'"}],
        },
    })
    sp = out.spokes

    env.expect.that_str(_library(sp["one"], "pkg")[1]).equals('":_reset_gate"')
    env.expect.that_str(sp["one"]).contains('name = "_reset_gate",\n    actual = ":_wheel_cs_one_1_0_cp312_cp312_manylinux_2_17_x86_64_whl",')
    env.expect.that_collection(_library(sp["pure"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_bool("_wheel_chooser" in sp["pure"]).equals(False)
    env.expect.that_str(_library(sp["win"], "pkg")[1]).equals('":_reset_gate"')
    env.expect.that_str(sp["win"]).contains('name = "_reset_wheel"')
    env.expect.that_str(sp["many"]).contains('name = "_wheel_matched"')
    env.expect.that_str(sp["many"]).contains('"pycross_wheel_matched"')

    env.expect.that_collection(_library(sp["cond-blocked"], "pkg")).contains_exactly(["pycross_resettable_wheel_library", '":_reset_gate"']).in_order()
    env.expect.that_str(sp["cond-blocked"]).contains("_nomatch")

    top = sp["top"]
    env.expect.that_str(_library(top, "pkg")[1]).equals('":_reset_gate"')
    edge_names = [
        line.split('"')[1]
        for line in top.split("\n")
        if 'name = "_reset_edge_' in line
    ]
    env.expect.that_int(len(edge_names)).equals(2)
    env.expect.that_bool(edge_names[0] != edge_names[1]).equals(True)
    edge = top.split('name = "{}",'.format(edge_names[0]))[1].split(")")[0]
    env.expect.that_str(edge).contains("match_any")
    env.expect.that_str(edge).contains("_nomatch")
    env.expect.that_str(edge).contains("@ws__pkg_win//:_reset_gate")
    env.expect.that_str(top).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')

    env.expect.that_str(sp["uses-extra"]).contains('actual = "@ws__pkg_one//:_reset_gate_[ext]"')
    env.expect.that_bool("_reset_wheel" in sp["blocked"]).equals(False)

def _test_reset_gates(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_gates_impl)

# buildifier: disable=unused-variable
def _test_reset_bzl_impl(env, target):
    """state reset.bzl resets canonical //:_state and each flag once via str(Label(...))."""
    res = render_state_reset_bzl(
        ["@r1//_variants:x", "@r1//_variants:x", "@r2//_variants:y"],
        string_flag_labels = ["@r1//_variants:_variants", "@r1//_variants:_variants", "@r2//_variants:_variants"],
    )
    env.expect.that_str(res).contains('str(Label("//:_state")): "",')
    env.expect.that_bool("_pin_" in res).equals(False)
    env.expect.that_bool("_default_" in res).equals(False)
    env.expect.that_bool("_usable_" in res).equals(False)
    env.expect.that_int(res.count('str(Label("@r1//_variants:x")): False,')).equals(1)
    env.expect.that_str(res).contains('str(Label("@r2//_variants:y")): False,')
    env.expect.that_int(res.count('str(Label("@r1//_variants:_variants")): "",')).equals(1)
    env.expect.that_str(res).contains('str(Label("@r2//_variants:_variants")): "",')

    lock = {"packages": {"leaf@1.0": {"wheel_candidates": [_whl("leaf_whl", "leaf-1.0-py3-none-any.whl")]}}}
    plain = _render_spokes(lock, {"leaf_whl": "@r//leaf:wheel"}).spokes["leaf"]
    env.expect.that_bool("reset.bzl" in plain).equals(False)

def _test_reset_bzl(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_bzl_impl)

# buildifier: disable=unused-variable
def _test_scoped_variants_and_grouped_deps_impl(env, target):
    """Verify direct _variant_state wiring, grouped conditional deps, and universal/multi-wheel fast paths."""
    lock = {
        "cycle_groups": {
            "cycle_group_g1": ["cyca@1.0", "cycb@1.0"],
            "cycle_group_g2": ["mha@1.0", "mhb@1.0", "mhc@1.0"],
        },
        "packages": {
            "cyca@1.0": {
                "cycle_group": "cycle_group_g1",
                "wheel_candidates": [_whl("ca", "cyca-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "cycb@1.0", "marker": "extra == '__variant_group_app_gpu'"}],
            },
            "cycb@1.0": {
                "cycle_group": "cycle_group_g1",
                "wheel_candidates": [_whl("cb", "cycb-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "cyca@1.0"}],
            },
            "mha@1.0": {
                "cycle_group": "cycle_group_g2",
                "wheel_candidates": [_whl("mha", "mha-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "mhb@1.0", "marker": "extra == '__variant_group_app_gpu'"}],
            },
            "mhb@1.0": {
                "cycle_group": "cycle_group_g2",
                "wheel_candidates": [_whl("mhb", "mhb-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "mhc@1.0", "marker": "sys_platform == 'win32'"}],
            },
            "mhc@1.0": {
                "cycle_group": "cycle_group_g2",
                "wheel_candidates": [_whl("mhc", "mhc-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "mha@1.0"}],
            },
            "app@1.0": {
                "wheel_candidates": [
                    _whl("app_linux", "app-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"),
                    _whl("app_any", "app-1.0-py3-none-any.whl"),
                ],
                "marker_dependencies": [
                    {"key": "dep_a@1.0", "marker": "sys_platform == 'win32'"},
                    {"key": "dep_b@1.0", "marker": "sys_platform == 'win32'"},
                    {"key": "dep_c@1.0", "marker": "extra == '__variant_group_app_gpu'"},
                ],
            },
            "dep_a@1.0": {"wheel_candidates": [_whl("da", "dep_a-1.0-py3-none-any.whl")]},
            "dep_b@1.0": {"wheel_candidates": [_whl("db", "dep_b-1.0-py3-none-any.whl")]},
            "dep_c@1.0": {
                "wheel_candidates": [
                    _whl("dc1", "dep_c-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"),
                    _whl("dc2", "dep_c-1.0-cp312-cp312-macosx_11_0_arm64.whl"),
                    _whl("dc3", "dep_c-1.0-cp312-cp312-win_amd64.whl"),
                ],
            },
        },
    }
    repo_map = {
        "ca": "@r//ca:whl",
        "cb": "@r//cb:whl",
        "mha": "@r//mha:whl",
        "mhb": "@r//mhb:whl",
        "mhc": "@r//mhc:whl",
        "app_linux": "@r//app:linux",
        "app_any": "@r//app:any",
        "da": "@r//da:whl",
        "db": "@r//db:whl",
        "dc1": "@r//dc:w1",
        "dc2": "@r//dc:w2",
        "dc3": "@r//dc:w3",
    }
    out = _render_spokes(lock, repo_map, has_variants = True)
    sp = out.spokes

    env.expect.that_str(sp["app"]).contains('["@ws__pkg_dep_a//:pkg", "@ws__pkg_dep_b//:pkg"]')
    env.expect.that_str(sp["app"]).contains('name = "_wheel_chooser"')
    env.expect.that_bool("_wheel_available" in sp["app"]).equals(False)

    env.expect.that_str(sp["dep-c"]).contains('name = "_wheel_matched"')
    env.expect.that_str(sp["dep-c"]).contains('name = "_wheel_available"')
    env.expect.that_bool("selects.config_setting_group(" in sp["dep-c"]).equals(False)

    eval_blocks = [
        b.split("\n)")[0]
        for b in out.all.split("pycross_pep508_evaluator(\n")[1:]
    ]
    for block in eval_blocks:
        expr = block.split('expr = "')[1].split('",')[0]
        if "__variant_" in expr:
            env.expect.that_str(block).contains('variants = ["@ws__state//:_variant_state"]')
        else:
            env.expect.that_bool("variants =" in block).equals(False)

    env.expect.that_bool("_CYCLE_EDGES_JSON" in sp["cyca"]).equals(False)
    env.expect.that_bool("_cycle_needed_" in sp["cyca"]).equals(False)

    cyc_block = sp["mha"].split('pycross_cycle_dep_needed(\n    name = "_cycle_needed_mha_mhc",')[1].split("\n)")[0]
    env.expect.that_str(cyc_block).contains('variants = ["@ws__state//:_variant_state"]')

def _test_scoped_variants_and_grouped_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_scoped_variants_and_grouped_deps_impl)

# buildifier: disable=unused-variable
def _test_extras_in_cycle_impl(env, target):
    """Extras proxy inside a cycle emits :_raw_[extra] pointing to :_raw and records the version-free base edge."""
    lock = {
        "cycle_groups": {
            "cycle_group_c1": ["alpha@1.0", "alpha[extra]@1.0", "alpha[explicit]@1.0", "beta@1.0", "gamma[cyc]@1.0"],
        },
        "packages": {
            "alpha@1.0": {
                "cycle_group": "cycle_group_c1",
                "wheel_candidates": [_whl("a_whl", "alpha-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "beta@1.0"}],
            },
            "alpha[extra]@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [{"key": "beta@1.0"}],
            },
            "alpha[explicit]@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [{"key": "alpha@1.0"}, {"key": "beta@1.0"}],
            },
            "beta@1.0": {
                "cycle_group": "cycle_group_c1",
                "wheel_candidates": [_whl("b_whl", "beta-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "alpha[extra]@1.0"}, {"key": "gamma[cyc]@1.0"}],
            },
            "gamma@1.0": {"wheel_candidates": [_whl("g_whl", "gamma-1.0-py3-none-any.whl")]},
            "gamma[cyc]@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [{"key": "beta@1.0"}],
            },
        },
    }
    out = _render_spokes(lock, {"a_whl": "@r//a:whl", "b_whl": "@r//b:whl", "g_whl": "@r//g:whl"})
    alpha = out.spokes["alpha"]
    gamma = out.spokes["gamma"]

    env.expect.that_str(alpha).contains('name = "_raw_[extra]",')
    env.expect.that_str(alpha).contains('actual = ":_raw",')
    env.expect.that_int(alpha.count('name = "[extra]",')).equals(1)
    env.expect.that_str(alpha).contains('pycross_library_proxy(\n    name = "[extra]",\n    actual = ":_raw_[extra]",')

    # Extras proxy inside a cycle whose base is outside the cycle points to :pkg (non-_raw base).
    gamma_proxy = gamma.split('pycross_library_proxy(\n    name = "_raw_[cyc]",')[1].split(")")[0]
    env.expect.that_str(gamma_proxy).contains('actual = ":pkg",')

    # Cycle edges in payload include implicit alpha[extra] -> alpha, dedup explicit alpha[explicit] -> alpha,
    # and omit out-of-cycle gamma.
    alpha_entry = [e for e in out.payloads["alpha"]["entries"] if e["extra"] == "extra"][0]
    edges = alpha_entry["cycle"]["edges"]
    env.expect.that_bool({"dep": "alpha"} in edges["alpha[extra]"]).equals(True)
    env.expect.that_int(len([e for e in edges["alpha[explicit]"] if e == {"dep": "alpha"}])).equals(1)
    env.expect.that_bool("gamma" in [e["dep"] for e in edges["gamma[cyc]"]]).equals(False)

def _test_extras_in_cycle(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_in_cycle_impl)

# buildifier: disable=unused-variable
def _test_marker_deps_dedup_impl(env, target):
    """Duplicate unconditional, shadowed conditional, and overlapping marker deps never duplicate labels."""
    lock = {
        "packages": {
            "app@1.0": {
                "wheel_candidates": [_whl("app_whl", "app-1.0-py3-none-any.whl")],
                "marker_dependencies": [
                    {"key": "uncond@1.0"},
                    {"key": "uncond@1.0"},
                    {"key": "uncond@1.0", "marker": "sys_platform == 'linux'"},
                    {"key": "same_marker@1.0", "marker": "sys_platform == 'linux'"},
                    {"key": "same_marker@1.0", "marker": "sys_platform == 'linux'"},
                    {"key": "overlap@1.0", "marker": "sys_platform == 'linux'"},
                    {"key": "overlap@1.0", "marker": "python_version >= '3.10'"},
                ],
            },
            "uncond@1.0": {"wheel_candidates": [_whl("u_whl", "uncond-1.0-py3-none-any.whl")]},
            "same_marker@1.0": {"wheel_candidates": [_whl("s_whl", "same_marker-1.0-py3-none-any.whl")]},
            "overlap@1.0": {"wheel_candidates": [_whl("o_whl", "overlap-1.0-py3-none-any.whl")]},
        },
    }
    app = _render_spokes(lock, {"app_whl": "@r//app:whl", "u_whl": "@r//u:whl", "s_whl": "@r//s:whl", "o_whl": "@r//o:whl"}).spokes["app"]

    deps_block = app.split("_deps = [")[1].split("\n\n")[0]
    env.expect.that_int(deps_block.count('"@ws__pkg_uncond//:pkg"')).equals(1)
    env.expect.that_int(deps_block.count('"@ws__pkg_same_marker//:pkg"')).equals(1)
    env.expect.that_int(deps_block.count('"@ws__pkg_overlap//:pkg"')).equals(1)
    env.expect.that_str(app).contains('name = "_dep_any_')
    env.expect.that_str(app).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')

def _test_marker_deps_dedup(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_deps_dedup_impl)

# buildifier: disable=unused-variable
def _test_epoch_and_marker_sanitization_impl(env, target):
    """Epoch versions and colons/punctuation in markers produce valid Starlark identifiers and labels."""
    env.expect.that_str(sanitize_name("1!2.0+a (b):c")).equals("1_2_0_a__b__c")
    colon_eval = marker_evaluator_name("platform_version == 'Linux #1:2 (x86)'")
    env.expect.that_bool(":" not in colon_eval).equals(True)
    env.expect.that_bool(" " not in colon_eval).equals(True)
    env.expect.that_bool("(" not in colon_eval and ")" not in colon_eval).equals(True)

    lock = {
        "packages": {
            "foo@1!2.0.0": {
                "wheel_candidates": [_whl("f_whl", "foo-1!2.0.0-py3-none-any.whl")],
                "marker_dependencies": [
                    {"key": "bar@1.0", "marker": "platform_version == 'Linux #1:2 (x86)'"},
                ],
            },
            "bar@1.0": {"wheel_candidates": [_whl("b_whl", "bar-1.0-py3-none-any.whl")]},
        },
    }
    foo = _render_spokes(lock, {"f_whl": "@r//f:whl", "b_whl": "@r//b:whl"}).spokes["foo"]
    env.expect.that_str(foo).contains("_deps = [")
    env.expect.that_str(foo).contains('name = "{}"'.format(colon_eval))

def _test_epoch_and_marker_sanitization(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_epoch_and_marker_sanitization_impl)

# buildifier: disable=unused-variable
def _test_wheel_available_always_emitted_impl(env, target):
    """Wheel-only platform-specific packages always emit _wheel_available for thin-repo composition."""
    lock = {
        "packages": {
            "nomarker@1.0": {
                "wheel_candidates": [
                    _whl("nm1", "nomarker-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"),
                    _whl("nm2", "nomarker-1.0-cp312-cp312-win_amd64.whl"),
                ],
            },
            "withmarker@1.0": {
                "wheel_candidates": [_whl("wm1", "withmarker-1.0-cp312-cp312-manylinux_2_17_x86_64.whl")],
                "availability_markers": ["sys_platform == 'linux'"],
            },
        },
    }
    out = _render_spokes(lock, {"nm1": "@r//nm:w1", "nm2": "@r//nm:w2", "wm1": "@r//wm:w1"})
    env.expect.that_str(out.spokes["nomarker"]).contains('name = "_wheel_available",')
    env.expect.that_str(out.spokes["withmarker"]).contains('name = "_wheel_available",')
    env.expect.that_bool('"_available_' in out.all).equals(False)
    env.expect.that_bool('"_marker_available_' in out.all).equals(False)

def _test_wheel_available_always_emitted(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_available_always_emitted_impl)

# buildifier: disable=unused-variable
def _test_sdist_deps_proxy_rendering_impl(env, target):
    """Sdist-buildable packages with deps emit :_sdist_deps using marker-gated, cycle-filtered deps."""
    lock = {
        "cycle_groups": {"cycle_0": ["cyc_sdist@1.0", "cyc_peer@1.0"]},
        "packages": {
            "cyc_sdist@1.0": {
                "sdist_file": {"key": "cyc_sdist_tar"},
                "cycle_group": "cycle_0",
                "marker_dependencies": [
                    {"key": "cyc_peer@1.0"},
                    {"key": "win_dep@1.0", "marker": "sys_platform == 'win32'"},
                    {"key": "common_dep@1.0"},
                ],
            },
            "cyc_peer@1.0": {
                "sdist_file": {"key": "cp_sdist"},
                "wheel_candidates": [_whl("cp_whl", "cyc_peer-1.0-cp312-cp312-manylinux_2_17_x86_64.whl")],
                "cycle_group": "cycle_0",
                "marker_dependencies": [{"key": "cyc_sdist@1.0"}],
            },
            "win_dep@1.0": {
                "wheel_candidates": [_whl("w_whl", "win_dep-1.0-py3-none-any.whl")],
                "marker_dependencies": [{"key": "common_dep@1.0"}],
            },
            "common_dep@1.0": {"wheel_candidates": [_whl("c_whl", "common_dep-1.0-py3-none-any.whl")]},
            "nodeps_sdist@1.0": {"sdist_file": {"key": "nodeps_tar"}},
            "never_sdist@1.0": {
                "sdist_file": {"key": "never_tar"},
                "build_mode": "never",
                "marker_dependencies": [{"key": "common_dep@1.0"}],
            },
            "custom_sdist@1.0": {
                "sdist_file": {"key": "custom_tar"},
                "build_target": "//custom:wheel",
                "marker_dependencies": [{"key": "common_dep@1.0"}],
            },
        },
    }
    repo_map = {
        "cyc_sdist_tar": "@r//cyc:sdist",
        "cp_sdist": "@r//cp:sdist",
        "cp_whl": "@r//cp:whl",
        "w_whl": "@r//w:whl",
        "c_whl": "@r//c:whl",
        "nodeps_tar": "@r//nodeps:sdist",
        "never_tar": "@r//never:sdist",
        "custom_tar": "@r//custom:sdist",
    }
    sp = _render_spokes(lock, repo_map).spokes

    env.expect.that_str(sp["cyc-sdist"]).contains('pycross_library_proxy(\n    name = "_sdist_deps",\n    deps = _deps,\n)')
    env.expect.that_str(sp["cyc-peer"]).contains('pycross_library_proxy(\n    name = "_sdist_deps",\n    deps = _deps,\n)')
    peer_deps_block = sp["cyc-peer"].split("_deps = [")[1].split("\n\n")[0]
    env.expect.that_bool("cyc_sdist" in peer_deps_block).equals(False)

    deps_block = sp["cyc-sdist"].split("_deps = [")[1].split("\n\n")[0]
    env.expect.that_bool("cyc_peer" in deps_block).equals(False)
    env.expect.that_str(deps_block).contains('"@ws__pkg_common_dep//:pkg"')
    env.expect.that_str(deps_block).contains('"@ws__pkg_win_dep//:pkg"')
    env.expect.that_str(deps_block).contains("select({")

    env.expect.that_bool("_sdist_deps" in sp["nodeps-sdist"]).equals(False)
    env.expect.that_bool("_sdist_deps" in sp["never-sdist"]).equals(False)
    env.expect.that_bool("_sdist_deps" in sp["custom-sdist"]).equals(False)
    env.expect.that_bool("_sdist_deps" in sp["win-dep"]).equals(False)

def _test_sdist_deps_proxy_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_sdist_deps_proxy_rendering_impl)

# buildifier: disable=unused-variable
def _test_reset_bzl_load_only_when_resettable_impl(env, target):
    """Spokes load @<ws>__state//:reset.bzl only when an entry actually resets."""
    sdist_only = _reset_lock({"src@1.0": {"sdist_file": {"key": "src_sdist"}}})
    env.expect.that_bool("reset.bzl" in sdist_only.spokes["src"]).equals(False)

    with_wheel = _reset_lock({"leaf@1.0": {"wheel_candidates": [_whl("leaf_whl", "leaf-1.0-py3-none-any.whl")]}})
    env.expect.that_str(with_wheel.spokes["leaf"]).contains('load("@ws__state//:reset.bzl", "pycross_resettable_wheel_library")')

def _test_reset_bzl_load_only_when_resettable(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_bzl_load_only_when_resettable_impl)

# buildifier: disable=unused-variable
def _test_cross_spoke_gated_reset_chain_impl(env, target):
    """A conditional dep on a gated downstream spoke composes local _nomatch with the dep's cross-spoke :_reset_gate."""
    out = _reset_lock({
        "sdist-leaf@1.0": {"sdist_file": {"key": "leaf_sdist"}},
        "mid@1.0": {
            "wheel_candidates": [_whl("mid_whl", "mid-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "sdist-leaf@1.0", "marker": "sys_platform == 'linux'"}],
        },
        "top@1.0": {
            "wheel_candidates": [_whl("top_whl", "top-1.0-py3-none-any.whl")],
            "marker_dependencies": [{"key": "mid@1.0", "marker": "sys_platform == 'linux'"}],
        },
    })
    linux_eval = marker_evaluator_name("sys_platform == 'linux'")
    env.expect.that_str(out.spokes["mid"]).contains('actual = ":{}_nomatch",'.format(linux_eval))
    env.expect.that_str(out.spokes["top"]).contains('":{}_nomatch",'.format(linux_eval))
    env.expect.that_str(out.spokes["top"]).contains('"@ws__pkg_mid//:_reset_gate",')

def _test_cross_spoke_gated_reset_chain(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cross_spoke_gated_reset_chain_impl)

def resolved_lock_renderer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_render_lock,
            _test_reset_bzl_load_only_when_resettable,
            _test_cross_spoke_gated_reset_chain,
            _test_reset_plan,
            _test_marker_depends_on_variants_cache,
            _test_reset_cycles,
            _test_reset_gates,
            _test_reset_bzl,
            _test_scoped_variants_and_grouped_deps,
            _test_extras_in_cycle,
            _test_marker_deps_dedup,
            _test_epoch_and_marker_sanitization,
            _test_wheel_available_always_emitted,
            _test_sdist_deps_proxy_rendering,
            _test_epoch_sdist_repo_name,
            _test_cycle_group_rendering,
            _test_cycle_group_marker_specific_rendering,
            _test_extras_rendering,
            _test_spoke_build_format,
            _test_no_cycles_no_cycle_targets,
            _test_marker_deps_rendering,
            _test_multi_platform_repo_map,
            _test_available_config_setting_group,
            _test_extras_inherit_base_available,
            _test_build_mode_never_no_sdist_fallback,
            _test_resolution_marker_member_rendering,
            _test_wheel_library_tags_and_precompile_rendering,
            _test_conflict_state_rendering,
        ],
    )
