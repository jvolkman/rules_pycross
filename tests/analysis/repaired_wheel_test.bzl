"""Tests for pycross_repaired_wheel."""

load("@rules_cc//cc:defs.bzl", "cc_import", "cc_library")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:repaired_wheel.bzl", "pycross_repaired_wheel")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:wheel_cc_import.bzl", "pycross_wheel_cc_import")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")

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

def _mock_file_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.filename)
    ctx.actions.write(out, "")
    return [DefaultInfo(files = depset([out]))]

_mock_file = rule(
    implementation = _mock_file_impl,
    attrs = {"filename": attr.string(mandatory = True)},
)

def _test_repaired_wheel_skips_static_libs(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(_mock_file, name = name + "_static_a", filename = name + "_libs/libstatic.a")
    util.helper_target(_mock_file, name = name + "_dyn_so", filename = name + "_libs/libdyn.so")
    util.helper_target(_mock_file, name = name + "_iface_lib", filename = name + "_libs/libdyn.ifso")
    util.helper_target(
        cc_import,
        name = name + "_mixed_cc",
        static_library = name + "_static_a",
        shared_library = name + "_dyn_so",
        interface_library = name + "_iface_lib",
    )
    util.helper_target(
        pycross_repaired_wheel,
        name = name + "_subject",
        wheel = name + "_wheel",
        native_deps = [name + "_mixed_cc"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_repaired_wheel_skips_static_libs_impl,
    )

def _test_repaired_wheel_skips_static_libs_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossRepairWheel")
    action.inputs().contains_predicate(matching.file_basename_equals("libdyn.so"))
    action.inputs().not_contains_predicate(matching.file_basename_equals("libstatic.a"))
    action.inputs().not_contains_predicate(matching.file_basename_equals("libdyn.ifso"))
    action.argv().contains_predicate(matching.str_endswith("_libs"))

def _mock_repair_dep_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + "/repairwheel.py")
    ctx.actions.write(out, "")
    return [
        DefaultInfo(files = depset([out])),
        PyInfo(
            transitive_sources = depset([out]),
            imports = depset([ctx.workspace_name + "/custom/repair_pkg", "ext_repo/site-packages"]),
        ),
    ]

_mock_repair_dep = rule(
    implementation = _mock_repair_dep_impl,
    provides = [DefaultInfo, PyInfo],
)

def _mock_repair_with_deps_impl(ctx):
    res = register_repair_action(
        ctx,
        input_wheel_dir = ctx.files.wheel[0],
        repair_tool = ctx.executable._repair_tool,
        repair_deps = ctx.attr.repair_deps,
    )
    return [DefaultInfo(files = depset([res.wheel_dir]))]

_mock_repair_with_deps = rule(
    implementation = _mock_repair_with_deps_impl,
    attrs = {
        "wheel": attr.label(mandatory = True, allow_files = True),
        "repair_deps": attr.label_list(providers = [PyInfo]),
        "_repair_tool": attr.label(
            default = Label("//pycross/private/build/tools:repair_wheel_hook"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def _test_repair_action_resolves_imports(name):
    util.helper_target(_mock_wheel, name = name + "_wheel")
    util.helper_target(_mock_repair_dep, name = name + "_dep")
    util.helper_target(
        _mock_repair_with_deps,
        name = name + "_subject",
        wheel = name + "_wheel",
        repair_deps = [name + "_dep"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_repair_action_resolves_imports_impl,
    )

def _test_repair_action_resolves_imports_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    action = [a for a in target.actions if a.mnemonic == "PycrossRepairWheel"][0]
    pp = action.env.get("REPAIRWHEEL_PYTHONPATH", "")
    parts = pp.split(":")
    env.expect.that_int(len(parts)).equals(2)
    env.expect.that_str(parts[0]).contains("/bin/custom/repair_pkg")
    env.expect.that_bool(parts[1].startswith("bazel-out/")).equals(True)
    env.expect.that_str(parts[1]).contains("ext_repo")
    env.expect.that_bool(parts[1].endswith("/site-packages")).equals(True)
    env.expect.that_bool(wheel_dir.is_directory).equals(True)

def repaired_wheel_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_repaired_wheel_basic,
            _test_repaired_wheel_with_native_deps,
            _test_repaired_wheel_with_exclude_globs,
            _test_repaired_wheel_excludes_wheel_libraries,
            _test_repaired_wheel_excludes_nested_wheel_libraries,
            _test_repaired_wheel_skips_static_libs,
            _test_repair_action_resolves_imports,
        ],
    )
