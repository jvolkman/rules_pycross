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
    env.expect.that_bool("name = \"_wheel_foo@1.0\"" in res).equals(True)
    env.expect.that_bool("actual = select({" in res).equals(True)
    env.expect.that_bool("\":_env_linux\": \"@my_repo//foo:wheel\"" in res).equals(True)

def _test_render_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_impl)

def resolved_lock_renderer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_render_lock,
        ],
    )
