"""Tests for resolved_lock_renderer"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:resolved_lock_renderer.bzl", "render_lock_bzl")

# buildifier: disable=unused-variable
def _test_render_lock_impl(env, target):
    """Verify basic rendering with wheel_candidates (wheel selection via pycross_wheel_chooser)."""
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
    repo_map = {"foo_wheel": "@my_repo//foo:wheel"}
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    env.expect.that_bool("pycross_wheel_library(" in res).equals(True)
    env.expect.that_bool("pycross_wheel_chooser(" in res).equals(True)

def _test_render_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_rendering_impl(env, target):
    """Verify cycle groups generate pycross_cycle_member_marker_deps targets."""
    lock = {
        "cycle_groups": {
            "cycle_group_abc123": ["alpha@1.0", "beta@2.0"],
        },
        "packages": {
            "alpha@1.0": {
                "cycle_group": "cycle_group_abc123",
                "marker_dependencies": [
                    {"key": "beta@2.0", "marker": None},
                ],
                "wheel_candidates": [
                    {
                        "filename": "alpha-1.0-py3-none-any.whl",
                        "file_reference": {"key": "alpha_wheel"},
                    },
                ],
            },
            "beta@2.0": {
                "cycle_group": "cycle_group_abc123",
                "marker_dependencies": [
                    {"key": "alpha@1.0", "marker": None},
                ],
                "wheel_candidates": [
                    {
                        "filename": "beta-2.0-py3-none-any.whl",
                        "file_reference": {"key": "beta_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "alpha_wheel": "@repo//alpha:wheel",
        "beta_wheel": "@repo//beta:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Should use pycross_cycle_member_marker_deps (not legacy pycross_cycle_member_deps)
    env.expect.that_bool("pycross_cycle_member_marker_deps(" in res).equals(True)
    env.expect.that_bool("pycross_cycle_member_deps(" not in res).equals(True)

    # Should reference _raw_ targets for both cycle members
    env.expect.that_bool('"_raw_alpha@1.0"' in res).equals(True)
    env.expect.that_bool('"_raw_beta@2.0"' in res).equals(True)

    # Both cycle members should have marker_deps macro calls
    env.expect.that_bool('member = "alpha@1.0"' in res).equals(True)
    env.expect.that_bool('member = "beta@2.0"' in res).equals(True)

    # Cycled package deps should exclude same-cycle members from _deps list
    alpha_deps_section = res.split("_alpha_1_0_deps = [")[1].split("]")[0] if "_alpha_1_0_deps = [" in res else ""
    env.expect.that_bool('"beta@2.0"' not in alpha_deps_section).equals(True)

def _test_cycle_group_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_group_rendering_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_marker_specific_rendering_impl(env, target):
    """Verify cycle groups with marker-gated deps generate correct edges JSON."""
    lock = {
        "cycle_groups": {
            "cycle_group_abc": ["alpha@1.0", "beta@2.0", "appnope@1.0"],
        },
        "packages": {
            "alpha@1.0": {
                "cycle_group": "cycle_group_abc",
                "marker_dependencies": [
                    {"key": "beta@2.0", "marker": None},
                    {
                        "key": "appnope@1.0",
                        "marker": "sys_platform == \"darwin\"",
                        "marker_ast": {
                            "op": "==",
                            "lhs": {"type": "marker", "value": "sys_platform"},
                            "rhs": {"type": "string", "value": "darwin"},
                        },
                    },
                ],
                "wheel_candidates": [
                    {
                        "filename": "alpha-1.0-py3-none-any.whl",
                        "file_reference": {"key": "alpha_wheel"},
                    },
                ],
            },
            "beta@2.0": {
                "cycle_group": "cycle_group_abc",
                "marker_dependencies": [
                    {"key": "alpha@1.0", "marker": None},
                ],
                "wheel_candidates": [
                    {
                        "filename": "beta-2.0-py3-none-any.whl",
                        "file_reference": {"key": "beta_wheel"},
                    },
                ],
            },
            "appnope@1.0": {
                "cycle_group": "cycle_group_abc",
                "marker_dependencies": [
                    {"key": "alpha@1.0", "marker": None},
                ],
                "wheel_candidates": [
                    {
                        "filename": "appnope-1.0-py3-none-any.whl",
                        "file_reference": {"key": "appnope_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "alpha_wheel": "@repo//alpha:wheel",
        "beta_wheel": "@repo//beta:wheel",
        "appnope_wheel": "@repo//appnope:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Each member should have its own macro call
    env.expect.that_bool('member = "alpha@1.0"' in res).equals(True)
    env.expect.that_bool('member = "beta@2.0"' in res).equals(True)
    env.expect.that_bool('member = "appnope@1.0"' in res).equals(True)

    # The edges JSON should include marker for the conditional edge
    env.expect.that_bool('"marker":' in res).equals(True)
    env.expect.that_bool("marker_ast" in res).equals(False)

def _test_cycle_group_marker_specific_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_group_marker_specific_rendering_impl)

# buildifier: disable=unused-variable
def _test_extras_rendering_impl(env, target):
    """Verify extra_dependencies generate pycross_library_proxy targets named [extra_name]."""
    lock = {
        "packages": {
            "mylib@1.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "mylib-1.0-py3-none-any.whl",
                        "file_reference": {"key": "mylib_wheel"},
                    },
                ],
            },
            "mylib[test]@1.0": {
                "marker_dependencies": [
                    {"key": "pytest@7.0", "marker": None},
                ],
            },
            "mylib[dev]@1.0": {
                "marker_dependencies": [
                    {"key": "black@23.0", "marker": None},
                    {
                        "key": "mypy@1.5",
                        "marker": "sys_platform == \"linux\"",
                        "marker_ast": {
                            "op": "==",
                            "lhs": {"type": "marker", "value": "sys_platform"},
                            "rhs": {"type": "string", "value": "linux"},
                        },
                    },
                ],
            },
            "pytest@7.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "pytest-7.0-py3-none-any.whl",
                        "file_reference": {"key": "pytest_wheel"},
                    },
                ],
            },
            "black@23.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "black-23.0-py3-none-any.whl",
                        "file_reference": {"key": "black_wheel"},
                    },
                ],
            },
            "mypy@1.5": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "mypy-1.5-py3-none-any.whl",
                        "file_reference": {"key": "mypy_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "mylib_wheel": "@repo//mylib:wheel",
        "pytest_wheel": "@repo//pytest:wheel",
        "black_wheel": "@repo//black:wheel",
        "mypy_wheel": "@repo//mypy:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Should have py_library for [test] extra
    env.expect.that_bool('"mylib[test]@1.0"' in res).equals(True)

    # [test] deps should include pytest
    env.expect.that_bool('":pytest@7.0"' in res).equals(True)

    # Should have py_library for [dev] extra
    env.expect.that_bool('"mylib[dev]@1.0"' in res).equals(True)

    # [dev] deps should include black (unconditional) and mypy (marker-conditional via select)
    env.expect.that_bool('":black@23.0"' in res).equals(True)
    env.expect.that_bool('":mypy@1.5"' in res).equals(True)

    # [dev] should use select for marker-conditional deps
    env.expect.that_bool("select({" in res).equals(True)

    # extras use pycross_library_proxy
    env.expect.that_bool("pycross_library_proxy" in res).equals(True)

    # Should generate an [_all_] target that aggregates the base and all extras
    env.expect.that_bool('name = "mylib[_all_]@1.0"' in res).equals(True)

    # The [_all_] target should depend on the base and all extras
    all_target_section = res.split('name = "mylib[_all_]@1.0"')[1].split(")", 1)[0]
    env.expect.that_bool('":mylib@1.0"' in all_target_section).equals(True)
    env.expect.that_bool('":mylib[test]@1.0"' in all_target_section).equals(True)
    env.expect.that_bool('":mylib[dev]@1.0"' in all_target_section).equals(True)

def _test_extras_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_rendering_impl)

# buildifier: disable=unused-variable
def _test_lock_bzl_format_impl(env, target):
    """Verify the renderer produces a single lock.bzl string with targets() function."""
    lock = {
        "packages": {
            "numpy@1.26.4": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "numpy-1.26.4-py3-none-any.whl",
                        "file_reference": {"key": "numpy_wheel"},
                    },
                ],
            },
            "pandas@2.1.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "pandas-2.1.0-py3-none-any.whl",
                        "file_reference": {"key": "pandas_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "numpy_wheel": "@repo//numpy:wheel",
        "pandas_wheel": "@repo//pandas:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Should be a string, not a dict
    env.expect.that_bool(type(res) == "string").equals(True)

    # Should have targets() function
    env.expect.that_bool("def targets():" in res).equals(True)

    # Should have pycross_wheel_library for both packages
    env.expect.that_bool('package_name = "numpy"' in res).equals(True)
    env.expect.that_bool('package_version = "1.26.4"' in res).equals(True)
    env.expect.that_bool('package_name = "pandas"' in res).equals(True)
    env.expect.that_bool('package_version = "2.1.0"' in res).equals(True)

    # Should have dist_info targets
    env.expect.that_bool("pycross_dist_info(" in res).equals(True)

    # Should always have marker-related loads
    env.expect.that_bool("pycross_pep508_evaluator" in res).equals(True)
    env.expect.that_bool("pycross_wheel_chooser" in res).equals(True)
    env.expect.that_bool("pep508_marker_values" in res).equals(True)

def _test_lock_bzl_format(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_lock_bzl_format_impl)

# buildifier: disable=unused-variable
def _test_no_cycles_no_cycle_targets_impl(env, target):
    """Verify that when there are no cycles, no _cycle_ targets are generated."""
    lock = {
        "packages": {
            "a@1.0": {
                "marker_dependencies": [
                    {"key": "b@2.0", "marker": None},
                ],
                "wheel_candidates": [
                    {
                        "filename": "a-1.0-py3-none-any.whl",
                        "file_reference": {"key": "a_wheel"},
                    },
                ],
            },
            "b@2.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "b-2.0-py3-none-any.whl",
                        "file_reference": {"key": "b_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "a_wheel": "@repo//a:wheel",
        "b_wheel": "@repo//b:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")
    env.expect.that_bool("_cycle_" not in res).equals(True)

    # a should use "a@1.0" not "_raw_"
    env.expect.that_bool('name = "a@1.0"' in res).equals(True)
    env.expect.that_bool("_raw_" not in res).equals(True)

def _test_no_cycles_no_cycle_targets(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_cycles_no_cycle_targets_impl)

# buildifier: disable=unused-variable
def _test_marker_deps_rendering_impl(env, target):
    """Verify marker_dependencies renders evaluator + config_setting + select."""
    lock = {
        "packages": {
            "foo@1.0": {
                "marker_dependencies": [
                    {"key": "bar@2.0", "marker": None},
                    {
                        "key": "baz@3.0",
                        "marker": "sys_platform == \"linux\"",
                        "marker_ast": {
                            "op": "==",
                            "lhs": {"type": "marker", "value": "sys_platform"},
                            "rhs": {"type": "string", "value": "linux"},
                        },
                    },
                ],
                "wheel_candidates": [
                    {
                        "filename": "foo-1.0-py3-none-any.whl",
                        "file_reference": {"key": "foo_wheel"},
                    },
                ],
            },
            "bar@2.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "bar-2.0-py3-none-any.whl",
                        "file_reference": {"key": "bar_wheel"},
                    },
                ],
            },
            "baz@3.0": {
                "marker_dependencies": [],
                "wheel_candidates": [
                    {
                        "filename": "baz-3.0-py3-none-any.whl",
                        "file_reference": {"key": "baz_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "foo_wheel": "@repo//foo:wheel",
        "bar_wheel": "@repo//bar:wheel",
        "baz_wheel": "@repo//baz:wheel",
    }
    res = render_lock_bzl(lock, repo_map, rctx_name = "my_rctx")

    # Should load the marker-related symbols
    env.expect.that_bool("pycross_pep508_evaluator" in res).equals(True)
    env.expect.that_bool("pycross_wheel_chooser" in res).equals(True)
    env.expect.that_bool("pep508_marker_values" in res).equals(True)

    # Should have an evaluator target for the sys_platform marker
    env.expect.that_bool("_marker_eval_" in res).equals(True)
    env.expect.that_bool("sys_platform" in res).equals(True)

    # Should have a config_setting matching the evaluator
    env.expect.that_bool("_match" in res).equals(True)

    # bar@2.0 should be an unconditional dep (no marker)
    env.expect.that_bool('":bar@2.0"' in res).equals(True)

    # baz@3.0 should be a conditional dep behind select
    env.expect.that_bool('":baz@3.0"' in res).equals(True)
    env.expect.that_bool("select({" in res).equals(True)

    # Should have wheel chooser for foo
    env.expect.that_bool("_wheel_chooser_foo@1.0" in res).equals(True)

    # Should have alias for wheel selection
    env.expect.that_bool("native.alias(" in res).equals(True)

def _test_marker_deps_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_deps_rendering_impl)

# buildifier: disable=unused-variable
def _test_multi_platform_repo_map_impl(env, target):
    """Verify multi-platform repo_map entries render correctly as string references."""
    lock = {
        "packages": {
            "crypto@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "crypto-1.0-cp311-cp311-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "crypto_linux_x86"},
                    },
                    {
                        "filename": "crypto-1.0-cp311-cp311-win_amd64.whl",
                        "file_reference": {"key": "crypto_win"},
                    },
                    {
                        "filename": "crypto-1.0-cp311-cp311-win32.whl",
                        "file_reference": {"key": "crypto_win32"},
                    },
                    {
                        "filename": "crypto-1.0-cp311-cp311-macosx_11_0_arm64.whl",
                        "file_reference": {"key": "crypto_macos"},
                    },
                ],
            },
        },
    }

    # repo_map uses string keys (file_key -> label), not label keys.
    # This mirrors the fix in ea1480c where we switched from
    # label_keyed_string_dict to string_dict.
    repo_map = {
        "crypto_linux_x86": "@pypi_crypto_linux//:wheel",
        "crypto_win": "@pypi_crypto_win//:wheel",
        "crypto_win32": "@pypi_crypto_win32//:wheel",
        "crypto_macos": "@pypi_crypto_macos//:wheel",
    }
    res = render_lock_bzl(lock, repo_map, rctx_name = "my_rctx")

    # All platform-specific labels should appear as string references
    # in the rendered output.
    env.expect.that_bool("@pypi_crypto_linux//:wheel" in res).equals(True)
    env.expect.that_bool("@pypi_crypto_win//:wheel" in res).equals(True)
    env.expect.that_bool("@pypi_crypto_win32//:wheel" in res).equals(True)
    env.expect.that_bool("@pypi_crypto_macos//:wheel" in res).equals(True)

    # Should have a wheel chooser for the multi-platform package
    env.expect.that_bool("pycross_wheel_chooser(" in res).equals(True)
    env.expect.that_bool("_wheel_chooser_crypto@1.0" in res).equals(True)

def _test_multi_platform_repo_map(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_multi_platform_repo_map_impl)

# ── Test: _available_ config_setting_group ─────────────────────────

# buildifier: disable=unused-variable
def _test_available_config_setting_group_impl(env, target):
    """Verify _available_ config_setting_group is emitted for packages without sdist."""
    lock = {
        "packages": {
            "platform_pkg@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "platform_pkg-1.0-cp310-cp310-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "plat_linux"},
                    },
                    {
                        "filename": "platform_pkg-1.0-cp310-cp310-win_amd64.whl",
                        "file_reference": {"key": "plat_win"},
                    },
                ],
            },
            "sdist_pkg@2.0": {
                "sdist_file": {"key": "sdist_key"},
                "wheel_candidates": [
                    {
                        "filename": "sdist_pkg-2.0-cp310-cp310-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "sdist_linux"},
                    },
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
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Platform-specific package (no sdist) should get _available_ group.
    env.expect.that_bool("_available_platform_pkg@1.0" in res).equals(True)
    env.expect.that_bool("config_setting_group(" in res).equals(True)

    # Package with sdist should NOT get _available_ group.
    env.expect.that_bool("_available_sdist_pkg@2.0" in res).equals(False)

    # Selects load should be present (at least one platform-specific package).
    env.expect.that_bool("selects" in res).equals(True)

def _test_available_config_setting_group(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_available_config_setting_group_impl)

# ── Test: no _available_ when all have sdist ──────────────────────

# buildifier: disable=unused-variable
def _test_no_available_when_all_have_sdist_impl(env, target):
    """Verify no selects load and no _available_ when all packages have sdist."""
    lock = {
        "packages": {
            "pkg@1.0": {
                "sdist_file": {"key": "sdist_key"},
                "wheel_candidates": [
                    {
                        "filename": "pkg-1.0-cp310-cp310-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "pkg_wheel"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "pkg_wheel": "@repo//pkg:wheel",
        "sdist_key": "@repo//pkg:sdist",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    env.expect.that_bool("_available_" in res).equals(False)
    env.expect.that_bool("selects" in res).equals(False)

def _test_no_available_when_all_have_sdist(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_available_when_all_have_sdist_impl)

# buildifier: disable=unused-variable
def _test_extras_inherit_base_available_impl(env, target):
    """Extras of a wheel-only package are gated by the base's _available_ group."""
    lock = {
        "packages": {
            "plat@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "plat-1.0-cp310-cp310-win_amd64.whl",
                        "file_reference": {"key": "plat_win"},
                    },
                ],
            },
            "plat[extra]@1.0": {},
        },
    }
    repo_map = {"plat_win": "@repo//plat:win_wheel"}
    res = render_lock_bzl(lock, repo_map, rctx_name = "my_rctx")

    alias = res.split('name = "_available_plat[extra]@1.0"')[1].split(")", 1)[0]
    env.expect.that_str(alias).contains('actual = ":_available_plat@1.0"')

