"""Tests for override_helpers"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:override_helpers.bzl", "encode_build_system_attrs", "merge_backend_overrides")

# buildifier: disable=unused-variable
def _test_encode_build_system_attrs_impl(env, target):
    mock_tag = struct(
        copts = ["-O3"],
        linkopts = ["-lfoo"],
        native_deps = ["@bar//lib:lib"],
        config_settings = {"//:my_setting": "1"},
        tool_deps = ["pkg1", "pkg2"],
        build_env = {"MY_VAR": "val"},
        data = ["//pkg:data"],
        pre_build_hooks = ["//pkg:pre_hook"],
        post_build_hooks = ["//pkg:post_hook"],
        path_tools = ["//pkg:path_tool"],
    )
    res = encode_build_system_attrs(mock_tag)

    # We check string equality with the expected JSON encoding because we want to ensure
    # we produced exactly the correct JSON serialized strings.
    env.expect.that_dict(res).contains_exactly({
        "copts": json.encode(["-O3"]),
        "linkopts": json.encode(["-lfoo"]),
        "native_deps": json.encode(["@bar//lib:lib"]),
        "config_settings": json.encode({"//:my_setting": "1"}),
        "tool_deps": json.encode(["pkg1", "pkg2"]),
        "build_env": json.encode({"MY_VAR": "val"}),
        "data": json.encode(["//pkg:data"]),
        "pre_build_hooks": json.encode(["//pkg:pre_hook"]),
        "post_build_hooks": json.encode(["//pkg:post_hook"]),
        "path_tools": json.encode(["//pkg:path_tool"]),
    })

def _test_encode_build_system_attrs(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_encode_build_system_attrs_impl)

# ---- merge_backend_overrides tests ----

# buildifier: disable=unused-variable
def _test_merge_wildcard_only_impl(env, target):
    """Wildcard applies to all packages."""
    scope = {
        "*": {"setuptools_build": {"copts": json.encode(["-O2"])}},
    }
    result = merge_backend_overrides(scope, "numpy")
    env.expect.that_dict(result).contains_exactly({
        "setuptools_build": {"copts": json.encode(["-O2"])},
    })

def _test_merge_wildcard_only(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_wildcard_only_impl)

# buildifier: disable=unused-variable
def _test_merge_specific_only_impl(env, target):
    """Specific override with no wildcard."""
    scope = {
        "numpy": {"setuptools_build": {"native_deps": json.encode(["//openblas"])}},
    }
    result = merge_backend_overrides(scope, "numpy")
    env.expect.that_dict(result).contains_exactly({
        "setuptools_build": {"native_deps": json.encode(["//openblas"])},
    })

def _test_merge_specific_only(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_specific_only_impl)

# buildifier: disable=unused-variable
def _test_merge_no_match_impl(env, target):
    """Package not in scope and no wildcard returns empty."""
    scope = {
        "numpy": {"setuptools_build": {"copts": json.encode(["-O2"])}},
    }
    result = merge_backend_overrides(scope, "pandas")
    env.expect.that_dict(result).keys().has_size(0)

def _test_merge_no_match(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_no_match_impl)

# buildifier: disable=unused-variable
def _test_merge_wildcard_and_specific_disjoint_fields_impl(env, target):
    """Wildcard and specific with different fields: both are present."""
    scope = {
        "*": {"setuptools_build": {"copts": json.encode(["-O2"])}},
        "numpy": {"setuptools_build": {"native_deps": json.encode(["//openblas"])}},
    }
    result = merge_backend_overrides(scope, "numpy")
    env.expect.that_dict(result).contains_exactly({
        "setuptools_build": {
            "copts": json.encode(["-O2"]),
            "native_deps": json.encode(["//openblas"]),
        },
    })

def _test_merge_wildcard_and_specific_disjoint_fields(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_wildcard_and_specific_disjoint_fields_impl)

# buildifier: disable=unused-variable
def _test_merge_specific_overrides_wildcard_field_impl(env, target):
    """Specific value replaces wildcard for the same field (no list merge)."""
    scope = {
        "*": {"setuptools_build": {"copts": json.encode(["-O2"])}},
        "numpy": {"setuptools_build": {"copts": json.encode(["-O3", "-mavx2"])}},
    }
    result = merge_backend_overrides(scope, "numpy")
    env.expect.that_dict(result).contains_exactly({
        "setuptools_build": {"copts": json.encode(["-O3", "-mavx2"])},
    })

def _test_merge_specific_overrides_wildcard_field(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_specific_overrides_wildcard_field_impl)

# buildifier: disable=unused-variable
def _test_merge_unmatched_package_gets_wildcard_impl(env, target):
    """A package without a specific override still gets the wildcard."""
    scope = {
        "*": {"setuptools_build": {"copts": json.encode(["-O2"])}},
        "numpy": {"setuptools_build": {"native_deps": json.encode(["//openblas"])}},
    }
    result = merge_backend_overrides(scope, "pandas")
    env.expect.that_dict(result).contains_exactly({
        "setuptools_build": {"copts": json.encode(["-O2"])},
    })

def _test_merge_unmatched_package_gets_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_unmatched_package_gets_wildcard_impl)

# buildifier: disable=unused-variable
def _test_merge_multiple_backends_impl(env, target):
    """Wildcard and specific can span different backends."""
    scope = {
        "*": {"setuptools_build": {"copts": json.encode(["-O2"])}},
        "numpy": {"meson_build": {"native_deps": json.encode(["//openblas"])}},
    }
    result = merge_backend_overrides(scope, "numpy")

    # Should have both backends.
    env.expect.that_dict(result).keys().contains_exactly(["setuptools_build", "meson_build"])
    env.expect.that_dict(result["setuptools_build"]).contains_exactly({
        "copts": json.encode(["-O2"]),
    })
    env.expect.that_dict(result["meson_build"]).contains_exactly({
        "native_deps": json.encode(["//openblas"]),
    })

def _test_merge_multiple_backends(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_multiple_backends_impl)

# buildifier: disable=unused-variable
def _test_merge_multiple_backends_same_backend_merge_impl(env, target):
    """Wildcard and specific both configure the same backend: attrs merge."""
    scope = {
        "*": {
            "setuptools_build": {"copts": json.encode(["-O2"]), "linkopts": json.encode(["-lm"])},
        },
        "numpy": {
            "setuptools_build": {"native_deps": json.encode(["//openblas"])},
            "meson_build": {"copts": json.encode(["-O3"])},
        },
    }
    result = merge_backend_overrides(scope, "numpy")

    # setuptools_build should have wildcard copts+linkopts plus specific native_deps.
    env.expect.that_dict(result["setuptools_build"]).contains_exactly({
        "copts": json.encode(["-O2"]),
        "linkopts": json.encode(["-lm"]),
        "native_deps": json.encode(["//openblas"]),
    })

    # meson_build only from specific.
    env.expect.that_dict(result["meson_build"]).contains_exactly({
        "copts": json.encode(["-O3"]),
    })

def _test_merge_multiple_backends_same_backend_merge(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_multiple_backends_same_backend_merge_impl)

# buildifier: disable=unused-variable
def _test_merge_empty_scope_impl(env, target):
    """Empty scope returns empty dict."""
    result = merge_backend_overrides({}, "numpy")
    env.expect.that_dict(result).keys().has_size(0)

def _test_merge_empty_scope(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_empty_scope_impl)

def override_helpers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_encode_build_system_attrs,
            _test_merge_wildcard_only,
            _test_merge_specific_only,
            _test_merge_no_match,
            _test_merge_wildcard_and_specific_disjoint_fields,
            _test_merge_specific_overrides_wildcard_field,
            _test_merge_unmatched_package_gets_wildcard,
            _test_merge_multiple_backends,
            _test_merge_multiple_backends_same_backend_merge,
            _test_merge_empty_scope,
        ],
    )
