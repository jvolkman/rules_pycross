"""Module docstring for tests."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:wheel_headers.bzl", "pycross_wheel_headers")

def _mock_wheel_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(
        outputs = [out],
        command = "mkdir -p $1",
        arguments = [out.path],
    )
    return [
        DefaultInfo(files = depset([out])),
        PycrossExtractedWheelInfo(site_packages = out),
    ]

_mock_wheel = rule(implementation = _mock_wheel_impl)

def _test_pycross_wheel_headers_basic(name):
    # Dummy wheel rule providing PycrossExtractedWheelInfo
    util.helper_target(
        _mock_wheel,
        name = name + "_wheel",
    )

    util.helper_target(
        pycross_wheel_headers,
        name = name + "_subject",
        wheel = name + "_wheel",
        include_dir = "numpy/_core/include",
        make_variable = "NUMPY_INCLUDE",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_headers_basic_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_headers_basic_impl(env, target):
    # Check that it returns CcInfo
    env.expect.that_target(target).has_provider(CcInfo)

    cc_info = target[CcInfo]
    includes = cc_info.compilation_context.includes.to_list()

    # It should include the path to the site_packages / include_dir
    found = False
    for inc in includes:
        if "numpy/_core/include" in inc:
            found = True
    env.expect.that_bool(found).equals(True)

    # Check TemplateVariableInfo
    env.expect.that_target(target).has_provider(platform_common.TemplateVariableInfo)
    tv_info = target[platform_common.TemplateVariableInfo]
    env.expect.that_collection(tv_info.variables.keys()).contains("NUMPY_INCLUDE")

def _test_pycross_wheel_headers_no_make_variable(name):
    util.helper_target(
        _mock_wheel,
        name = name + "_wheel",
    )
    util.helper_target(
        pycross_wheel_headers,
        name = name + "_subject",
        wheel = name + "_wheel",
        include_dir = "numpy/_core/include",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_headers_no_make_variable_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_headers_no_make_variable_impl(env, target):
    env.expect.that_bool(platform_common.TemplateVariableInfo in target).equals(False)

def pycross_wheel_headers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_wheel_headers_basic,
            _test_pycross_wheel_headers_no_make_variable,
        ],
    )