def _test_extras_inherit_base_available(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_inherit_base_available_impl)

# buildifier: disable=unused-variable
def _test_build_mode_never_no_sdist_fallback_impl(env, target):
    """build_mode = "never" packages don't fall back to the sdist build and get _available_."""
    lock = {
        "packages": {
            "pkg@1.0": {
                "sdist_file": {"key": "sdist_key"},
                "build_mode": "never",
                "wheel_candidates": [
                    {
                        "filename": "pkg-1.0-cp310-cp310-win_amd64.whl",
                        "file_reference": {"key": "pkg_win"},
                    },
                ],
            },
        },
    }
    repo_map = {
        "pkg_win": "@repo//pkg:win_wheel",
        "sdist_key": "@repo//pkg:sdist",
    }
    res = render_lock_bzl(lock, repo_map, rctx_name = "my_rctx")

    env.expect.that_bool("my_rctx_sdist_" in res).equals(False)
    env.expect.that_str(res).contains("@rules_pycross//pycross/private:no_match_error")
    env.expect.that_str(res).contains('name = "_available_pkg@1.0"')

def _test_build_mode_never_no_sdist_fallback(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_mode_never_no_sdist_fallback_impl)

# buildifier: disable=unused-variable
def _test_resolution_marker_evaluator_rendering_impl(env, target):
    """Verify resolution_marker_exprs generate evaluator + config_setting targets."""
    lock = {
        "packages": {
            "numpy@2.3.4": {
                "wheel_candidates": [
                    {
                        "filename": "numpy-2.3.4-cp312-cp312-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "numpy_wheel_linux"},
                    },
                ],
            },
            "numpy@2.3.3": {
                "wheel_candidates": [
                    {
                        "filename": "numpy-2.3.3-cp312-cp312-macosx_11_0_arm64.whl",
                        "file_reference": {"key": "numpy_wheel_mac"},
                    },
                ],
            },
        },
        "resolution_marker_exprs": {
            "res_numpy_2_3_4": "sys_platform == 'linux'",
            "res_numpy_2_3_3": "sys_platform == 'darwin'",
        },
    }
    repo_map = {
        "numpy_wheel_linux": "@repo//numpy:wheel_linux",
        "numpy_wheel_mac": "@repo//numpy:wheel_mac",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Should generate pycross_pep508_evaluator for each fork
    env.expect.that_bool("pycross_pep508_evaluator(" in res).equals(True)
    env.expect.that_bool("_res_eval_res_numpy_2_3_4" in res).equals(True)
    env.expect.that_bool("_res_eval_res_numpy_2_3_3" in res).equals(True)

    # Should generate config_settings with is_ prefix
    env.expect.that_bool('"is_res_numpy_2_3_4"' in res).equals(True)
    env.expect.that_bool('"is_res_numpy_2_3_3"' in res).equals(True)

    # Should contain the marker expressions
    env.expect.that_bool("sys_platform == 'linux'" in res).equals(True)
    env.expect.that_bool("sys_platform == 'darwin'" in res).equals(True)

def _test_resolution_marker_evaluator_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_resolution_marker_evaluator_rendering_impl)

