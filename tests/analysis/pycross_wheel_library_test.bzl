"""Module docstring for tests."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_library.bzl", "pycross_wheel_library")

def _test_pycross_wheel_library_basic(name):
    # Dummy wheel file
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "test",
        package_version = "1.0",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_library_basic_impl,
    )

def _test_pycross_wheel_library_basic_impl(env, target):
    # Check that it returns PycrossExtractedWheelInfo
    # buildifier: disable=unused-variable
    extracted_info = env.expect.that_target(target).has_provider(PycrossExtractedWheelInfo)

    # Check that it returns PycrossPackageInfo
    # buildifier: disable=unused-variable
    pkg_info = env.expect.that_target(target).has_provider(PycrossPackageInfo)

    # Assert package details
    if PycrossPackageInfo in target:
        env.expect.that_str(target[PycrossPackageInfo].package_name).equals("test")
        env.expect.that_str(target[PycrossPackageInfo].package_version).equals("1.0")

def pycross_wheel_library_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_wheel_library_basic,
        ],
    )
