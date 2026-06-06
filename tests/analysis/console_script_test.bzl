"""Tests for pycross_console_script_binary"""

load("@rules_python//python:defs.bzl", "PyInfo", "py_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:console_script.bzl", "pycross_console_script_binary")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

def _mock_wheel_lib_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(
        outputs = [out],
        command = "mkdir -p $1 && touch $1/entry_points.txt",
        arguments = [out.path],
    )
    if ctx.attr.fail_no_provider:
        return [
            DefaultInfo(files = depset([out])),
            PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
        ]
    return [
        DefaultInfo(files = depset([out])),
        PycrossExtractedWheelInfo(site_packages = out),
        PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
    ]

_mock_wheel_lib = rule(
    implementation = _mock_wheel_lib_impl,
    attrs = {
        "fail_no_provider": attr.bool(default = False),
    },
)

def _test_console_script_basic(name):
    util.helper_target(_mock_wheel_lib, name = name + "_wheel_lib")
    util.helper_target(py_library, name = name + "_extra_lib")
    pycross_console_script_binary(
        name = name + "_subject",
        script = "foo",
        pkg = name + "_wheel_lib",
        deps = [name + "_extra_lib"],
        tags = ["manual"],
    )
    analysis_test(name = name + "_extractor", target = name + "_subject_script", impl = _test_console_script_extractor_impl)
    analysis_test(name = name + "_binary", target = name + "_subject", impl = _test_console_script_binary_impl)
    native.test_suite(name = name, tests = [name + "_extractor", name + "_binary"])

# buildifier: disable=unused-variable
def _test_console_script_extractor_impl(env, target):
    expected_out = target.label.name[:-7] + ".py"
    action = env.expect.that_target(target).action_generating("tests/analysis/" + expected_out)
    action.mnemonic().equals("ExtractConsoleScript")
    env.expect.that_target(target).default_outputs().contains_exactly(["tests/analysis/" + expected_out])
    action.argv().contains("--script")
    action.argv().contains("foo")
    action.argv().contains("--site-packages")

# buildifier: disable=unused-variable
def _test_console_script_binary_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)

def _test_console_script_missing_provider(name):
    util.helper_target(_mock_wheel_lib, name = name + "_wheel_lib", fail_no_provider = True)
    pycross_console_script_binary(
        name = name + "_subject",
        script = "foo",
        pkg = name + "_wheel_lib",
        tags = ["manual"],
    )
    analysis_test(name = name, target = name + "_subject_script", expect_failure = True, impl = _test_console_script_missing_provider_impl)

# buildifier: disable=unused-variable
def _test_console_script_missing_provider_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("PycrossExtractedWheelInfo"))

def console_script_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_console_script_basic,
            _test_console_script_missing_provider,
        ],
    )
