"""Tests for pep517_build"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
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
        whldir_name = "pkg-1.0.whldir",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pep517_build_invalid_deps_impl,
    )

def _test_pep517_build_invalid_deps_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)
    env.expect.that_str(wheel_dir.basename).equals("pkg-1.0.whldir")
    env.expect.that_target(target).output_group("raw_wheel").contains_exactly([wheel_dir.short_path])

    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossSdistBuildConfigError")
    action.env().contains_exactly({
        "PYCROSS_ERROR": "Cannot build {}_sdist.tar.gz from source:\n".format(target.label.name.removesuffix("_subject")) +
                         "Missing required build-system packages: hatchling. " +
                         "These are listed in build-system.requires but are not present in build_deps. " +
                         "Make sure they are included in your lockfile.",
    })

    # The real build should not be registered.
    env.expect.that_bool(
        any([a.mnemonic == "PycrossPep517Build" for a in target.actions]),
    ).equals(False)

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

def _test_pep517_build_scratch_dirs(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_scratch_dirs_impl)

def _test_pep517_build_scratch_dirs_impl(env, target):
    # Scratch dirs live next to the wheel output so they are unique per
    # repo/package/target (the builder wipes them before use).
    build = [a for a in target.actions if a.mnemonic == "PycrossPep517Build"][0]
    out_dir = build.outputs.to_list()[0].dirname
    env.expect.that_str(out_dir).contains(target.label.name)
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({
        "PYCROSS_BUILD_ROOT": out_dir + "/_tmp",
        "PYCROSS_SDIST_DIR": out_dir + "/sdist",
    })

def pep517_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pep517_build_valid_deps,
            _test_pep517_build_invalid_deps,
            _test_pep517_build_basic,
            _test_pep517_build_resources,
            _test_pep517_build_scratch_dirs,
        ],
    )
