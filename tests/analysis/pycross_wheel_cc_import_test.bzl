"""Tests for pycross_wheel_cc_import and the pycross_wheel_headers macro."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossWheelSharedLibraryInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:wheel_cc_import.bzl", "pycross_wheel_cc_import", "pycross_wheel_headers")

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

    pycross_wheel_headers(
        name = name + "_subject",
        wheel_library = name + "_wheel",
        include_dir = "numpy/_core/include",
        make_variable = "NUMPY_INCLUDE",
        tags = ["manual"],
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
    pycross_wheel_headers(
        name = name + "_subject",
        wheel_library = name + "_wheel",
        include_dir = "numpy/_core/include",
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_headers_no_make_variable_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_headers_no_make_variable_impl(env, target):
    env.expect.that_bool(platform_common.TemplateVariableInfo in target).equals(False)
    env.expect.that_collection(target[CcInfo].linking_context.linker_inputs.to_list()).has_size(0)
    env.expect.that_collection(target[PycrossWheelSharedLibraryInfo].shared_libraries.to_list()).has_size(0)

def _test_cc_import_shared_library(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(_mock_wheel, name = name + "_other_wheel")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_dep",
        wheel_library = name + "_other_wheel",
        shared_library = "other/lib/libbar.so.2",
    )
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_subject",
        wheel_library = name + "_wheel",
        includes = ["torch/include", "torch/include/api"],
        shared_library = "torch/lib/./libtorch.so",
        linkopts = ["-lm"],
        deps = [name + "_dep"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_cc_import_shared_library_impl)

def _test_cc_import_shared_library_impl(env, target):
    cc_info = target[CcInfo]
    includes = cc_info.compilation_context.includes.to_list()
    env.expect.that_bool(any([inc.endswith("_wheel_dir/site-packages/torch/include") for inc in includes])).equals(True)
    env.expect.that_bool(any([inc.endswith("site-packages/torch/include/api") for inc in includes])).equals(True)

    libs = []
    flags = []
    for linker_input in cc_info.linking_context.linker_inputs.to_list():
        flags.extend(linker_input.user_link_flags)
        for lib in linker_input.libraries:
            dynamic = lib.resolved_symlink_dynamic_library or lib.dynamic_library
            libs.append(dynamic.basename)
    env.expect.that_collection(libs).contains_exactly(["libtorch.so", "libbar.so.2"])
    env.expect.that_collection(flags).contains("-lm")

    shared = [f.basename for f in target[PycrossWheelSharedLibraryInfo].shared_libraries.to_list()]
    env.expect.that_collection(shared).contains_exactly(["libtorch.so", "libbar.so.2"])

    copy = env.expect.that_target(target).action_named("PycrossWheelLibrary")
    copy.argv().contains("torch/lib/libtorch.so")

def _test_cc_import_static_library(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_subject",
        wheel_library = name + "_wheel",
        static_library = "numpy/_core/lib/libnpymath.a",
        alwayslink = True,
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_cc_import_static_library_impl)

def _test_cc_import_static_library_impl(env, target):
    libs = target[CcInfo].linking_context.linker_inputs.to_list()[0].libraries
    env.expect.that_collection(libs).has_size(1)
    env.expect.that_str(libs[0].static_library.basename).equals("libnpymath.a")
    env.expect.that_bool(libs[0].alwayslink).equals(True)

    # A static library is linked in, so it isn't a runtime library from another wheel.
    env.expect.that_collection(target[PycrossWheelSharedLibraryInfo].shared_libraries.to_list()).has_size(0)

def _test_cc_import_rejects_paths_outside_wheel(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_subject",
        wheel_library = name + "_wheel",
        shared_library = "torch/../../libtorch.so",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_cc_import_rejects_paths_outside_wheel_impl,
        expect_failure = True,
    )

def _test_cc_import_rejects_paths_outside_wheel_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*must be a path inside the wheel's site-packages*"),
    )

def _test_cc_import_make_variable_needs_one_include(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_subject",
        wheel_library = name + "_wheel",
        includes = ["a", "b"],
        make_variable = "INC",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_cc_import_make_variable_needs_one_include_impl,
        expect_failure = True,
    )

def _test_cc_import_make_variable_needs_one_include_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*make_variable requires exactly one entry in includes*"),
    )

def pycross_wheel_cc_import_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_wheel_headers_basic,
            _test_pycross_wheel_headers_no_make_variable,
            _test_cc_import_shared_library,
            _test_cc_import_static_library,
            _test_cc_import_rejects_paths_outside_wheel,
            _test_cc_import_make_variable_needs_one_include,
        ],
    )
