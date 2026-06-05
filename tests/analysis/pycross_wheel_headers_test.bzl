load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private/build:wheel_headers.bzl", "pycross_wheel_headers")
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

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

def _test_pycross_wheel_headers_basic_impl(env, target):
    # Check that it returns CcInfo
    env.expect.that_target(target).has_provider(CcInfo)
    
    # Check TemplateVariableInfo
    env.expect.that_target(target).has_provider(platform_common.TemplateVariableInfo)

def pycross_wheel_headers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_wheel_headers_basic,
        ],
    )
