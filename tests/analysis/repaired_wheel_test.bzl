"""Tests for pycross_repaired_wheel."""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:repaired_wheel.bzl", "pycross_repaired_wheel")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:wheel_cc_import.bzl", "pycross_wheel_cc_import")

def _mock_wheel_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_whldir")
    ctx.actions.run_shell(
        outputs = [out],
        command = "mkdir -p %s && touch %s/dummy-1.0-py3-none-any.whl" % (out.path, out.path),
    )
    return [
        DefaultInfo(files = depset([out])),
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
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)
    env.expect.that_str(wheel_dir.basename).contains(".whldir")

    # The action generating the wheel_dir should be RepairWheel
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossRepairWheel")

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
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)

def _test_repaired_wheel_with_exclude_globs(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(
        pycross_repaired_wheel,
        name = name + "_subject",
        wheel = name + "_wheel",
        repair_exclude_globs = ["libtorch*.so", "libc10*.dylib"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_repaired_wheel_with_exclude_globs_impl)

# buildifier: disable=unused-variable
def _test_repaired_wheel_with_exclude_globs_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossRepairWheel")
    action.argv().contains_at_least([
        "--exclude",
        "libtorch*.so",
        "--exclude",
        "libc10*.dylib",
    ]).in_order()

def _mock_installed_wheel_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(outputs = [out], command = "mkdir -p $1", arguments = [out.path])
    return [DefaultInfo(files = depset([out])), PycrossExtractedWheelInfo(site_packages = out)]

_mock_installed_wheel = rule(implementation = _mock_installed_wheel_impl)

def _test_repaired_wheel_excludes_wheel_libraries(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(_mock_installed_wheel, name = name + "_torch")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_libtorch",
        wheel_library = name + "_torch",
        shared_library = "torch/lib/libtorch.so",
    )
    util.helper_target(
        pycross_repaired_wheel,
        name = name + "_subject",
        wheel = name + "_wheel",
        native_deps = [name + "_libtorch"],
        repair_exclude_globs = ["libc10*.so"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_repaired_wheel_excludes_wheel_libraries_impl)

def _test_repaired_wheel_excludes_wheel_libraries_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.argv().contains_at_least(["--exclude", "libc10*.so", "--exclude", "libtorch.so"]).in_order()
    action.argv().contains_predicate(matching.str_endswith("_libtorch/shared_library"))
    action.inputs().contains_predicate(matching.file_basename_equals("libtorch.so"))

def _test_repaired_wheel_excludes_nested_wheel_libraries(name):
    # libtorch depends on libc10 through a cc_library, and the build wraps libtorch too.
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(_mock_installed_wheel, name = name + "_torch")
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_libc10",
        wheel_library = name + "_torch",
        shared_library = "torch/lib/libc10.so",
    )
    util.helper_target(cc_library, name = name + "_c10_wrapped", deps = [name + "_libc10"])
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_libtorch",
        wheel_library = name + "_torch",
        shared_library = "torch/lib/libtorch.so",
        deps = [name + "_c10_wrapped"],
    )
    util.helper_target(cc_library, name = name + "_torch_wrapped", deps = [name + "_libtorch"])
    util.helper_target(
        pycross_repaired_wheel,
        name = name + "_subject",
        wheel = name + "_wheel",
        native_deps = [name + "_torch_wrapped"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_repaired_wheel_excludes_nested_wheel_libraries_impl)

def _test_repaired_wheel_excludes_nested_wheel_libraries_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.argv().contains_at_least(["--exclude", "libtorch.so"]).in_order()
    action.argv().contains_at_least(["--exclude", "libc10.so"]).in_order()

def repaired_wheel_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_repaired_wheel_basic,
            _test_repaired_wheel_with_native_deps,
            _test_repaired_wheel_with_exclude_globs,
            _test_repaired_wheel_excludes_wheel_libraries,
            _test_repaired_wheel_excludes_nested_wheel_libraries,
        ],
    )
