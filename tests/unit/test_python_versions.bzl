"""Tests for pycross/private/python_versions.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:python_versions.bzl", "dedupe_versions", "get_micro_version", "resolve_interpreter_version")

# Hub-style tables in which 3.15.0 exists only because of a python.single_version_override:
# rules_python's built-in tables don't know it.
_MINOR_MAPPING = {
    "3.14": "3.14.2",
    "3.15": "3.15.0",
}
_PYTHON_VERSIONS = ["3.11.6", "3.14.0", "3.14.2", "3.15.0"]

def _subject(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    return name + "_subject"

# buildifier: disable=unused-variable
def _test_get_micro_version_impl(env, target):
    env.expect.that_str(get_micro_version("3.15.0", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.15.0")
    env.expect.that_str(get_micro_version("3.15", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.15.0")
    env.expect.that_str(get_micro_version("3.14", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.14.2")
    env.expect.that_str(get_micro_version("3.11.6", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.11.6")
    env.expect.that_bool(get_micro_version("3.8", _MINOR_MAPPING, _PYTHON_VERSIONS) == None).equals(True)

def _test_get_micro_version(name):
    analysis_test(name = name, target = _subject(name), impl = _test_get_micro_version_impl)

# buildifier: disable=unused-variable
def _test_dedupe_versions_impl(env, target):
    env.expect.that_collection(
        dedupe_versions(["3.15.0", "3.14", "3.14.2", "3.11.6", "3.8"], _MINOR_MAPPING, _PYTHON_VERSIONS),
    ).contains_exactly(["3.11.6", "3.14.2", "3.15.0"]).in_order()

def _test_dedupe_versions(name):
    analysis_test(name = name, target = _subject(name), impl = _test_dedupe_versions_impl)

# buildifier: disable=unused-variable
def _test_resolve_interpreter_version_impl(env, target):
    # The non-default override-only version is kept, not mapped to the default.
    env.expect.that_str(resolve_interpreter_version("3.15.0", "3.14.2", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.15.0")
    env.expect.that_str(resolve_interpreter_version("3.15", "3.14.2", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.15.0")

    # An override-only default resolves.
    env.expect.that_str(resolve_interpreter_version("", "3.15.0", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.15.0")
    env.expect.that_str(resolve_interpreter_version("3.11.6", "3.15.0", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.11.6")

    # Unknown versions fall back to the default.
    env.expect.that_str(resolve_interpreter_version("3.9.99", "3.14.2", _MINOR_MAPPING, _PYTHON_VERSIONS)).equals("3.14.2")

def _test_resolve_interpreter_version(name):
    analysis_test(name = name, target = _subject(name), impl = _test_resolve_interpreter_version_impl)

def python_versions_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_get_micro_version,
            _test_dedupe_versions,
            _test_resolve_interpreter_version,
        ],
    )
