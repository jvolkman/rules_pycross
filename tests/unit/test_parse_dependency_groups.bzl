"""Tests for parse_dependency_group_entries in lock_common.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_common.bzl", "parse_dependency_group_entries")

# --- test: basic testonly group ---

# buildifier: disable=unused-variable
def _test_parse_basic_testonly_impl(env, target):
    """['default', 'group:dev;testonly'] -> group:dev is testonly."""
    result = parse_dependency_group_entries(["default", "group:dev;testonly"])

    env.expect.that_collection(result.dependency_groups).contains_exactly(["default", "group:dev"])
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["default"])
    env.expect.that_bool(result.wildcard_testonly).equals(False)

def _test_parse_basic_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_basic_testonly_impl)

# --- test: wildcard then specific testonly ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_then_specific_testonly_impl(env, target):
    """['*', 'group:dev;testonly'] -> wildcard not testonly, group:dev overrides to testonly."""
    result = parse_dependency_group_entries(["*", "group:dev;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_wildcard_then_specific_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_then_specific_testonly_impl)

# --- test: specific testonly then wildcard resets ---

# buildifier: disable=unused-variable
def _test_parse_specific_testonly_then_wildcard_impl(env, target):
    """['group:dev;testonly', '*'] -> * comes last, resets group:dev's testonly."""
    result = parse_dependency_group_entries(["group:dev;testonly", "*"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_specific_testonly_then_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_specific_testonly_then_wildcard_impl)

# --- test: wildcard testonly with specific override ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_testonly_with_override_impl(env, target):
    """['*;testonly', 'group:dev'] -> everything testonly except group:dev."""
    result = parse_dependency_group_entries(["*;testonly", "group:dev"])

    env.expect.that_bool(result.wildcard_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["group:dev"])

def _test_parse_wildcard_testonly_with_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_testonly_with_override_impl)

# --- test: wildcard testonly alone ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_testonly_alone_impl(env, target):
    """['*;testonly'] -> everything testonly, no overrides."""
    result = parse_dependency_group_entries(["*;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_wildcard_testonly_alone(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_testonly_alone_impl)

# --- test: no testonly at all ---

# buildifier: disable=unused-variable
def _test_parse_no_testonly_impl(env, target):
    """['default', 'group:dev'] -> nothing testonly."""
    result = parse_dependency_group_entries(["default", "group:dev"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["default", "group:dev"])

def _test_parse_no_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_no_testonly_impl)

# --- test: transitive with testonly ---

# buildifier: disable=unused-variable
def _test_parse_transitive_testonly_impl(env, target):
    """['default', 'group:dev;testonly', 'transitive;testonly'] -> transitive_testonly is True."""
    result = parse_dependency_group_entries(["default", "group:dev;testonly", "transitive;testonly"])

    env.expect.that_bool(result.include_transitive).equals(True)
    env.expect.that_bool(result.transitive_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])

    # "transitive" should NOT appear in dependency_groups
    env.expect.that_collection(result.dependency_groups).contains_exactly(["default", "group:dev"])

def _test_parse_transitive_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_transitive_testonly_impl)

# --- test: double wildcard, last wins ---

# buildifier: disable=unused-variable
def _test_parse_double_wildcard_impl(env, target):
    """['*;testonly', 'group:dev;testonly', '*', 'group:test;testonly'] -> second * resets.

    First *;testonly sets wildcard_testonly=True.
    group:dev;testonly is a specific override.
    Second * (not testonly) resets wildcard_testonly=False and clears group:dev override.
    group:test;testonly is a new specific override after the second *.
    """
    result = parse_dependency_group_entries(["*;testonly", "group:dev;testonly", "*", "group:test;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)

    # group:dev;testonly was before the second *, so it's reset
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:test"])
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_double_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_double_wildcard_impl)

# --- Test suite ---

def parse_dependency_groups_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_parse_basic_testonly,
            _test_parse_wildcard_then_specific_testonly,
            _test_parse_specific_testonly_then_wildcard,
            _test_parse_wildcard_testonly_with_override,
            _test_parse_wildcard_testonly_alone,
            _test_parse_no_testonly,
            _test_parse_transitive_testonly,
            _test_parse_double_wildcard,
        ],
    )
