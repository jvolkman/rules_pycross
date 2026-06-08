"""Tests for setuptools_build"""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:setuptools_build.bzl", "setuptools_build")

def _mock_sdist_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".tar.gz")
    ctx.actions.write(out, "dummy")
    return [DefaultInfo(files = depset([out]))]

_mock_sdist = rule(implementation = _mock_sdist_impl)

def _test_setuptools_build_no_repair(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        setuptools_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        native_deps = [],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_setuptools_build_no_repair_impl)

# buildifier: disable=unused-variable
def _test_setuptools_build_no_repair_impl(env, target):
    wheelhouse = target[DefaultInfo].files.to_list()[0]
    env.expect.that_target(target).action_generating(wheelhouse.short_path)
    # The action that generates the wheel should be the main build action, meaning no repair action

def _test_setuptools_build_with_repair(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(cc_library, name = name + "_cc_lib")
    util.helper_target(
        setuptools_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        native_deps = [name + "_cc_lib"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_setuptools_build_with_repair_impl)

# buildifier: disable=unused-variable
def _test_setuptools_build_with_repair_impl(env, target):
    wheelhouse = target[DefaultInfo].files.to_list()[0]
    action = env.expect.that_target(target).action_generating(wheelhouse.short_path)
    action.mnemonic().equals("RepairWheel")

def setuptools_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_setuptools_build_no_repair,
            _test_setuptools_build_with_repair,
        ],
    )
