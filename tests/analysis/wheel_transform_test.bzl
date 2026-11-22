"""Tests for pycross_wheel_transform"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_transform.bzl", "pycross_wheel_transform")

def _mock_exe_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(out, "exit 0", is_executable = True)
    return [DefaultInfo(files = depset([out]), executable = out)]

_mock_exe = rule(implementation = _mock_exe_impl, executable = True)

def _mock_wheel_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_whldir")
    ctx.actions.run_shell(
        outputs = [out],
        command = "touch %s/dummy.whl" % out.path,
    )
    return [
        DefaultInfo(files = depset([out])),
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

# buildifier: disable=unused-variable
def _test_wheel_transform_basic_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_target(target).action_generating(wheel_dir.short_path)

    # The action executable should be the transform tool
    raw_action = [a for a in target.actions if wheel_dir in a.outputs.to_list()][0]
    env.expect.that_str(str(raw_action.argv)).contains("_transform_tool")

def _mock_data_with_runfiles_impl(ctx):
    main = ctx.actions.declare_file(ctx.label.name + "_main.txt")
    rf = ctx.actions.declare_file(ctx.label.name + "_runfile.dat")
    ctx.actions.write(main, "main")
    ctx.actions.write(rf, "rf")
    return [
        DefaultInfo(
            files = depset([main]),
            runfiles = ctx.runfiles(files = [rf]),
        ),
    ]

_mock_data_with_runfiles = rule(implementation = _mock_data_with_runfiles_impl)

def _test_wheel_transform_plain_file_and_data_runfiles(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(_mock_exe, name = name + "_transform_tool")
    util.helper_target(_mock_data_with_runfiles, name = name + "_data")
    util.helper_target(
        pycross_wheel_transform,
        name = name + "_subject",
        wheel = name + "_wheel",
        transform = name + "_transform_tool",
        data = [name + "_data"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_transform_plain_file_and_data_runfiles_impl,
    )

def _test_wheel_transform_plain_file_and_data_runfiles_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossWheelTransform")
    action.argv().contains("--in-wheel")
    action.argv().not_contains("--in-wheel-dir")
    action.inputs().contains_predicate(matching.file_basename_equals(target.label.name.removesuffix("_subject") + "_data_runfile.dat"))

def wheel_transform_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_wheel_transform_basic,
            _test_wheel_transform_plain_file_and_data_runfiles,
        ],
    )
