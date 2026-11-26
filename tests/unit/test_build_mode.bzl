"""Tests for package(build_mode = ...) merging and sdist-build gating."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:format_extension.bzl", "package_tag_to_dict_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_repo_creation.bzl", "sdist_builds_disallowed_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "resolve")

def _pkg_tag(**kwargs):
    """A raw package() tag struct with every field at its Bazel attr default unless overridden."""
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
        build_backend = "",
        site_paths = [],
        bin_paths = [],
        data_paths = [],
        include_paths = [],
        wheel_library_tags = [],
        precompile = "",
    )
    fields.update(kwargs)
    return struct(**fields)

def _resolve_with_tags(pkg_tag, wildcard_tag = None):
    lock_model_data = {
        "packages": {
            "foo@1.0": {
                "name": "foo",
                "version": "1.0",
                "dependencies": [],
                "files": [
                    {"name": "foo-1.0-py3-none-any.whl", "sha256": "aaaa"},
                    {"name": "foo-1.0.tar.gz", "sha256": "bbbb"},
                ],
            },
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations = {"foo": package_tag_to_dict_for_testing(pkg_tag)}
    if wildcard_tag != None:
        annotations["*"] = package_tag_to_dict_for_testing(wildcard_tag)
    return resolve(lock_model_data, annotations_data = annotations).packages["foo@1.0"]

def _subject(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])

# buildifier: disable=unused-variable
def _test_default_is_auto_impl(env, target):
    pkg = _resolve_with_tags(_pkg_tag())
    env.expect.that_str(pkg["build_mode"]).equals("auto")
    env.expect.that_str(pkg["precompile"]).equals("")
    env.expect.that_bool(pkg["build_backend"] == None).equals(True)

    # Raw tag conversion stringifies Label / label_list attrs and omits unset defaults.
    raw = package_tag_to_dict_for_testing(_pkg_tag(
        build_target = Label("//pkg:custom"),
        post_install_patches = [Label("//pkg:post.patch")],
        pre_build_patches = [Label("//pkg:pre.patch")],
        install_exclude_globs = ["*.pyc", "*.pyc"],
    ))
    env.expect.that_str(raw["build_target"]).equals(str(Label("//pkg:custom")))
    env.expect.that_collection(raw["post_install_patches"]).contains_exactly([str(Label("//pkg:post.patch"))])
    env.expect.that_collection(raw["pre_build_patches"]).contains_exactly([str(Label("//pkg:pre.patch"))])
    env.expect.that_bool("build_mode" not in raw).equals(True)
    env.expect.that_bool("build_backend" not in raw).equals(True)

    resolved_dedup = _resolve_with_tags(_pkg_tag(install_exclude_globs = ["*.pyc", "tests/**", "*.pyc"]))
    env.expect.that_collection(resolved_dedup["install_exclude_globs"]).contains_exactly(["*.pyc", "tests/**"]).in_order()

def _test_default_is_auto(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_default_is_auto_impl)

# buildifier: disable=unused-variable
def _test_specific_inherits_wildcard_impl(env, target):
    # A specific entry that only sets another field inherits build_mode and precompile from "*".
    pkg = _resolve_with_tags(
        _pkg_tag(site_hooks = ["import foo"]),
        _pkg_tag(build_mode = "always", precompile = "enabled"),
    )
    env.expect.that_str(pkg["build_mode"]).equals("always")
    env.expect.that_str(pkg["precompile"]).equals("enabled")
    env.expect.that_collection(pkg["site_hooks"]).contains_exactly(["import foo"])

def _test_specific_inherits_wildcard(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_specific_inherits_wildcard_impl)

# buildifier: disable=unused-variable
def _test_specific_auto_opts_out_impl(env, target):
    pkg = _resolve_with_tags(
        _pkg_tag(build_mode = "auto", precompile = "disabled"),
        _pkg_tag(build_mode = "never", precompile = "enabled"),
    )
    env.expect.that_str(pkg["build_mode"]).equals("auto")
    env.expect.that_str(pkg["precompile"]).equals("disabled")

    pkg_auto = _resolve_with_tags(
        _pkg_tag(precompile = "auto"),
        _pkg_tag(precompile = "enabled"),
    )
    env.expect.that_str(pkg_auto["precompile"]).equals("auto")

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
