"""Tests for the backends registration extension."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:backends.bzl", "collect_registrations_for_testing")

def _tag(name, rule_bzl, pyproject_backends = [], default = False):
    return struct(
        name = name,
        rule_bzl = rule_bzl,
        pyproject_backends = pyproject_backends,
        tool_packages = [],
        default = default,
        override_json = None,
        sdist_hook_bzl = None,
        sdist_hook_fn = "",
        package_repo_hook_bzl = None,
        package_repo_hook_fn = "",
    )

def _module(name, tags, is_root = False):
    return struct(name = name, is_root = is_root, tags = struct(register = tags))

# The built-in registrations as made by rules_pycross itself (a non-root module).
_BUILTIN = _module("rules_pycross", [
    _tag("meson_build", "@rules_pycross//pycross/backends:meson.bzl", ["mesonpy"]),
    _tag("pep517_build", "@rules_pycross//pycross/backends:pep517.bzl", ["hatchling.build"], default = True),
])

# buildifier: disable=unused-variable
def _test_root_overrides_are_silent_impl(env, target):
    root = _module("my_project", [
        _tag("meson_build", "//:my_meson.bzl"),
        _tag("my_build", "//:my_build.bzl", ["hatchling.build"], default = True),
    ], is_root = True)
    warnings = []
    res = collect_registrations_for_testing([root, _BUILTIN], warn = warnings.append)

    env.expect.that_collection(warnings).contains_exactly([])
    env.expect.that_str(json.decode(res.backend_configs["meson_build"])["rule_bzl"]).equals("//:my_meson.bzl")
    env.expect.that_str(res.backend_to_rule["hatchling.build"]).equals("my_build")
    env.expect.that_str(res.default_backend).equals("my_build")
    env.expect.that_bool("pep517_build" in res.backend_configs).equals(True)

def _test_root_overrides_are_silent(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_root_overrides_are_silent_impl)

# buildifier: disable=unused-variable
def _test_non_root_duplicates_warn_impl(env, target):
    other = _module("other_module", [
        _tag("meson_build", "@other_module//:meson.bzl"),
        _tag("other_build", "@other_module//:other.bzl", ["mesonpy"], default = True),
    ])
    warnings = []
    res = collect_registrations_for_testing([_BUILTIN, other], warn = warnings.append)

    env.expect.that_collection(warnings).has_size(3)
    env.expect.that_str(json.decode(res.backend_configs["meson_build"])["rule_bzl"]).equals("@rules_pycross//pycross/backends:meson.bzl")
    env.expect.that_str(res.backend_to_rule["mesonpy"]).equals("meson_build")
    env.expect.that_str(res.default_backend).equals("pep517_build")

def _test_non_root_duplicates_warn(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_non_root_duplicates_warn_impl)

def backends_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_root_overrides_are_silent,
            _test_non_root_duplicates_warn,
        ],
    )
