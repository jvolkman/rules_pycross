"""Tests for pycross_repaired_wheel."""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:repaired_wheel.bzl", "pycross_repaired_wheel")

def _mock_wheel_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_wheelhouse")
    ctx.actions.run_shell(
        outputs = [out],
        command = "mkdir -p %s && touch %s/dummy-1.0-py3-none-any.whl" % (out.path, out.path),
    )
    return [
        DefaultInfo(files = depset([out])),
        PycrossWheelInfo(wheelhouse = out),
    ]

_mock_wheel = rule(implementation = _mock_wheel_impl)

def _test_repaired_wheel_basic(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(
        pycross_repaired_wheel,
        name = name + "_subject",
        wheel = name + "_wheel",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_repaired_wheel_basic_impl)

# buildifier: disable=unused-variable
def _test_repaired_wheel_basic_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossWheelInfo)
    wheelhouse = target[PycrossWheelInfo].wheelhouse
    env.expect.that_bool(wheelhouse.is_directory).equals(True)
    env.expect.that_str(wheelhouse.basename).contains("repaired_wheelhouse")

    # The action generating the wheelhouse should be RepairWheel
    action = env.expect.that_target(target).action_generating(wheelhouse.short_path)
    action.mnemonic().equals("RepairWheel")

def _test_repaired_wheel_with_native_deps(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(cc_library, name = name + "_cc_lib")
    util.helper_target(
        pycross_repaired_wheel,
        name = name + "_subject",
        wheel = name + "_wheel",
        native_deps = [name + "_cc_lib"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_repaired_wheel_with_native_deps_impl)

# buildifier: disable=unused-variable
def _test_repaired_wheel_with_native_deps_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossWheelInfo)
    wheelhouse = target[PycrossWheelInfo].wheelhouse
    env.expect.that_bool(wheelhouse.is_directory).equals(True)

def repaired_wheel_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_repaired_wheel_basic,
            _test_repaired_wheel_with_native_deps,
        ],
    )
