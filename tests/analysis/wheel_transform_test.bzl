"""Tests for pycross_wheel_transform"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross/private:providers.bzl", "PycrossWheelInfo")
load("//pycross/private:wheel_transform.bzl", "pycross_wheel_transform")

def _mock_exe_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(out, "exit 0", is_executable = True)
    return [DefaultInfo(files = depset([out]), executable = out)]

_mock_exe = rule(implementation = _mock_exe_impl, executable = True)

def _mock_wheel_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".whl")
    ctx.actions.write(out, "dummy")
    name_file = ctx.actions.declare_file(ctx.label.name + "_name.txt")
    ctx.actions.write(name_file, "dummy")
    return [
        DefaultInfo(files = depset([out])),
        PycrossWheelInfo(wheel_file = out, name_file = name_file, wheel_directory = None),
    ]

_mock_wheel = rule(implementation = _mock_wheel_impl)

def _test_wheel_transform_basic(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(_mock_exe, name = name + "_transform_tool")
    util.helper_target(
        pycross_wheel_transform,
        name = name + "_subject",
        wheel = name + "_wheel",
        transform = name + "_transform_tool",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_transform_basic_impl)

def _test_wheel_transform_basic_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossWheelInfo)
    wheel_file = target[PycrossWheelInfo].wheel_file
    action = env.expect.that_target(target).action_generating(wheel_file.short_path)

    # The action executable should be the transform tool
    action = env.expect.that_target(target).action_generating(wheel_file.short_path)
    env.expect.that_str(str(target.actions[0].argv)).contains("_transform_tool")

def wheel_transform_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_wheel_transform_basic,
        ],
    )
