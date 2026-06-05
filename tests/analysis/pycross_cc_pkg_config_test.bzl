load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross/private/build:cc_pkg_config.bzl", "pycross_cc_pkg_config")

def _test_pycross_cc_pkg_config(name):
    util.helper_target(
        cc_library,
        name = name + "_mock_lib",
        srcs = ["mock.cc"],
        hdrs = ["mock.h"],
    )

    util.helper_target(
        pycross_cc_pkg_config,
        name = name + "_subject",
        dep = name + "_mock_lib",
        lib_name = "mock_lib",
        version = "1.2.3",
        description = "Mock description",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_cc_pkg_config_impl,
    )

def _test_pycross_cc_pkg_config_impl(env, target):
    action = env.expect.that_target(target).action_generating("tests/analysis/mock_lib.pc")
    
    # Assert action type
    action.mnemonic().equals("FileWrite")
    
    # Assert content
    content = action.content()
    content.contains("Name: mock_lib")
    content.contains("Version: 1.2.3")
    content.contains("Description: Mock description")
    content.contains("Libs:")
    content.contains("Cflags:")

def pycross_cc_pkg_config_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_cc_pkg_config,
        ],
    )
