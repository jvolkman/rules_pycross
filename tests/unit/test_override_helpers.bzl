"""Tests for override_helpers"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:format_extension.bzl", "canonicalize_package_tag_name_for_testing", "normalize_flag_for_testing", "normalize_settings_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_repo_creation.bzl", "compute_variant_pins_for_testing", "normalize_override_name_for_testing", "validate_override_packages_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:override_helpers.bzl", "canonicalize_override_key", "collect_module_overrides_for_testing", "encode_build_system_attrs", "merge_backend_overrides")

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
    for bad in ("", "@1.0", "foo@", "*@1.0", "foo[extra]", "foo@1.0~"):
        env.expect.that_bool(canonicalize_override_key(bad) == None).equals(True)

def _test_normalize_override_name(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_normalize_override_name_impl)

def _invalid_override_name_subject_impl(ctx):  # @unused
    normalize_override_name_for_testing("foo@", "setuptools_build", "ws")
    return []

_invalid_override_name_subject = rule(implementation = _invalid_override_name_subject_impl)

def _test_normalize_override_name_invalid_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("setuptools_build override 'foo@' (workspace 'ws'): expected a package name, 'name@version', or '*'"),
    )

def _test_normalize_override_name_invalid_fails(name):
    util.helper_target(_invalid_override_name_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_normalize_override_name_invalid_fails_impl,
        expect_failure = True,
    )

# ---- override package validation ----

_RESOLVED_LOCKS = {
    "pypi": {"packages": {"python-dateutil@2.9.0": {}, "six@1.16.0": {}, "six@1.17.0": {}, "requests[socks]@2.32.0": {}}},
    "pypi__build": {"packages": {"setuptools@70.0.0": {}}},
}
_WORKSPACES = {
    "pypi": struct(repos = [struct(name = "pypi"), struct(name = "pypi__build")]),
}

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
        _WORKSPACES,
        _RESOLVED_LOCKS,
    )

def _test_validate_override_packages_ok(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_validate_override_packages_ok_impl)

def _unknown_override_package_subject_impl(ctx):  # @unused
    validate_override_packages_for_testing(
        {"pypi": {"no-such-package": {"setuptools_build": {}}}},
        _WORKSPACES,
        _RESOLVED_LOCKS,
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
        _WORKSPACES,
        _RESOLVED_LOCKS,
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

# buildifier: disable=unused-variable
def _test_normalize_flags_impl(env, target):
    """Repo flags: bare names map to command_line_option; root-relative labels become canonical."""
    n = normalize_flag_for_testing
    env.expect.that_str(n("--//pkg:flag=1", True)).equals("--@@//pkg:flag=1")
    env.expect.that_str(n("--:flag", True)).equals("--@@//:flag")
    env.expect.that_str(n("--//pkg:flag=1", False)).equals("--//pkg:flag=1")
    env.expect.that_str(n("--:flag", False)).equals("--:flag")
    env.expect.that_str(n("--@repo//_variants:x=True", True)).equals("--@repo//_variants:x=True")
    env.expect.that_str(n("--@repo//_variants=extra_a", True)).equals("--@repo//_variants:_variants=extra_a")
    env.expect.that_str(n("--//pkg/sub=1", True)).equals("--@@//pkg/sub:sub=1")
    env.expect.that_str(n("--@@//pkg:flag", True)).equals("--@@//pkg:flag")
    env.expect.that_str(n("--//command_line_option:copt=-O2", True)).equals("--//command_line_option:copt=-O2")
    env.expect.that_str(n("--compilation_mode=opt", True)).equals("--//command_line_option:compilation_mode=opt")
    env.expect.that_str(n("--copt=-Wl,-rpath,/x", False)).equals("--//command_line_option:copt=-Wl,-rpath,/x")

def _test_normalize_flags(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_normalize_flags_impl)

def _invalid_flag_subject_impl(ctx):  # @unused
    normalize_flag_for_testing("compilation_mode=opt", True)
    return []

_invalid_flag_subject = rule(implementation = _invalid_flag_subject_impl)

def _test_normalize_flag_requires_dashes_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Invalid repo flag \"compilation_mode=opt\": expected '--<flag>[=<value>]'"),
    )

def _test_normalize_flag_requires_dashes(name):
    util.helper_target(_invalid_flag_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_normalize_flag_requires_dashes_impl,
        expect_failure = True,
    )

def _platforms_flag_subject_impl(ctx):  # @unused
    normalize_flag_for_testing("--platforms=//:p", True)
    return []

_platforms_flag_subject = rule(implementation = _platforms_flag_subject_impl)

def _test_normalize_flag_rejects_platforms_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("use 'platform' or 'constraint_values' instead"),
    )

def _test_normalize_flag_rejects_platforms(name):
    util.helper_target(_platforms_flag_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_normalize_flag_rejects_platforms_impl,
        expect_failure = True,
    )

# buildifier: disable=unused-variable
def _test_normalize_settings_impl(env, target):
    """settings keys are stringified to canonical labels."""
    res = normalize_settings_for_testing({Label("//pkg:flag"): "a,b"}, ["--@@//other:flag=1"])
    env.expect.that_dict(res).contains_exactly({str(Label("//pkg:flag")): "a,b"})

def _test_normalize_settings(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_normalize_settings_impl)

def _cmdline_setting_subject_impl(ctx):  # @unused
    normalize_settings_for_testing({Label("//command_line_option:copt"): "-O2"}, [])
    return []

_cmdline_setting_subject = rule(implementation = _cmdline_setting_subject_impl)

def _test_normalize_settings_rejects_builtin_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("is a built-in option; use flags = [\"--copt=...\"] instead"),
    )

def _test_normalize_settings_rejects_builtin(name):
    util.helper_target(_cmdline_setting_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_normalize_settings_rejects_builtin_impl,
        expect_failure = True,
    )

def _duplicate_setting_subject_impl(ctx):  # @unused
    normalize_settings_for_testing(
        {Label("//pkg:flag"): "1"},
        [normalize_flag_for_testing("--//pkg:flag=2", True)],
    )
    return []

_duplicate_setting_subject = rule(implementation = _duplicate_setting_subject_impl)

def _test_normalize_settings_rejects_duplicate_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("is set in both flags and settings"),
    )

def _test_normalize_settings_rejects_duplicate(name):
    util.helper_target(_duplicate_setting_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_normalize_settings_rejects_duplicate_impl,
        expect_failure = True,
    )

# buildifier: disable=unused-variable
def _test_compute_variant_pins_impl(env, target):
    variants = [{
        "items": [
            {"package": "app-a", "kind": "group", "name": "test", "flags": ["group_test", "group_app-a_test"]},
            {"package": "app-b", "kind": "group", "name": "test", "flags": ["group_test", "group_app-b_test"]},
        ],
    }]
    locks = {
        "lock_a_test": {"variants": [{"items": [variants[0]["items"][0], dict(variants[0]["items"][1], flags = [])]}]},
        "lock_all": {"variants": variants},
    }
    set_suffix = "group_app-a_test_group_app-b_test"

    # Apparent label, flag without a value.
    env.expect.that_dict(compute_variant_pins_for_testing("lock_a_test", ["--@lock_a_test//_variants:group_test"], {}, locks)).contains_exactly({set_suffix: "group_app-a_test"})

    # Canonical label from `settings`, and a sibling repo's per-project flag.
    env.expect.that_dict(compute_variant_pins_for_testing("x", [], {"@@rules_pycross++uv+lock_all//_variants:group_app-b_test": "True"}, locks)).contains_exactly({set_suffix: "group_app-b_test"})

    # The last value for a flag wins, as in the transition.
    env.expect.that_dict(compute_variant_pins_for_testing("x", ["--@lock_all//_variants:group_app-a_test", "--@lock_all//_variants:group_app-a_test=False"], {}, locks)).contains_exactly({})

    # `=False` and unrelated flags select nothing.
    env.expect.that_dict(compute_variant_pins_for_testing("x", ["--@lock_all//_variants:group_test=False", "--compilation_mode=opt", "--//:foo"], {}, locks)).contains_exactly({})

    # Per-repo string_flag (`//_variants` shorthand and canonical `//_variants:_variants`), including comma-separated multi-set values.
    extra_set = {
        "items": [
            {"package": "app-a", "kind": "extra", "name": "cpu", "flags": ["extra_cpu"]},
            {"package": "app-a", "kind": "extra", "name": "gpu", "flags": ["extra_gpu"]},
        ],
    }
    multi_locks = {"lock_all": {"variants": variants + [extra_set]}}
    extra_suffix = "extra_app-a_cpu_extra_app-a_gpu"
    env.expect.that_dict(
        compute_variant_pins_for_testing("x", ["--@lock_all//_variants=group_app-a_test, extra_cpu"], {}, multi_locks),
    ).contains_exactly({set_suffix: "group_app-a_test", extra_suffix: "extra_app-a_cpu"})
    env.expect.that_dict(
        compute_variant_pins_for_testing("x", [], {"@@rules_pycross++uv+lock_all//_variants:_variants": "extra_gpu"}, multi_locks),
    ).contains_exactly({extra_suffix: "extra_app-a_gpu"})
    env.expect.that_dict(
        compute_variant_pins_for_testing("x", ["--@lock_all//_variants=extra_cpu", "--@lock_all//_variants="], {}, multi_locks),
    ).contains_exactly({})

    # Shorthand, explicit `:_variants`, and canonical spellings deduplicate as the same setting.
    env.expect.that_dict(
        compute_variant_pins_for_testing("x", ["--@lock_all//_variants:_variants=extra_cpu", "--@lock_all//_variants=extra_gpu"], {}, multi_locks),
    ).contains_exactly({extra_suffix: "extra_app-a_gpu"})
    env.expect.that_dict(
        compute_variant_pins_for_testing("x", ["--@lock_all//_variants=extra_cpu"], {"@@rules_pycross++uv+lock_all//_variants:_variants": ""}, multi_locks),
    ).contains_exactly({})

def _test_compute_variant_pins(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_compute_variant_pins_impl)

def _unknown_string_variant_pin_subject_impl(ctx):  # @unused
    locks = {
        "pypi": {
            "variants": [{
                "items": [
                    {"package": "app", "kind": "extra", "name": "cpu", "flags": ["extra_cpu"]},
                    {"package": "app", "kind": "extra", "name": "gpu", "flags": ["extra_gpu"]},
                ],
            }],
        },
    }
    compute_variant_pins_for_testing("pypi", ["--@pypi//_variants=extra_typo"], {}, locks)
    return []

_unknown_string_variant_pin_subject = rule(implementation = _unknown_string_variant_pin_subject_impl)

def _test_compute_variant_pins_unknown_string_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("selects unknown variant 'extra_typo'"),
    )

def _test_compute_variant_pins_unknown_string_fails(name):
    util.helper_target(_unknown_string_variant_pin_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_compute_variant_pins_unknown_string_fails_impl,
        expect_failure = True,
    )

# buildifier: disable=unused-variable
def _test_collect_module_overrides_root_wins_impl(env, target):
    """Root module (first in module_ctx.modules) overrides transitive dependency modules."""
    root_mod = struct(
        name = "root",
        tags = struct(override = [
            struct(workspace = "uv", name = "pyyaml", copts = ["-O3"]),
        ]),
    )
    dep_mod = struct(
        name = "dep",
        tags = struct(override = [
            struct(workspace = "uv", name = "PyYAML", copts = ["-O0"]),
            struct(workspace = "uv", name = "other", copts = ["-O1"]),
        ]),
    )
    res = collect_module_overrides_for_testing([root_mod, dep_mod], "setuptools_build")
    env.expect.that_str(res["uv"]["pyyaml"]["backend_attrs"]["copts"]).equals(json.encode(["-O3"]))
    env.expect.that_str(res["uv"]["other"]["backend_attrs"]["copts"]).equals(json.encode(["-O1"]))

    # Package tag name canonicalization handles case, underscores, extras, versions, and wildcard.
    env.expect.that_str(canonicalize_package_tag_name_for_testing("*")).equals("*")
    env.expect.that_str(canonicalize_package_tag_name_for_testing("PyYAML")).equals("pyyaml")
    env.expect.that_str(canonicalize_package_tag_name_for_testing("Foo_Bar[My_Extra]@1.0")).equals("foo-bar[my-extra]@1.0")
    env.expect.that_str(canonicalize_package_tag_name_for_testing("Foo_Bar[My_Extra]@1.0~abcd1234")).equals("foo-bar[my-extra]@1.0~abcd1234")

    # Main-repo @//pkg:flag does NOT falsely collide with external @rules_python//pkg:flag.
    main_flag = [normalize_flag_for_testing("--@//python/config_settings:python_version=3.12", True)]
    non_dup = normalize_settings_for_testing({Label("@rules_python//python/config_settings:python_version"): "3.13"}, main_flag)
    env.expect.that_int(len(non_dup)).equals(1)

def _test_collect_module_overrides_root_wins(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_collect_module_overrides_root_wins_impl)

def _dup_module_override_subject_impl(_ctx):
    mod = struct(
        name = "root",
        tags = struct(override = [
            struct(workspace = "uv", name = "PyYAML", copts = ["-O2"]),
            struct(workspace = "uv", name = "pyyaml", copts = ["-O3"]),
        ]),
    )
    collect_module_overrides_for_testing([mod], "setuptools_build")
    return []

_dup_module_override_subject = rule(implementation = _dup_module_override_subject_impl)

def _test_collect_module_overrides_same_module_dup_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Duplicate setuptools_build override for package 'pyyaml'"),
    )

def _test_collect_module_overrides_same_module_dup_fails(name):
    util.helper_target(_dup_module_override_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        expect_failure = True,
        impl = _test_collect_module_overrides_same_module_dup_fails_impl,
    )

def _canonical_dup_setting_subject_impl(_ctx):
    flags = [normalize_flag_for_testing("--@rules_python//python/config_settings:python_version=3.12", True)]
    normalize_settings_for_testing({Label("@rules_python//python/config_settings:python_version"): "3.13"}, flags)
    return []

_canonical_dup_setting_subject = rule(implementation = _canonical_dup_setting_subject_impl)

def _test_normalize_settings_rejects_apparent_vs_canonical_dup_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("set in both flags and settings"),
    )

def _test_normalize_settings_rejects_apparent_vs_canonical_dup(name):
    util.helper_target(_canonical_dup_setting_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        expect_failure = True,
        impl = _test_normalize_settings_rejects_apparent_vs_canonical_dup_impl,
    )

def _test_encode_custom_backend_attrs_impl(env, _target):
    lbl = Label("//tests/unit:BUILD.bazel")
    tag = struct(
        name = "demo",
        workspace = "pypi",
        copts = ["-O2"],
        custom_str = "hello",
        custom_bool = True,
        custom_int = 7,
        custom_label = lbl,
        custom_label_list = [lbl],
        custom_label_dict = {"k": lbl},
        custom_label_keyed_dict = {lbl: "val"},
        custom_string_list_dict = {"opt": ["a", "b"]},
        empty_list = [],
        falsy_bool = False,
        zero_int = 0,
    )
    encoded = encode_build_system_attrs(tag)
    env.expect.that_bool("name" not in encoded).equals(True)
    env.expect.that_bool("workspace" not in encoded).equals(True)
    env.expect.that_bool("empty_list" not in encoded).equals(True)
    env.expect.that_bool("falsy_bool" not in encoded).equals(True)
    env.expect.that_bool("zero_int" not in encoded).equals(True)
    env.expect.that_str(json.decode(encoded["custom_str"])).equals("hello")
    env.expect.that_bool(json.decode(encoded["custom_bool"])).equals(True)
    env.expect.that_int(json.decode(encoded["custom_int"])).equals(7)
    env.expect.that_str(json.decode(encoded["custom_label"])).contains("//tests/unit:BUILD.bazel")
    env.expect.that_int(len(json.decode(encoded["custom_label_list"]))).equals(1)
    env.expect.that_str(json.decode(encoded["custom_label_dict"])["k"]).contains("//tests/unit:BUILD.bazel")
    env.expect.that_str(json.decode(encoded["custom_label_keyed_dict"])[str(lbl)]).equals("val")
    env.expect.that_collection(json.decode(encoded["custom_string_list_dict"])["opt"]).contains_exactly(["a", "b"])

def _test_encode_custom_backend_attrs(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_encode_custom_backend_attrs_impl)

def override_helpers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_compute_variant_pins,
            _test_compute_variant_pins_unknown_string_fails,
            _test_encode_build_system_attrs,
            _test_encode_custom_backend_attrs,
            _test_collect_module_overrides_root_wins,
            _test_collect_module_overrides_same_module_dup_fails,
            _test_normalize_settings_rejects_apparent_vs_canonical_dup,
            _test_normalize_flags,
            _test_normalize_flag_requires_dashes,
            _test_normalize_flag_rejects_platforms,
            _test_normalize_settings,
            _test_normalize_settings_rejects_builtin,
            _test_normalize_settings_rejects_duplicate,
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
            _test_normalize_override_name_invalid_fails,
            _test_validate_override_version_unknown,
        ],
    )
