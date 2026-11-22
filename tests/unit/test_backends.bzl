"""Tests for the backends registration extension."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:backend_registry_repo.bzl", "render_hook_dispatch_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:backends.bzl", "collect_registrations_for_testing")

def _tag(
        name,
        rule_bzl,
        pyproject_backends = [],
        default = False,
        override_json = None,
        sdist_hook_bzl = None,
        sdist_hook_fn = ""):
    return struct(
        name = name,
        rule_bzl = rule_bzl,
        pyproject_backends = pyproject_backends,
        tool_packages = [],
        default = default,
        override_json = override_json,
        sdist_hook_bzl = sdist_hook_bzl,
        sdist_hook_fn = sdist_hook_fn,
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

# buildifier: disable=unused-variable
def _test_duplicate_registration_does_not_leak_override_json_impl(env, target):
    """Ignored duplicate registrations must not leak override_json; root re-registrations replace cleanly."""
    root = _module("my_project", [
        _tag("meson_build", "//:first_meson.bzl", ["old_meson"], default = True, override_json = "//:first_overrides.json", sdist_hook_bzl = "//:first_hook.bzl", sdist_hook_fn = "first_fn"),
        _tag("meson_build", "//:second_meson.bzl", ["new_meson"], default = False, override_json = None),
        _tag("extra_build", "//:extra.bzl", override_json = "@shared//:overrides.json"),
        _tag("extra2_build", "//:extra2.bzl", override_json = "@shared//:overrides.json"),
    ], is_root = True)
    dep = _module("rules_pycross", [
        _tag("meson_build", "@rules_pycross//pycross/backends:meson.bzl", ["mesonpy"], override_json = "@meson_overrides//:overrides.json"),
        _tag("pep517_build", "@rules_pycross//pycross/backends:pep517.bzl", ["hatchling.build"], default = True, override_json = "@pep517_overrides//:overrides.json"),
    ])
    other = _module("other_module", [
        _tag("pep517_build", "@other//:pep517.bzl", override_json = "@other_overrides//:overrides.json"),
    ])
    warnings = []
    res = collect_registrations_for_testing([root, dep, other], warn = warnings.append)

    env.expect.that_collection(warnings).has_size(1)

    # Root re-registered meson_build without override_json, so it inherits dep's
    # @meson_overrides//:overrides.json (while dropping root's replaced first_overrides.json).
    # Non-root duplicate pep517_build from other_module must NOT leak @other_overrides//:overrides.json.
    env.expect.that_collection(res.override_files).contains_exactly([
        "@meson_overrides//:overrides.json",
        "@shared//:overrides.json",
        "@pep517_overrides//:overrides.json",
    ]).in_order()
    env.expect.that_bool("meson_build" in res.sdist_hook_bzl).equals(False)
    env.expect.that_bool("meson_build" in res.sdist_hook_fn).equals(False)
    env.expect.that_bool("old_meson" in res.backend_to_rule).equals(False)
    env.expect.that_str(res.backend_to_rule["new_meson"]).equals("meson_build")
    env.expect.that_str(res.default_backend).equals("pep517_build")

def _test_duplicate_registration_does_not_leak_override_json(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_duplicate_registration_does_not_leak_override_json_impl)

# buildifier: disable=unused-variable
def _test_root_reregistration_override_json_inheritance_impl(env, target):
    """Root re-registration inherits built-in override_json when omitted, or replaces it when set."""
    root = _module("my_project", [
        _tag("setuptools_build", "//:custom_setuptools.bzl", ["setuptools.build_meta"]),
        _tag("cmake_build", "//:custom_cmake.bzl", ["scikit_build_core.build"], override_json = "//:custom_cmake_overrides.json"),
    ], is_root = True)
    dep = _module("rules_pycross", [
        _tag("setuptools_build", "@rules_pycross//pycross/backends:setuptools.bzl", ["setuptools.build_meta"], override_json = "@setuptools_overrides//:overrides.json"),
        _tag("cmake_build", "@rules_pycross//pycross/backends:cmake.bzl", ["scikit_build_core.build"], override_json = "@cmake_overrides//:overrides.json"),
        _tag("pep517_build", "@rules_pycross//pycross/backends:pep517.bzl", default = True),
    ])
    other = _module("other_module", [
        _tag("setuptools_build", "@other//:setuptools.bzl", override_json = "@other_setuptools//:overrides.json"),
    ])
    warnings = []
    res = collect_registrations_for_testing([root, dep, other], warn = warnings.append)

    env.expect.that_collection(warnings).contains_exactly([])
    env.expect.that_collection(res.override_files).contains_exactly([
        "@setuptools_overrides//:overrides.json",
        "//:custom_cmake_overrides.json",
    ]).in_order()

def _test_root_reregistration_override_json_inheritance(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_root_reregistration_override_json_inheritance_impl)

# buildifier: disable=unused-variable
def _test_render_hook_dispatch_suffix_replacement_impl(env, target):
    """Default hook names strip only a trailing '_build' suffix and append the hook suffix."""
    rendered = render_hook_dispatch_for_testing(
        "sdist repo rule",
        "sdist hook",
        "SDIST_HOOKS",
        {
            "maturin_build": "@m//:hook.bzl",
            "my_build_tool_build": "@t//:hook.bzl",
            "my_build_tool": "@t2//:hook.bzl",
            "custom_backend": "@c//:hook.bzl",
            "explicit_build": "@e//:hook.bzl",
        },
        {
            "explicit_build": "custom_fn_name",
            "custom_backend": "",
        },
        "_sdist_hook",
        ["maturin_build", "my_build_tool_build", "my_build_tool", "custom_backend", "explicit_build"],
    )
    env.expect.that_str(rendered).contains('load("@m//:hook.bzl", _sdist_hook_maturin_build = "maturin_sdist_hook")')
    env.expect.that_str(rendered).contains('load("@t//:hook.bzl", _sdist_hook_my_build_tool_build = "my_build_tool_sdist_hook")')
    env.expect.that_str(rendered).contains('load("@t2//:hook.bzl", _sdist_hook_my_build_tool = "my_build_tool_sdist_hook")')
    env.expect.that_str(rendered).contains('load("@c//:hook.bzl", _sdist_hook_custom_backend = "custom_backend_sdist_hook")')
    env.expect.that_str(rendered).contains('load("@e//:hook.bzl", _sdist_hook_explicit_build = "custom_fn_name")')

def _test_render_hook_dispatch_suffix_replacement(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_hook_dispatch_suffix_replacement_impl)

def backends_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_root_overrides_are_silent,
            _test_non_root_duplicates_warn,
            _test_duplicate_registration_does_not_leak_override_json,
            _test_root_reregistration_override_json_inheritance,
            _test_render_hook_dispatch_suffix_replacement,
        ],
    )
