"""Analysis tests for pycross_wheel_dir."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossUnsupportedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_dir.bzl", "pycross_wheel_dir")

def _unsupported_src_impl(_ctx):
    return [PycrossUnsupportedWheelInfo(package = "placeholder")]

_unsupported_src = rule(implementation = _unsupported_src_impl)

def _test_wheel_dir_explicit_package_name(name):
    util.helper_target(_unsupported_src, name = name + "_unsupported")
    util.helper_target(
        pycross_wheel_dir,
        name = name + "_subject",
        src = name + "_unsupported",
        whldir_name = "demo-1.0.0.whldir",
        package = "demo@1.0.0",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_dir_explicit_package_name_impl)

def _test_wheel_dir_explicit_package_name_impl(env, target):
    env.expect.that_str(target[PycrossUnsupportedWheelInfo].package).equals("demo@1.0.0")
    action = env.expect.that_target(target).action_named("PycrossUnsupportedWheel")
    action.env().contains_at_least({"PYCROSS_ERROR": "No compatible wheel is available for demo@1.0.0 in the selected target environment."})

def wheel_dir_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_wheel_dir_explicit_package_name,
        ],
    )