# buildifier: disable=unused-variable
def _test_resolution_marker_compound_rendering_impl(env, target):
    """Verify compound resolution-marker constraints use config_setting_group."""
    lock = {
        "packages": {
            "numpy@2.3.4": {
                "wheel_candidates": [
                    {
                        "filename": "numpy-2.3.4-cp312-cp312-manylinux_2_17_x86_64.whl",
                        "file_reference": {"key": "numpy_whl"},
                    },
                ],
            },
        },
        "resolution_marker_exprs": {
            "res_numpy_2_3_4": "sys_platform == 'linux'",
            "extra_science_res_numpy_2_3_4": {
                "variant": "extra_science",
                "marker": "res_numpy_2_3_4",
            },
        },
    }
    repo_map = {"numpy_whl": "@repo//numpy:wheel"}
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Compound should use config_setting_group
    env.expect.that_bool("selects.config_setting_group(" in res).equals(True)
    env.expect.that_bool('"is_extra_science_res_numpy_2_3_4"' in res).equals(True)
    env.expect.that_bool("match_all" in res).equals(True)
    env.expect.that_bool('"is_extra_science"' in res).equals(True)
    env.expect.that_bool('"is_res_numpy_2_3_4"' in res).equals(True)

    # selects.bzl should be loaded
    env.expect.that_bool('load("@bazel_skylib//lib:selects.bzl"' in res).equals(True)

