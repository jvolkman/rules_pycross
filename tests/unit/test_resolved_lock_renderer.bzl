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
    res_dict = render_lock_bzl(lock, repo_map, "my_rctx")
    res = "\n".join(res_dict.values())

    env.expect.that_bool("pycross_wheel_library(" in res).equals(True)
    env.expect.that_bool("name = \"whl\"" in res).equals(True)
    env.expect.that_bool("actual = select({" in res).equals(True)
    env.expect.that_bool("\"//_env:linux\": \"@my_repo//foo:wheel\"" in res).equals(True)

def _test_render_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_rendering_impl(env, target):
    """Verify cycle groups generate _cycles/BUILD.bazel and cycled packages use pkg_raw naming."""
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
    res_dict = render_lock_bzl(lock, repo_map, "my_rctx")

    # _cycles/BUILD.bazel should exist
    env.expect.that_bool("_cycles/BUILD.bazel" in res_dict).equals(True)

    cycles_build = res_dict["_cycles/BUILD.bazel"]

    # Should have a py_library named cycle_group_abc123
    env.expect.that_bool("name = \"cycle_group_abc123\"" in cycles_build).equals(True)

    # Should reference pkg_raw targets for both cycle members
    env.expect.that_bool("//alpha/v1.0:pkg_raw" in cycles_build).equals(True)
    env.expect.that_bool("//beta/v2.0:pkg_raw" in cycles_build).equals(True)

    # Check alpha's package BUILD — should use pkg_raw for the wheel_library name
    alpha_build = res_dict.get("alpha/v1.0/BUILD.bazel", "")
    env.expect.that_bool("name = \"pkg_raw\"" in alpha_build).equals(True)

    # Should have a wrapping py_library named "pkg" that depends on pkg_raw + cycle group
    env.expect.that_bool("name = \"pkg\"" in alpha_build).equals(True)
    env.expect.that_bool("//_cycles:cycle_group_abc123" in alpha_build).equals(True)

    # Cycled package deps should exclude same-cycle members from their dep list
    # alpha depends on beta, but beta is in the same cycle, so it should NOT appear in alpha's deps
    env.expect.that_bool("//beta/v2.0:pkg" not in alpha_build.split("pycross_wheel_library")[0]).equals(True)

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
                "extra_dependencies": {
                    "test": {
                        "common_dependencies": ["pytest@7.0"],
                    },
                    "dev": {
                        "common_dependencies": ["black@23.0"],
                        "environment_dependencies": {
                            "linux": ["mypy@1.5"],
                        },
                    },
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
    res_dict = render_lock_bzl(lock, repo_map, "my_rctx")

    mylib_build = res_dict.get("mylib/v1.0/BUILD.bazel", "")

    # Should have py_library for [test] extra
    env.expect.that_bool("name = \"[test]\"" in mylib_build).equals(True)

    # [test] deps should include pytest
    env.expect.that_bool("//pytest/v7.0:pkg" in mylib_build).equals(True)

    # Should have py_library for [dev] extra
    env.expect.that_bool("name = \"[dev]\"" in mylib_build).equals(True)

    # [dev] deps should include black (common) and mypy (linux-specific via select)
    env.expect.that_bool("//black/v23.0:pkg" in mylib_build).equals(True)
    env.expect.that_bool("//mypy/v1.5:pkg" in mylib_build).equals(True)

    # [dev] should use select for env-specific deps
    # The select should reference _env:linux
    env.expect.that_bool("select({" in mylib_build).equals(True)

    # loads py_library since we have extras
    env.expect.that_bool("py_library" in mylib_build).equals(True)

def _test_extras_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_rendering_impl)

# buildifier: disable=unused-variable
def _test_versioned_paths_impl(env, target):
    """Verify the renderer produces versioned path keys like pkg/vN/BUILD.bazel."""
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
    res_dict = render_lock_bzl(lock, {}, "my_rctx")

    # Should have versioned BUILD file paths
    env.expect.that_bool("numpy/v1.26.4/BUILD.bazel" in res_dict).equals(True)
    env.expect.that_bool("pandas/v2.1.0/BUILD.bazel" in res_dict).equals(True)

    # Check package_name and package_version in rendered content
    numpy_build = res_dict["numpy/v1.26.4/BUILD.bazel"]
    env.expect.that_bool("package_name = \"numpy\"" in numpy_build).equals(True)
    env.expect.that_bool("package_version = \"1.26.4\"" in numpy_build).equals(True)

def _test_versioned_paths(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_versioned_paths_impl)

# buildifier: disable=unused-variable
def _test_no_cycles_no_cycles_dir_impl(env, target):
    """Verify that when there are no cycles, _cycles/BUILD.bazel is not generated."""
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
    res_dict = render_lock_bzl(lock, {}, "my_rctx")
    env.expect.that_bool("_cycles/BUILD.bazel" in res_dict).equals(False)

    # a should use "pkg" not "pkg_raw"
    a_build = res_dict.get("a/v1.0/BUILD.bazel", "")
    env.expect.that_bool("name = \"pkg\"" in a_build).equals(True)
    env.expect.that_bool("pkg_raw" not in a_build).equals(True)

def _test_no_cycles_no_cycles_dir(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_cycles_no_cycles_dir_impl)

def resolved_lock_renderer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_render_lock,
            _test_cycle_group_rendering,
            _test_extras_rendering,
            _test_versioned_paths,
            _test_no_cycles_no_cycles_dir,
        ],
    )
