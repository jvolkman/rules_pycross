"""Tests for pycross_exec_platform_transition"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")

# buildifier: disable=unused-variable
def _mock_dep_impl(ctx):
    return [DefaultInfo()]

_mock_dep = rule(implementation = _mock_dep_impl)

# buildifier: disable=unused-variable
def _mock_rule_impl(ctx):
    return [DefaultInfo()]

_mock_rule = rule(
    implementation = _mock_rule_impl,
    attrs = {
        "dep": attr.label(cfg = pycross_exec_platform_transition),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _test_transitions_basic(name):
    util.helper_target(_mock_dep, name = name + "_dep")
    util.helper_target(_mock_rule, name = name + "_subject", dep = name + "_dep")
    analysis_test(name = name, target = name + "_subject", impl = _test_transitions_basic_impl)

# buildifier: disable=unused-variable
def _test_transitions_basic_impl(env, target):
    # Transitioned dep should exist
    env.expect.that_target(target).has_provider(DefaultInfo)

def transitions_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_transitions_basic,
        ],
    )
