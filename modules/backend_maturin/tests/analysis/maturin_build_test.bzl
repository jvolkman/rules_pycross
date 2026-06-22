"""Tests for maturin_build.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//rules:maturin_build.bzl", "maturin_build")

def _mock_executable_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(out, "#!/bin/sh\nexit 0", is_executable = True)
    return [DefaultInfo(executable = out)]

_mock_executable = rule(
    implementation = _mock_executable_impl,
    executable = True,
)

def _test_maturin_build_basic(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )

    util.helper_target(
        _mock_executable,
        name = name + "_mock_maturin",
    )

    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        path_tools = [name + "_mock_maturin"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_basic_impl,
    )

def _test_maturin_build_basic_impl(env, target):
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)

def _test_maturin_build_resources(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )

    util.helper_target(
        _mock_executable,
        name = name + "_mock_maturin",
    )

    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        path_tools = [name + "_mock_maturin"],
        resource_size = "medium",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_resources_impl,
    )

def _test_maturin_build_resources_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({
        "CARGO_BUILD_JOBS": "6",
        "MAKEFLAGS": "-j6",
    })

def maturin_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_maturin_build_basic,
            _test_maturin_build_resources,
        ],
    )
