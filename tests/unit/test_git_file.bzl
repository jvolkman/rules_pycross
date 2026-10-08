"""Tests for git URL parsing in git_file.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:git_file.bzl", "parse_git_url")

_SHA = "be7c37807fc9f4f035ba4efc7dc33f42099f8308"

def _unit_test(name, impl):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = impl)

# buildifier: disable=unused-variable
def _test_parse_git_url_plain_impl(env, target):
    src = parse_git_url("git+https://github.com/pypa/packaging.git#" + _SHA)
    env.expect.that_str(src.remote).equals("https://github.com/pypa/packaging.git")
    env.expect.that_str(src.commit).equals(_SHA)
    env.expect.that_bool(src.lfs).equals(False)

def _test_parse_git_url_plain(name):
    _unit_test(name, _test_parse_git_url_plain_impl)

# buildifier: disable=unused-variable
def _test_parse_git_url_uv_query_impl(env, target):
    # uv.lock writes `lfs=true` in the query only when the source enables it.
    src = parse_git_url("git+file:///tmp/lib?subdirectory=pkgs%2Fa&lfs=true&rev=main#" + _SHA)
    env.expect.that_str(src.remote).equals("file:///tmp/lib")
    env.expect.that_str(src.commit).equals(_SHA)
    env.expect.that_bool(src.lfs).equals(True)

    src = parse_git_url("git+https://host/repo?rev=v1.0#" + _SHA)
    env.expect.that_str(src.remote).equals("https://host/repo")
    env.expect.that_bool(src.lfs).equals(False)

def _test_parse_git_url_uv_query(name):
    _unit_test(name, _test_parse_git_url_uv_query_impl)

def git_file_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_parse_git_url_plain,
            _test_parse_git_url_uv_query,
        ],
    )
