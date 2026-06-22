"""Tests for meson_build"""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:meson_build.bzl", "meson_build")

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

def _test_meson_build_basic(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(_mock_pkg, name = name + "_meson", package_name = "meson")
    util.helper_target(_mock_pkg, name = name + "_ninja", package_name = "ninja")
    util.helper_target(cc_library, name = name + "_native_deps", srcs = [])
    util.helper_target(
        meson_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        tool_deps = [name + "_meson", name + "_ninja"],
        native_deps = [name + "_native_deps"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_meson_build_basic_impl)

# buildifier: disable=unused-variable
def _test_meson_build_basic_impl(env, target):
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)
    out_group = target[OutputGroupInfo]
    env.expect.that_bool(hasattr(out_group, "raw_wheel")).equals(True)

def _test_meson_build_resources(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(_mock_pkg, name = name + "_meson", package_name = "meson")
    util.helper_target(_mock_pkg, name = name + "_ninja", package_name = "ninja")
    util.helper_target(cc_library, name = name + "_native_deps", srcs = [])
    util.helper_target(
        meson_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        tool_deps = [name + "_meson", name + "_ninja"],
        native_deps = [name + "_native_deps"],
        resource_size = "medium",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_meson_build_resources_impl)

# buildifier: disable=unused-variable
def _test_meson_build_resources_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({
        "MESON_NUM_PROCESSES": "6",
        "NINJA_JOBS": "6",
        "MAKEFLAGS": "-j6",
    })

def meson_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_meson_build_basic,
            _test_meson_build_resources,
        ],
    )
