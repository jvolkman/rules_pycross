"""Tests for pycross_conflict_check aspect."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross:aspects.bzl", "PycrossConflictInfo", "pycross_conflict_check")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_library.bzl", "pycross_wheel_library")

# We need a rule that the aspect can propagate through.
# Using a real py_test would require a Python toolchain, so we use
# pycross_wheel_library targets and check PycrossConflictInfo directly.

def _aspect_wrapper_rule_impl(ctx):
    """Collects PycrossConflictInfo from aspect-applied deps."""
    packages = []
    for dep in ctx.attr.deps:
        if PycrossConflictInfo in dep:
            packages.append(dep[PycrossConflictInfo].packages)
    return [
        DefaultInfo(),
        PycrossConflictInfo(packages = depset(transitive = packages)),
    ]

_aspect_wrapper = rule(
    implementation = _aspect_wrapper_rule_impl,
    attrs = {
        "deps": attr.label_list(aspects = [pycross_conflict_check]),
    },
)

# -- Test: aspect propagates PycrossPackageInfo --

def _test_aspect_collects_package_info(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib",
        wheel = name + "_wheel",
        package_name = "requests",
        package_version = "2.31.0",
    )

    util.helper_target(
        _aspect_wrapper,
        name = name + "_subject",
        deps = [name + "_lib"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_aspect_collects_package_info_impl,
    )

# buildifier: disable=unused-variable
def _test_aspect_collects_package_info_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossConflictInfo)
    packages = target[PycrossConflictInfo].packages.to_list()
    env.expect.that_int(len(packages)).equals(1)
    env.expect.that_str(packages[0].name).equals("requests")
    env.expect.that_str(packages[0].version).equals("2.31.0")

# -- Test: no conflict when same version --

def _test_no_conflict_same_version(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_a",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        native.filegroup,
        name = name + "_wheel_b",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib_a",
        wheel = name + "_wheel_a",
        package_name = "requests",
        package_version = "2.31.0",
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib_b",
        wheel = name + "_wheel_b",
        package_name = "requests",
        package_version = "2.31.0",
    )

    util.helper_target(
        _aspect_wrapper,
        name = name + "_subject",
        deps = [name + "_lib_a", name + "_lib_b"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_no_conflict_same_version_impl,
    )

# buildifier: disable=unused-variable
def _test_no_conflict_same_version_impl(env, target):
    # Should succeed — both deps have the same version
    env.expect.that_target(target).has_provider(PycrossConflictInfo)
    packages = target[PycrossConflictInfo].packages.to_list()

    # Both entries are collected (depset dedupes by identity, not value)
    names = [p.name for p in packages]
    env.expect.that_bool("requests" in names).equals(True)

# -- Test: conflict detected with different versions --
# Note: The aspect calls fail() on py_binary/py_test targets.
# Since _aspect_wrapper is not py_binary/py_test, the aspect won't fail here.
# We test that the conflict info is properly collected with different versions.

def _test_conflict_different_versions_collected(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_a",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        native.filegroup,
        name = name + "_wheel_b",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib_v1",
        wheel = name + "_wheel_a",
        package_name = "numpy",
        package_version = "1.24.0",
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib_v2",
        wheel = name + "_wheel_b",
        package_name = "numpy",
        package_version = "1.26.0",
    )

    util.helper_target(
        _aspect_wrapper,
        name = name + "_subject",
        deps = [name + "_lib_v1", name + "_lib_v2"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_conflict_different_versions_collected_impl,
    )

# buildifier: disable=unused-variable
def _test_conflict_different_versions_collected_impl(env, target):
    # Both versions should be collected in the depset
    env.expect.that_target(target).has_provider(PycrossConflictInfo)
    packages = target[PycrossConflictInfo].packages.to_list()
    versions = sorted([p.version for p in packages if p.name == "numpy"])
    env.expect.that_int(len(versions)).equals(2)
    env.expect.that_str(versions[0]).equals("1.24.0")
    env.expect.that_str(versions[1]).equals("1.26.0")

# -- Test: multiple different packages (no conflict) --

def _test_multiple_packages_no_conflict(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_a",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        native.filegroup,
        name = name + "_wheel_b",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib_requests",
        wheel = name + "_wheel_a",
        package_name = "requests",
        package_version = "2.31.0",
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib_urllib3",
        wheel = name + "_wheel_b",
        package_name = "urllib3",
        package_version = "2.1.0",
    )

    util.helper_target(
        _aspect_wrapper,
        name = name + "_subject",
        deps = [name + "_lib_requests", name + "_lib_urllib3"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_multiple_packages_no_conflict_impl,
    )

# buildifier: disable=unused-variable
def _test_multiple_packages_no_conflict_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossConflictInfo)
    packages = target[PycrossConflictInfo].packages.to_list()
    names = sorted([p.name for p in packages])
    env.expect.that_int(len(names)).equals(2)
    env.expect.that_str(names[0]).equals("requests")
    env.expect.that_str(names[1]).equals("urllib3")

# -- Test suite --

def conflict_check_aspect_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_aspect_collects_package_info,
            _test_no_conflict_same_version,
            _test_conflict_different_versions_collected,
            _test_multiple_packages_no_conflict,
        ],
    )
