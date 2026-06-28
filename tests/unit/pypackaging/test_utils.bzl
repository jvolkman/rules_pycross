"""Tests for utils.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/pypackaging/utils:utils.bzl", "utils")

def _test_canonicalize_version_impl(env, _target):
    env.expect.that_str(utils.canonicalize_version("1.0.0")).equals("1")
    env.expect.that_str(utils.canonicalize_version("1.0.0", strip_trailing_zero = False)).equals("1.0.0")
    env.expect.that_str(utils.canonicalize_version("1.4.0.0.0")).equals("1.4")

def _test_canonicalize_version(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_canonicalize_version_impl)

def _test_parse_wheel_filename_impl(env, _target):
    res = utils.parse_wheel_filename("foo-1.0-py3-none-any.whl")
    env.expect.that_str(res.name).equals("foo")
    env.expect.that_str(res.version.version_str).equals("1.0")
    env.expect.that_collection(res.build).contains_exactly([])
    env.expect.that_int(len(res.tags)).equals(1)

    tag = res.tags[0]
    env.expect.that_str(tag.interpreter).equals("py3")
    env.expect.that_str(tag.abi).equals("none")
    env.expect.that_str(tag.platform).equals("any")

def _test_parse_wheel_filename(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wheel_filename_impl)

def _test_parse_sdist_filename_impl(env, _target):
    res = utils.parse_sdist_filename("foo-1.0.tar.gz")
    env.expect.that_str(res.name).equals("foo")
    env.expect.that_str(res.version.version_str).equals("1.0")

def _test_parse_sdist_filename(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_sdist_filename_impl)

def utils_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_canonicalize_version,
            _test_parse_wheel_filename,
            _test_parse_sdist_filename,
        ],
    )
