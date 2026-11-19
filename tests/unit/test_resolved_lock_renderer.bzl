"""Tests for resolved_lock_renderer"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:resolved_lock_renderer.bzl", "render_lock_bzl", "render_reset_bzl")

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

# buildifier: disable=unused-variable
def _test_conflict_state_rendering_impl(env, target):
    """Verify variants is emitted only on __variant_-referencing evaluators when variant_resolvers is provided."""
    t_cuda = "__variant_group_cuda"
    conflict_marker = "sys_platform == 'linux' and extra == '{}'".format(t_cuda)
    plain_extra_marker = "extra == 'cudart'"
    plain_marker = "sys_platform == 'darwin'"
    lock = {
        "cycle_groups": {
            "cycle_group_c1": ["cyca@1.0", "cycb@1.0"],
        },
        "packages": {
            "cuda-toolkit@13.0.2": {
                "availability_markers": [conflict_marker],
                "wheel_candidates": [
                    {
                        "filename": "cuda_toolkit-13.0.2-py3-none-any.whl",
                        "file_reference": {"key": "ct_whl"},
                    },
                ],
            },
            "cuda-toolkit[cudart]@13.0.2": {
                "marker_dependencies": [
                    {"key": "dep_a@1.0", "marker": conflict_marker},
                    {"key": "dep_b@1.0", "marker": plain_marker},
                    {"key": "dep_b@1.0", "marker": plain_extra_marker},
                ],
            },
            "dep_a@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "dep_a-1.0-py3-none-any.whl",
                        "file_reference": {"key": "da_whl"},
                    },
                ],
            },
            "dep_b@1.0": {
                "wheel_candidates": [
                    {
                        "filename": "dep_b-1.0-py3-none-any.whl",
                        "file_reference": {"key": "db_whl"},
                    },
                ],
            },
            "cyca@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [
                    {"key": "cycb@1.0", "marker": conflict_marker},
                ],
                "wheel_candidates": [
                    {
                        "filename": "cyca-1.0-py3-none-any.whl",
                        "file_reference": {"key": "ca_whl"},
                    },
                ],
            },
            "cycb@1.0": {
                "cycle_group": "cycle_group_c1",
                "marker_dependencies": [
                    {"key": "cyca@1.0", "marker": None},
                ],
                "wheel_candidates": [
                    {
                        "filename": "cycb-1.0-py3-none-any.whl",
                        "file_reference": {"key": "cb_whl"},
                    },
                ],
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
    }
    res_with_variants = render_lock_bzl(
        lock,
        repo_map,
        rctx_name = "my_rctx",
        variant_resolvers = [":_resolver_group_cpu_group_cuda"],
    )
    res_without_variants = render_lock_bzl(
        lock,
        repo_map,
        rctx_name = "my_rctx",
    )

    # Without variant_resolvers, variants is never emitted.
    env.expect.that_int(res_without_variants.count('variants = [":_resolver_group_cpu_group_cuda"]')).equals(0)

    # With variant_resolvers, variants = [":_resolver_group_cpu_group_cuda"] appears on:
    # - _marker_eval_* for availability_markers (extra="") (1)
    # - _marker_eval_* for cuda-toolkit[cudart] (extra="cudart") (1)
    # - _res_eval_res_fork_conflict (1)
    # - the 2 cycle members in cycle_group_c1 (2)
    # and NOT on plain_marker, plain_extra_marker, or res_fork_plain!
    env.expect.that_int(res_with_variants.count('variants = [":_resolver_group_cpu_group_cuda"]')).equals(5)

def _test_conflict_state_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_conflict_state_rendering_impl)

# --- Variant reset ---

def _whl(name, filename):
    return {"filename": filename, "file_reference": {"key": name}}

_RESET_SETS = [["extra_app_cpu", "extra_app_gpu"]]

def _reset_lock(packages):
    repo_map = {}
    for pkg in packages.values():
        for c in pkg.get("wheel_candidates", []):
            repo_map[c["file_reference"]["key"]] = "@r//{}:wheel".format(c["file_reference"]["key"])
        if pkg.get("sdist_file"):
            repo_map[pkg["sdist_file"]["key"]] = "@r//{}:sdist".format(pkg["sdist_file"]["key"])
    return render_lock_bzl({"packages": packages}, repo_map, "ws__pkgs", reset_conflict_sets = _RESET_SETS)

def _library(res, key):
    """The rule kind and gate of a package's library target."""
    for kind in ("pycross_resettable_wheel_library(", "pycross_wheel_library("):
        marker = '{}\n        name = "{}",'.format(kind, key)
        if marker in res:
            body = res.split(marker)[1].split("\n    )")[0]
            gate = body.split("reset_gate = ")[1].split(",")[0] if "reset_gate = " in body else None
            return (kind[:-1], gate)
    return (None, None)

