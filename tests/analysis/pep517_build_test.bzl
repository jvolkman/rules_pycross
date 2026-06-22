"""Tests for pep517_build"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossPackageInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:pep517_build.bzl", "pep517_build")

def _mock_pkg_impl(ctx):
    return [
        PycrossPackageInfo(package_name = ctx.attr.package_name, package_version = "1.0"),
        DefaultInfo(),
        PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
    ]

_mock_pkg = rule(
    implementation = _mock_pkg_impl,
    attrs = {"package_name": attr.string()},
)

def _mock_sdist_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".tar.gz")
    ctx.actions.write(out, "dummy")
    return [DefaultInfo(files = depset([out]))]

_mock_sdist = rule(implementation = _mock_sdist_impl)

def _test_pep517_build_valid_deps(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(_mock_pkg, name = name + "_hatchling", package_name = "hatchling")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        required_build_packages = ["hatchling"],
        build_deps = [name + "_hatchling"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_valid_deps_impl)

# buildifier: disable=unused-variable
def _test_pep517_build_valid_deps_impl(env, target):
    pass

def _test_pep517_build_invalid_deps(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        required_build_packages = ["hatchling"],
        build_deps = [],
        tags = ["manual"],
    )
    analysis_test(name = name, target = name + "_subject", expect_failure = True, impl = _test_pep517_build_invalid_deps_impl)

# buildifier: disable=unused-variable
def _test_pep517_build_invalid_deps_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("Missing required build-system packages: hatchling."))

def _test_pep517_build_basic(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_basic_impl)

# buildifier: disable=unused-variable
def _test_pep517_build_basic_impl(env, target):
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)

    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)

def _test_pep517_build_resources(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        resource_size = "medium",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_resources_impl)

# buildifier: disable=unused-variable
def _test_pep517_build_resources_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({"MAKEFLAGS": "-j6"})

def pep517_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pep517_build_valid_deps,
            _test_pep517_build_invalid_deps,
            _test_pep517_build_basic,
            _test_pep517_build_resources,
        ],
    )
