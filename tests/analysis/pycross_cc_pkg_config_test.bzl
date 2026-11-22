"""Module docstring for tests."""

load("@rules_cc//cc:defs.bzl", "cc_import", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:cc_pkg_config.bzl", "pycross_cc_pkg_config")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:wheel_cc_import.bzl", "pycross_wheel_cc_import")

def _test_pycross_cc_pkg_config(name):
    util.helper_target(
        cc_library,
        name = name + "_mock_lib",
        srcs = ["mock.cc"],
        hdrs = ["mock.h"],
        includes = ["include/mock"],
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

# buildifier: disable=unused-variable
def _test_pycross_cc_pkg_config_impl(env, target):
    action = env.expect.that_target(target).action_generating("tests/analysis/mock_lib.pc")

    # Assert action type
    action.mnemonic().equals("FileWrite")

    # Assert content
    content = action.content()
    content.contains("Name: mock_lib")
    content.contains("Version: 1.2.3")
    content.contains("Description: Mock description")
    content.contains("-I$$EXT_BUILD_ROOT$$/tests/analysis/include/mock")
    raw = [a.content for a in target.actions if a.mnemonic == "FileWrite"][0]

    # On PIC platforms (Linux), cc_library emits a .pic.a archive which is linked
    # directly by path; on non-PIC platforms (macOS/Windows), it emits -l<name>.
    has_pic_path = "libtest_pycross_cc_pkg_config_mock_lib.pic.a" in raw
    has_lib_flag = "-ltest_pycross_cc_pkg_config_mock_lib" in raw
    env.expect.that_bool(has_pic_path or has_lib_flag).equals(True)
    env.expect.that_bool("-ltest_pycross_cc_pkg_config_mock_lib.pic" in raw).equals(False)

def _test_pycross_cc_pkg_config_libprefix(name):
    util.helper_target(
        cc_import,
        name = "lib" + name + "_foo",
        static_library = "liblib" + name + "_foo.a",
    )

    util.helper_target(
        pycross_cc_pkg_config,
        name = name + "_subject",
        dep = "lib" + name + "_foo",
        lib_name = "libfoo",
        version = "1.0.0",
        description = "libfoo",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_cc_pkg_config_libprefix_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_cc_pkg_config_libprefix_impl(env, target):
    action = env.expect.that_target(target).action_generating("tests/analysis/libfoo.pc")
    content = action.content()
    content.contains("-L$$EXT_BUILD_ROOT$$/tests/analysis")
    content.contains("-llibtest_pycross_cc_pkg_config_libprefix_foo")

def _test_pycross_cc_pkg_config_pic_static_library(name):
    util.helper_target(
        cc_import,
        name = name + "_pic",
        static_library = "libmock_pic.a",
        pic_static_library = "libmock_pic.pic.a",
    )
    util.helper_target(
        pycross_cc_pkg_config,
        name = name + "_subject",
        dep = name + "_pic",
        lib_name = "mock_pic",
        version = "1.0.0",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_cc_pkg_config_pic_static_library_impl,
    )

def _test_pycross_cc_pkg_config_pic_static_library_impl(env, target):
    content = env.expect.that_target(target).action_generating("tests/analysis/mock_pic.pc").content()
    content.contains("$$EXT_BUILD_ROOT$$/tests/analysis/libmock_pic.pic.a")
    raw = [a.content for a in target.actions if a.mnemonic == "FileWrite"][0]
    env.expect.that_bool("-lmock_pic" in raw).equals(False)

def _mock_installed_wheel_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(outputs = [out], command = "mkdir -p $1", arguments = [out.path])
    return [DefaultInfo(files = depset([out])), PycrossExtractedWheelInfo(site_packages = out)]

_mock_installed_wheel = rule(implementation = _mock_installed_wheel_impl)

def _test_pycross_cc_pkg_config_versioned_library(name):
    util.helper_target(_mock_installed_wheel, name = name + "_wheel")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_libcudart",
        wheel_library = name + "_wheel",
        shared_library = "nvidia/cuda_runtime/lib/libcudart.so.12",
    )
    util.helper_target(
        pycross_cc_pkg_config,
        name = name + "_subject",
        dep = name + "_libcudart",
        lib_name = "cudart",
        version = "12.0",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pycross_cc_pkg_config_versioned_library_impl)

def _test_pycross_cc_pkg_config_versioned_library_impl(env, target):
    content = env.expect.that_target(target).action_generating("tests/analysis/cudart.pc").content()

    # `-lcudart` wouldn't find a file named only libcudart.so.12, so it's linked by path.
    content.contains("_libcudart/shared_library/libcudart.so.12")
    raw = [a.content for a in target.actions if a.mnemonic == "FileWrite"][0]
    env.expect.that_bool("-lcudart" in raw).equals(False)

def pycross_cc_pkg_config_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_cc_pkg_config_versioned_library,
            _test_pycross_cc_pkg_config,
            _test_pycross_cc_pkg_config_libprefix,
            _test_pycross_cc_pkg_config_pic_static_library,
        ],
    )
