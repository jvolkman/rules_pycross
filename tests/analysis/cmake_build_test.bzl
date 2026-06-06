"""Tests for cmake_build"""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo", "PycrossWheelInfo")
load("//pycross/private/build/rules:cmake_build.bzl", "cmake_build")

def _mock_pkg_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(outputs = [out], command = "mkdir -p $1", arguments = [out.path])
    return [
        PycrossPackageInfo(package_name = ctx.attr.package_name, package_version = "1.0"),
        DefaultInfo(files = depset([out])),
        PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
        PycrossExtractedWheelInfo(site_packages = out),
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

def _test_cmake_build_basic(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(_mock_pkg, name = name + "_cmake", package_name = "cmake")
    util.helper_target(_mock_pkg, name = name + "_ninja", package_name = "ninja")
    util.helper_target(cc_library, name = name + "_native_deps", srcs = [])
    util.helper_target(
        cmake_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        tool_deps = [name + "_cmake", name + "_ninja"],
        native_deps = [name + "_native_deps"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_cmake_build_basic_impl)

def _test_cmake_build_basic_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossWheelInfo)
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)
    out_group = target[OutputGroupInfo]
    env.expect.that_bool(hasattr(out_group, "raw_wheel")).equals(True)

def cmake_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_cmake_build_basic,
        ],
    )