def _test_resolution_marker_compound_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_resolution_marker_compound_rendering_impl)

# buildifier: disable=unused-variable
def _test_wheel_library_tags_rendering_impl(env, target):
    """Verify that wheel_library_tags is rendered as tags on pycross_wheel_library."""
    lock = {
        "packages": {
            "foo@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "foo-1.0-py3-none-any.whl",
                        "file_reference": {"key": "foo_wheel"},
                    },
                ],
                "wheel_library_tags": ["no-remote", "custom-tag"],
            },
        },
    }
    repo_map = {"foo_wheel": "@my_repo//foo:wheel"}
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    env.expect.that_bool("tags = [" in res).equals(True)
    env.expect.that_bool('"no-remote",' in res).equals(True)
    env.expect.that_bool('"custom-tag",' in res).equals(True)

def _test_wheel_library_tags_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_library_tags_rendering_impl)

# buildifier: disable=unused-variable
def _test_precompile_rendering_impl(env, target):
    """Verify that precompile is rendered on pycross_wheel_library only when non-empty."""
    lock = {
        "packages": {
            "compiled@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "compiled-1.0-py3-none-any.whl",
                        "file_reference": {"key": "compiled_wheel"},
                    },
                ],
                "precompile": "enabled",
            },
            "default_pkg@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "default_pkg-1.0-py3-none-any.whl",
                        "file_reference": {"key": "default_wheel"},
                    },
                ],
                "precompile": "",
            },
        },
    }
    repo_map = {
        "compiled_wheel": "@my_repo//compiled:wheel",
        "default_wheel": "@my_repo//default_pkg:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    env.expect.that_bool('precompile = "enabled",' in res).equals(True)
    env.expect.that_bool('precompile = ""' in res).equals(False)
    env.expect.that_int(res.count("precompile =")).equals(1)

def _test_precompile_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_precompile_rendering_impl)

