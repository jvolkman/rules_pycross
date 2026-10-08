"""Tests for package(build_mode = ...) merging and sdist-build gating."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:format_extension.bzl", "tag_to_annotation_data_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_repo_creation.bzl", "sdist_builds_disallowed_for_testing")

def _pkg_tag(**kwargs):
    """A normalized package tag struct with every field unset unless overridden."""
    fields = dict(
        build_mode = "",
        extra_build_tools = [],
        build_tools_repo = "",
        build_target = None,
        ignore_dependencies = [],
        extra_dependencies = [],
        install_exclude_globs = [],
        post_install_patches = [],
        pre_build_patches = [],
        site_hooks = [],
        build_backend = None,
        site_paths = [],
        bin_paths = [],
        data_paths = [],
        include_paths = [],
        wheel_library_tags = [],
    )
    fields.update(kwargs)
    return struct(**fields)

def _subject(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])

# buildifier: disable=unused-variable
def _test_default_is_auto_impl(env, target):
    ann = tag_to_annotation_data_for_testing(_pkg_tag())
    env.expect.that_str(ann["build_mode"]).equals("auto")

def _test_default_is_auto(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_default_is_auto_impl)

# buildifier: disable=unused-variable
def _test_specific_inherits_wildcard_impl(env, target):
    # A specific entry that only sets another field inherits build_mode from "*".
    ann = tag_to_annotation_data_for_testing(
        _pkg_tag(site_hooks = ["import foo"]),
        _pkg_tag(build_mode = "always"),
    )
    env.expect.that_str(ann["build_mode"]).equals("always")
    env.expect.that_collection(ann["site_hooks"]).contains_exactly(["import foo"])

def _test_specific_inherits_wildcard(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_specific_inherits_wildcard_impl)

# buildifier: disable=unused-variable
def _test_specific_auto_opts_out_impl(env, target):
    ann = tag_to_annotation_data_for_testing(
        _pkg_tag(build_mode = "auto"),
        _pkg_tag(build_mode = "never"),
    )
    env.expect.that_str(ann["build_mode"]).equals("auto")

def _test_specific_auto_opts_out(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_specific_auto_opts_out_impl)

# buildifier: disable=unused-variable
def _test_never_disallows_sdist_impl(env, target):
    env.expect.that_bool(sdist_builds_disallowed_for_testing({"build_mode": "never"})).equals(True)
    env.expect.that_bool(sdist_builds_disallowed_for_testing({"build_mode": "auto"})).equals(False)
    env.expect.that_bool(sdist_builds_disallowed_for_testing({"build_mode": "always"})).equals(False)

def _test_never_disallows_sdist(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_never_disallows_sdist_impl)

# buildifier: disable=unused-variable
def _test_never_build_target_exempt_impl(env, target):
    pkg = {"build_mode": "never", "build_target": "@@//pkg:wheel"}
    env.expect.that_bool(sdist_builds_disallowed_for_testing(pkg)).equals(False)

def _test_never_build_target_exempt(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_never_build_target_exempt_impl)

def build_mode_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_default_is_auto,
            _test_specific_inherits_wildcard,
            _test_specific_auto_opts_out,
            _test_never_disallows_sdist,
            _test_never_build_target_exempt,
        ],
    )
