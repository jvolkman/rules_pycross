"""Tests for pycross_console_script_binary"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross/private:console_script.bzl", "pycross_console_script_binary")
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

def _mock_wheel_lib_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(
        outputs = [out],
        command = "mkdir -p $1 && touch $1/entry_points.txt",
        arguments = [out.path],
    )
    return [
        DefaultInfo(files = depset([out])),
        PycrossExtractedWheelInfo(site_packages = out),
        PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
    ]

_mock_wheel_lib = rule(implementation = _mock_wheel_lib_impl)

def _test_console_script_basic(name):
    util.helper_target(_mock_wheel_lib, name = name + "_wheel_lib")
    pycross_console_script_binary(
        name = name + "_subject",
        script = "foo",
        pkg = name + "_wheel_lib",
        tags = ["manual"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_console_script_basic_impl)

def _test_console_script_basic_impl(env, target):
    # Check that it resolves to py_binary (which has PyInfo)
    env.expect.that_target(target).has_provider(PyInfo)

def console_script_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_console_script_basic,
        ],
    )