# buildifier: disable=unused-variable
def _test_epoch_sdist_repo_name_impl(env, target):
    """The sdist repo label must use the same sanitization as lock_repo_creation (e.g. epoch '!')."""
    lock = {
        "packages": {
            "foo@1!2.0": {
                "sdist_file": {"key": "foo_sdist"},
                "wheel_candidates": [],
            },
        },
    }
    res = render_lock_bzl(lock, {"foo_sdist": "@repo//file:foo-1!2.0.tar.gz"}, rctx_name = "uv__pkgs")
    env.expect.that_bool("@@uv__pkgs_sdist_foo_1_2_0//:wheel" in res).equals(True)

def _test_epoch_sdist_repo_name(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_epoch_sdist_repo_name_impl)

def resolved_lock_renderer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_render_lock,
            _test_epoch_sdist_repo_name,
            _test_cycle_group_rendering,
            _test_cycle_group_marker_specific_rendering,
            _test_extras_rendering,
            _test_lock_bzl_format,
            _test_no_cycles_no_cycle_targets,
            _test_marker_deps_rendering,
            _test_multi_platform_repo_map,
            _test_available_config_setting_group,
            _test_no_available_when_all_have_sdist,
            _test_extras_inherit_base_available,
            _test_build_mode_never_no_sdist_fallback,
            _test_resolution_marker_evaluator_rendering,
            _test_resolution_marker_compound_rendering,
            _test_wheel_library_tags_rendering,
            _test_precompile_rendering,
        ],
    )