# buildifier: disable=unused-variable
def _test_reset_plan_impl(env, target):
    """Packages that don't depend on variants install with them reset; others don't."""
    res = _reset_lock({
        "leaf@1.0": {"wheel_candidates": [_whl("leaf_whl", "leaf-1.0-py3-none-any.whl")]},
        # Two items of one conflict set can't both be active, so this edge isn't variant-gated.
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
    env.expect.that_str(res).contains('load(":reset.bzl", "pycross_resettable_wheel_library")')
    env.expect.that_collection(_library(res, "leaf@1.0")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_collection(_library(res, "uses-leaf@1.0")).contains_exactly(["pycross_resettable_wheel_library", "None"]).in_order()
    env.expect.that_str(_library(res, "gated@1.0")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(res, "above-gated@1.0")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(res, "patched@1.0")[0]).equals("pycross_wheel_library")

    # Packages without wheels and cycle members (and what depends on them) stay.
    env.expect.that_str(_library(res, "above-no-wheel@1.0")[0]).equals("pycross_wheel_library")
    env.expect.that_str(_library(res, "above-cyc@1.0")[0]).equals("pycross_wheel_library")
    env.expect.that_bool("pycross_resettable_wheel_library(\n        name = \"_raw_cyc@1.0\"" in res).equals(False)

def _test_reset_plan(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_plan_impl)

# buildifier: disable=unused-variable
def _test_reset_gates_impl(env, target):
    """Packages that can fall back to an sdist only reset where a wheel matches."""
    res = _reset_lock({
        "one@1.0": {
            "wheel_candidates": [_whl("one_whl", "one-1.0-py3-none-any.whl")],
            "sdist_file": {"key": "one_sdist"},
        },
        "win@1.0": {
            "wheel_candidates": [
                _whl("win_whl", "win-1.0-cp312-cp312-win_amd64.whl"),
                _whl("win_whl32", "win-1.0-cp312-cp312-win32.whl"),
            ],
            "sdist_file": {"key": "win_sdist"},
        },
        # An extras proxy forwards its base package's gate.
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
            ],
        },
    })

    # A single wheel reuses its config_setting; several get a match_any group.
    env.expect.that_str(_library(res, "one@1.0")[1]).equals('":_wheel_cs_one@1.0_one_1_0_py3_none_any_whl"')
    env.expect.that_str(_library(res, "win@1.0")[1]).equals('":_reset_wheel_win@1.0"')

    # The conditional edge only needs win's gate where it applies.
    env.expect.that_str(_library(res, "top@1.0")[1]).equals('":_reset_ok_top@1.0"')
    edge = res.split('name = "_reset_edge_top@1.0_win@1.0",')[1].split(")")[0]
    env.expect.that_str(edge).contains("match_any")
    env.expect.that_str(edge).contains("_nomatch")
    env.expect.that_str(edge).contains(":_reset_wheel_win@1.0")
    env.expect.that_str(res).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')
    env.expect.that_str(_library(res, "uses-extra@1.0")[1]).equals('":_wheel_cs_one@1.0_one_1_0_py3_none_any_whl"')

def _test_reset_gates(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_gates_impl)

# buildifier: disable=unused-variable
def _test_reset_bzl_impl(env, target):
    """reset.bzl resets every variant setting and each flag once."""
    res = render_reset_bzl(["a_b"], ["@r1//_variants:x", "@r1//_variants:x", "@r2//_variants:y"])
    env.expect.that_str(res).contains('"//_lock:_pin_a_b": "",')
    env.expect.that_str(res).contains('"//_lock:_default_a_b": "",')
    env.expect.that_str(res).contains('"//_lock:_usable_a_b": "*",')
    env.expect.that_int(res.count('"@r1//_variants:x": False,')).equals(1)
    env.expect.that_str(res).contains('"@r2//_variants:y": False,')

    # Without conflict sets nothing resets.
    lock = {"packages": {"leaf@1.0": {"wheel_candidates": [_whl("leaf_whl", "leaf-1.0-py3-none-any.whl")]}}}
    plain = render_lock_bzl(lock, {"leaf_whl": "@r//leaf:wheel"}, "ws__pkgs")
    env.expect.that_bool("reset.bzl" in plain).equals(False)

def _test_reset_bzl(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_reset_bzl_impl)

def resolved_lock_renderer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_render_lock,
            _test_reset_plan,
            _test_reset_gates,
            _test_reset_bzl,
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
            _test_conflict_state_rendering,
        ],
    )
