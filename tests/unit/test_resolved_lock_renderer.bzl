"""Tests for resolved_lock_renderer"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:resolved_lock_renderer.bzl", "render_lock_bzl")

# buildifier: disable=unused-variable
def _test_render_lock_impl(env, target):
    lock = {
        "environments": {
            "linux": {
                "environment_label": "@platforms//os:linux",
                "config_setting_label": "//:linux_env",
            },
        },
        "packages": {
            "foo@1.0": {
                "environment_files": {
                    "linux": {"key": "foo_wheel"},
                    "mac": {"key": "foo_wheel_mac"},
                },
            },
        },
    }
    repo_map = {"foo_wheel": "@my_repo//foo:wheel", "foo_wheel_mac": "@my_repo//foo:mac_wheel"}
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    env.expect.that_bool("pycross_wheel_library(" in res).equals(True)
    env.expect.that_bool("_wheel_foo@1.0" in res).equals(True)
    env.expect.that_bool("select({" in res).equals(True)
    env.expect.that_bool('":linux": "@my_repo//foo:wheel"' in res).equals(True)

def _test_render_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_rendering_impl(env, target):
    """Verify cycle groups generate cycle py_libraries and cycled packages use _raw naming."""
    lock = {
        "environments": {
            "linux": {
                "environment_label": "@platforms//os:linux",
                "config_setting_label": "//:linux_env",
            },
        },
        "cycle_groups": {
            "cycle_group_abc123": ["alpha@1.0", "beta@2.0"],
        },
        "packages": {
            "alpha@1.0": {
                "cycle_group": "cycle_group_abc123",
                "common_dependencies": ["beta@2.0"],
                "environment_files": {
                    "linux": {"key": "alpha_wheel"},
                },
            },
            "beta@2.0": {
                "cycle_group": "cycle_group_abc123",
                "common_dependencies": ["alpha@1.0"],
                "environment_files": {
                    "linux": {"key": "beta_wheel"},
                },
            },
        },
    }
    repo_map = {
        "alpha_wheel": "@repo//alpha:wheel",
        "beta_wheel": "@repo//beta:wheel",
    }
    res = render_lock_bzl(lock, repo_map, "my_rctx")

    # Should have a py_library named _cycle_cycle_group_abc123
    env.expect.that_bool('"_cycle_cycle_group_abc123"' in res).equals(True)

    # Should reference _raw_ targets for both cycle members
    env.expect.that_bool('"_raw_alpha@1.0"' in res).equals(True)
    env.expect.that_bool('"_raw_beta@2.0"' in res).equals(True)

    # alpha's pycross_wheel_library should use _raw_ name
    env.expect.that_bool('"_raw_alpha@1.0"' in res).equals(True)

    # Should have a wrapping py_library named "alpha@1.0" that depends on _raw + cycle group
    env.expect.that_bool('"alpha@1.0"' in res).equals(True)
    env.expect.that_bool('"_cycle_cycle_group_abc123"' in res).equals(True)

    # Cycled package deps should exclude same-cycle members
    # Split at the pycross_wheel_library for alpha to check its deps
    # alpha depends on beta, but beta is in the same cycle, so beta should NOT appear in alpha's deps list
    alpha_section = res.split('name = "_raw_alpha@1.0"')[0].rsplit("_alpha_1_0_deps", 1)[-1] if "_alpha_1_0_deps" in res else ""
    env.expect.that_bool('"beta@2.0"' not in alpha_section).equals(True)

def _test_cycle_group_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_group_rendering_impl)

# buildifier: disable=unused-variable
def _test_extras_rendering_impl(env, target):
    """Verify extra_dependencies generate py_library targets named [extra_name]."""
    lock = {
        "environments": {
            "linux": {
                "environment_label": "@platforms//os:linux",
                "config_setting_label": "//:linux_env",
            },
        },
        "packages": {
            "mylib@1.0": {
                "environment_files": {
                    "linux": {"key": "mylib_wheel"},
                },
            },
            "mylib[test]@1.0": {
                "environment_files": {},
                "common_dependencies": ["pytest@7.0"],
            },
            "mylib[dev]@1.0": {
                "environment_files": {},
                "common_dependencies": ["black@23.0"],
                "environment_dependencies": {
                    "linux": ["mypy@1.5"],
                },
            },
            "pytest@7.0": {
                "environment_files": {
                    "linux": {"key": "pytest_wheel"},
                },
            },
            "black@23.0": {
                "environment_files": {
                    "linux": {"key": "black_wheel"},
                },
            },
            "mypy@1.5": {
                "environment_files": {
                    "linux": {"key": "mypy_wheel"},
                },
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

    # [dev] deps should include black (common) and mypy (linux-specific via select)
    env.expect.that_bool('":black@23.0"' in res).equals(True)
    env.expect.that_bool('":mypy@1.5"' in res).equals(True)

    # [dev] should use select for env-specific deps
    env.expect.that_bool("select({" in res).equals(True)

    # loads py_library since we have extras
    env.expect.that_bool("py_library" in res).equals(True)

def _test_extras_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_rendering_impl)

# buildifier: disable=unused-variable
def _test_lock_bzl_format_impl(env, target):
    """Verify the renderer produces a single lock.bzl string with targets() function."""
    lock = {
        "environments": {},
        "packages": {
            "numpy@1.26.4": {
                "environment_files": {},
            },
            "pandas@2.1.0": {
                "environment_files": {},
            },
        },
    }
    res = render_lock_bzl(lock, {}, "my_rctx")

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

def _test_lock_bzl_format(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_lock_bzl_format_impl)

# buildifier: disable=unused-variable
def _test_no_cycles_no_cycle_targets_impl(env, target):
    """Verify that when there are no cycles, no _cycle_ targets are generated."""
    lock = {
        "environments": {},
        "packages": {
            "a@1.0": {
                "common_dependencies": ["b@2.0"],
                "environment_files": {},
            },
            "b@2.0": {
                "environment_files": {},
            },
        },
    }
    res = render_lock_bzl(lock, {}, "my_rctx")
    env.expect.that_bool("_cycle_" not in res).equals(True)

    # a should use "a@1.0" not "_raw_"
    env.expect.that_bool('name = "a@1.0"' in res).equals(True)
    env.expect.that_bool("_raw_" not in res).equals(True)

def _test_no_cycles_no_cycle_targets(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_cycles_no_cycle_targets_impl)

def resolved_lock_renderer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_render_lock,
            _test_cycle_group_rendering,
            _test_extras_rendering,
            _test_lock_bzl_format,
            _test_no_cycles_no_cycle_targets,
        ],
    )
