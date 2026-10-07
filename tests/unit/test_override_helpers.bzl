"""Tests for override_helpers"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_repo_creation.bzl", "normalize_override_name_for_testing", "validate_override_packages_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:override_helpers.bzl", "encode_build_system_attrs", "merge_backend_overrides")

# buildifier: disable=unused-variable
def _test_encode_build_system_attrs_impl(env, target):
    mock_tag = struct(
        copts = ["-O3"],
        linkopts = ["-lfoo"],
        native_deps = ["@bar//lib:lib"],
        config_settings = {"//:my_setting": "1"},
        tool_deps = {"cmake": Label("//third_party/cmake:pkg")},
        build_env = {"MY_VAR": "val"},
        data = ["//pkg:data"],
        pre_build_hooks = ["//pkg:pre_hook"],
        post_build_hooks = ["//pkg:post_hook"],
        path_tools = ["//pkg:path_tool"],
        repair_exclude_globs = ["libtorch*.so", "libc10*.so"],
    )
    res = encode_build_system_attrs(mock_tag)

    # We check string equality with the expected JSON encoding because we want to ensure
    # we produced exactly the correct JSON serialized strings.
    env.expect.that_dict(res).contains_exactly({
        "copts": json.encode(["-O3"]),
        "linkopts": json.encode(["-lfoo"]),
        "native_deps": json.encode(["@bar//lib:lib"]),
        "config_settings": json.encode({"//:my_setting": "1"}),
        "tool_deps": json.encode({"cmake": str(Label("//third_party/cmake:pkg"))}),
        "build_env": json.encode({"MY_VAR": "val"}),
        "data": json.encode(["//pkg:data"]),
        "pre_build_hooks": json.encode(["//pkg:pre_hook"]),
        "post_build_hooks": json.encode(["//pkg:post_hook"]),
        "path_tools": json.encode(["//pkg:path_tool"]),
        "repair_exclude_globs": json.encode(["libtorch*.so", "libc10*.so"]),
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

# buildifier: disable=unused-variable
def _test_merge_versioned_precedence_impl(env, target):
    """name@version beats name, which beats *; fields are layered."""
    scope = {
        "*": {"setuptools_build": {"copts": ["-O1"], "linkopts": ["-lw"], "build_env": {"W": "1"}}},
        "foo": {"setuptools_build": {"copts": ["-O2"], "linkopts": ["-ln"]}},
        "foo@2.0": {"setuptools_build": {"copts": ["-O3"]}},
    }
    result = merge_backend_overrides(scope, "foo", "2.0")
    env.expect.that_dict(result["setuptools_build"]).contains_exactly({
        "copts": ["-O3"],
        "linkopts": ["-ln"],
        "build_env": {"W": "1"},
    })

def _test_merge_versioned_precedence(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_versioned_precedence_impl)

# buildifier: disable=unused-variable
def _test_merge_versioned_only_matching_version_impl(env, target):
    """With two locked versions (a fork), a versioned override applies to that version only."""
    scope = {
        "foo": {"setuptools_build": {"copts": ["-O2"]}},
        "foo@1.0": {"setuptools_build": {"copts": ["-O0"]}},
    }
    env.expect.that_dict(merge_backend_overrides(scope, "foo", "1.0")["setuptools_build"]).contains_exactly({"copts": ["-O0"]})
    env.expect.that_dict(merge_backend_overrides(scope, "foo", "2.0")["setuptools_build"]).contains_exactly({"copts": ["-O2"]})

def _test_merge_versioned_only_matching_version(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_merge_versioned_only_matching_version_impl)

# buildifier: disable=unused-variable
def _test_normalize_override_name_impl(env, target):
    env.expect.that_str(normalize_override_name_for_testing("*", "b", "ws")).equals("*")
    env.expect.that_str(normalize_override_name_for_testing("Python_DateUtil", "b", "ws")).equals("python-dateutil")
    env.expect.that_str(normalize_override_name_for_testing("Python_DateUtil@2.9.0", "b", "ws")).equals("python-dateutil@2.9.0")

def _test_normalize_override_name(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_normalize_override_name_impl)

# ---- override package validation ----

_RESOLVED_LOCKS = {
    "pypi": {"packages": {"python-dateutil@2.9.0": {}, "six@1.16.0": {}, "six@1.17.0": {}, "requests[socks]@2.32.0": {}}},
    "pypi__build": {"packages": {"setuptools@70.0.0": {}}},
}
_MEMBERSHIPS = {"pypi": "pypi", "pypi__build": "pypi"}

# buildifier: disable=unused-variable
def _test_validate_override_packages_ok_impl(env, target):
    """Known packages (any member, normalized), wildcards and foreign workspaces pass."""
    validate_override_packages_for_testing(
        {
            "pypi": {
                "*": {"setuptools_build": {}},
                "python-dateutil": {"setuptools_build": {}},
                "requests": {"setuptools_build": {}},
                "setuptools": {"setuptools_build": {}},
                "six@1.16.0": {"setuptools_build": {}},
                "six@1.17.0": {"setuptools_build": {}},
                "setuptools@70.0.0": {"setuptools_build": {}},
            },
            # May belong to a different lock extension.
            "pdm_workspace": {"anything": {"meson_build": {}}},
        },
        _RESOLVED_LOCKS,
        _MEMBERSHIPS,
    )

def _test_validate_override_packages_ok(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_validate_override_packages_ok_impl)

def _unknown_override_package_subject_impl(ctx):  # @unused
    validate_override_packages_for_testing(
        {"pypi": {"no-such-package": {"setuptools_build": {}}}},
        _RESOLVED_LOCKS,
        _MEMBERSHIPS,
    )
    return []

_unknown_override_package_subject = rule(implementation = _unknown_override_package_subject_impl)

def _test_validate_override_packages_unknown_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("setuptools_build override for package 'no-such-package' matches no package in workspace 'pypi'"),
    )

def _test_validate_override_packages_unknown(name):
    util.helper_target(_unknown_override_package_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_validate_override_packages_unknown_impl,
        expect_failure = True,
    )

def _unknown_override_version_subject_impl(ctx):  # @unused
    validate_override_packages_for_testing(
        {"pypi": {"six@9.9.9": {"setuptools_build": {}}}},
        _RESOLVED_LOCKS,
        _MEMBERSHIPS,
    )
    return []

_unknown_override_version_subject = rule(implementation = _unknown_override_version_subject_impl)

def _test_validate_override_version_unknown_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("setuptools_build override for 'six@9.9.9' matches no locked version of 'six' in workspace 'pypi'; available versions: 1.16.0, 1.17.0"),
    )

def _test_validate_override_version_unknown(name):
    util.helper_target(_unknown_override_version_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_validate_override_version_unknown_impl,
        expect_failure = True,
    )

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
            _test_validate_override_packages_ok,
            _test_validate_override_packages_unknown,
            _test_merge_versioned_precedence,
            _test_merge_versioned_only_matching_version,
            _test_normalize_override_name,
            _test_validate_override_version_unknown,
        ],
    )
