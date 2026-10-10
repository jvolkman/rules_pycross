"""Module docstring for tests."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo", "PycrossUnsupportedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private:proxy.bzl", "pycross_library_proxy")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_dir.bzl", "pycross_wheel_dir")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_library.bzl", "pycross_wheel_library")

def _test_pycross_wheel_library_basic(name):
    # Dummy wheel file
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )

    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "Foo-Bar",
        package_version = "1.0",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_library_basic_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_library_basic_impl(env, target):
    # Check that it returns PycrossExtractedWheelInfo
    env.expect.that_target(target).has_provider(PycrossExtractedWheelInfo)

    extracted_info = target[PycrossExtractedWheelInfo]

    # Assert site_packages is a TreeArtifact. We can check if it's a directory.
    env.expect.that_bool(extracted_info.site_packages.is_directory).equals(True)

    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    action.argv().contains_at_least(["--dist-info-dir", "foo_bar-1.0.dist-info"])

    # Check that it returns PycrossPackageInfo
    env.expect.that_target(target).has_provider(PycrossPackageInfo)

    # Assert package details
    if PycrossPackageInfo in target:
        env.expect.that_str(target[PycrossPackageInfo].package_name).equals("Foo-Bar")
        env.expect.that_str(target[PycrossPackageInfo].package_version).equals("1.0")

def _test_pycross_wheel_library_no_package_name(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_library_no_package_name_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_library_no_package_name_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossExtractedWheelInfo)

    extracted_info = target[PycrossExtractedWheelInfo]
    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    env.expect.that_bool("--dist-info-dir" in action.actual.argv).equals(False)

    # PycrossPackageInfo should not be present
    env.expect.that_bool(PycrossPackageInfo in target).equals(False)

def _test_pycross_wheel_library_no_match_deferred(name):
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = "//pycross/private:no_match_error",
        package_name = "unsupported_pkg",
        package_version = "1.0",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_pycross_wheel_library_no_match_deferred_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_library_no_match_deferred_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossExtractedWheelInfo)
    env.expect.that_target(target).has_provider(PycrossPackageInfo)

    extracted_info = target[PycrossExtractedWheelInfo]
    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    action.mnemonic().equals("PycrossUnsupportedWheel")
    action.env().contains_exactly({
        "PYCROSS_ERROR": "No compatible wheel is available for unsupported_pkg@1.0 in the selected target environment.",
    })

def _test_pycross_wheel_dir_no_match_deferred(name):
    util.helper_target(
        pycross_wheel_dir,
        name = name + "_subject",
        src = "//pycross/private:no_match_error",
        whldir_name = "unsupported_pkg-1.0.whldir",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_pycross_wheel_dir_no_match_deferred_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_wheel_dir_no_match_deferred_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossUnsupportedWheel")

    # Generated wheel_dir targets are named by package key, which the message uses.
    action.env().contains_exactly({
        "PYCROSS_ERROR": "No compatible wheel is available for {} in the selected target environment.".format(target.label.name),
    })

    # The marker is forwarded so downstream rules can report the package too.
    env.expect.that_target(target).has_provider(PycrossUnsupportedWheelInfo)

# ── no_match_error compatibility probe ──────────────────────────────
#
# An incompatible target cannot be the subject of an analysis test (the test
# itself becomes incompatible and is skipped). Instead, mirror the scenario from
# issue #299: an aspect whose implicit attribute points at no_match_error. Bazel
# does not propagate incompatibility through aspect attributes; the aspect just
# sees a stub target without the rule's providers. So the presence of
# PycrossUnsupportedWheelInfo tells us whether no_match_error was analyzed
# (compatible) or not (incompatible).

_NoMatchProbeInfo = provider(
    doc = "Records what an aspect observed about //pycross/private:no_match_error.",
    fields = {"analyzed": "bool: whether no_match_error was analyzed (i.e. compatible)."},
)

def _no_match_probe_aspect_impl(target, ctx):  # buildifier: disable=unused-variable
    return [_NoMatchProbeInfo(
        analyzed = PycrossUnsupportedWheelInfo in ctx.attr._no_match_error,
    )]

_no_match_probe_aspect = aspect(
    implementation = _no_match_probe_aspect_impl,
    attrs = {
        "_no_match_error": attr.label(default = Label("//pycross/private:no_match_error")),
    },
)

def _no_match_probe_subject(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])

def _test_no_match_error_incompatible_by_default(name):
    _no_match_probe_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        extra_target_under_test_aspects = [_no_match_probe_aspect],
        impl = _test_no_match_error_incompatible_by_default_impl,
    )

def _test_no_match_error_incompatible_by_default_impl(env, target):
    env.expect.that_bool(target[_NoMatchProbeInfo].analyzed).equals(False)

def _test_no_match_error_compatible_when_deferred(name):
    _no_match_probe_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        extra_target_under_test_aspects = [_no_match_probe_aspect],
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_no_match_error_compatible_when_deferred_impl,
    )

def _test_no_match_error_compatible_when_deferred_impl(env, target):
    env.expect.that_bool(target[_NoMatchProbeInfo].analyzed).equals(True)

def _test_pycross_library_proxy_no_match_deferred(name):
    util.helper_target(
        pycross_library_proxy,
        name = name + "_proxy",
        actual = "//pycross/private:no_match_error",
    )
    util.helper_target(
        pycross_library_proxy,
        name = name + "_subject",
        actual = ":" + name + "_proxy",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_pycross_library_proxy_no_match_deferred_impl,
    )

# buildifier: disable=unused-variable
def _test_pycross_library_proxy_no_match_deferred_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossUnsupportedWheelInfo)

    # The failing .whl must be present in default_runfiles so a downstream
    # py_binary / py_test depending on a fork-select proxy whose branches all
    # fall through to no_match_error triggers the deferred failure action at
    # build time instead of succeeding with an empty environment.
    runfile_names = [f.basename for f in target[DefaultInfo].default_runfiles.files.to_list()]
    env.expect.that_collection(runfile_names).contains("no_match_error.whl")

def _define_precompile_subject(name, **kwargs):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "test",
        package_version = "1.0",
        **kwargs
    )

def _assert_precompile_disabled_impl(env, target):
    extracted_info = target[PycrossExtractedWheelInfo]
    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    env.expect.that_bool("--compile-python" in action.actual.argv).equals(False)
    env.expect.that_bool("--compile-invalidation-mode" in action.actual.argv).equals(False)
    env.expect.that_bool("--compile-optimize" in action.actual.argv).equals(False)

def _assert_precompile_enabled_checked_opt0_impl(env, target):
    extracted_info = target[PycrossExtractedWheelInfo]
    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    env.expect.that_bool("--compile-python" in action.actual.argv).equals(True)
    action.argv().contains_at_least([
        "--compile-invalidation-mode",
        "checked_hash",
        "--compile-optimize",
        "0",
    ])
    input_paths = [f.short_path for f in action.actual.inputs.to_list()]
    has_python_bin = any(["/bin/python" in p for p in input_paths])
    has_stdlib_os = any(["/lib/python3." in p and p.endswith("/os.py") for p in input_paths])
    env.expect.that_bool(has_python_bin).equals(True)
    env.expect.that_bool(has_stdlib_os).equals(True)
    excluded_interp_inputs = [
        p
        for p in input_paths
        if "/python_" in p and (
            "/site-packages/" in p or
            "/tcl" in p or
            "/tk" in p or
            "/Tix" in p or
            "/include/" in p or
            "/idlelib/" in p or
            "/lib2to3/" in p or
            "/distutils/" in p or
            "/turtledemo/" in p or
            "/tkinter/" in p
        )
    ]
    env.expect.that_collection(excluded_interp_inputs).contains_exactly([])

def _assert_precompile_enabled_unchecked_opt0_impl(env, target):
    extracted_info = target[PycrossExtractedWheelInfo]
    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    env.expect.that_bool("--compile-python" in action.actual.argv).equals(True)
    action.argv().contains_at_least([
        "--compile-invalidation-mode",
        "unchecked_hash",
        "--compile-optimize",
        "0",
    ])

def _test_pycross_wheel_library_precompile_auto(name):
    _define_precompile_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "auto",
        },
        impl = _assert_precompile_disabled_impl,
    )

def _test_pycross_wheel_library_precompile_disabled(name):
    _define_precompile_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "disabled",
        },
        impl = _assert_precompile_disabled_impl,
    )

def _test_pycross_wheel_library_precompile_force_disabled(name):
    _define_precompile_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "force_disabled",
        },
        impl = _assert_precompile_disabled_impl,
    )

def _test_pycross_wheel_library_precompile_enabled_checked_hash(name):
    _define_precompile_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "enabled",
        },
        impl = _assert_precompile_enabled_checked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_force_enabled_opt(name):
    _define_precompile_subject(name)
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "force_enabled",
            "//command_line_option:compilation_mode": "opt",
        },
        impl = _assert_precompile_enabled_unchecked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_attr_enabled_flag_auto(name):
    _define_precompile_subject(name, precompile = "enabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "auto",
        },
        impl = _assert_precompile_enabled_checked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_attr_enabled_flag_disabled(name):
    _define_precompile_subject(name, precompile = "enabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "disabled",
        },
        impl = _assert_precompile_enabled_checked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_attr_enabled_flag_force_disabled(name):
    _define_precompile_subject(name, precompile = "enabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "force_disabled",
        },
        impl = _assert_precompile_disabled_impl,
    )

def _test_pycross_wheel_library_precompile_attr_disabled_flag_enabled(name):
    _define_precompile_subject(name, precompile = "disabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "enabled",
        },
        impl = _assert_precompile_disabled_impl,
    )

def _test_pycross_wheel_library_precompile_attr_disabled_flag_force_enabled(name):
    _define_precompile_subject(name, precompile = "disabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "force_enabled",
        },
        impl = _assert_precompile_enabled_checked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_invalidation_mode_explicit(name):
    _define_precompile_subject(
        name,
        precompile = "enabled",
        precompile_invalidation_mode = "checked_hash",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:compilation_mode": "opt",
        },
        impl = _assert_precompile_enabled_checked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_invalidation_mode_unchecked_explicit(name):
    _define_precompile_subject(
        name,
        precompile = "enabled",
        precompile_invalidation_mode = "unchecked_hash",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:compilation_mode": "fastbuild",
        },
        impl = _assert_precompile_enabled_unchecked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_optimize_level(name):
    _define_precompile_subject(
        name,
        precompile = "enabled",
        precompile_optimize_level = 2,
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_library_precompile_optimize_level_impl,
    )

def _test_pycross_wheel_library_precompile_optimize_level_impl(env, target):
    extracted_info = target[PycrossExtractedWheelInfo]
    action = env.expect.that_target(target).action_generating(extracted_info.site_packages.short_path)
    action.argv().contains_at_least(["--compile-optimize", "2"])

def _test_pycross_wheel_library_precompile_missing_toolchain_skipped(name):
    _define_precompile_subject(name, precompile = "enabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:precompile")): "enabled",
            str(Label("@rules_python//python/config_settings:python_version")): "3.10",
        },
        impl = _assert_precompile_disabled_impl,
    )

def pycross_wheel_library_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_wheel_library_basic,
            _test_pycross_wheel_library_no_package_name,
            _test_pycross_wheel_library_no_match_deferred,
            _test_pycross_wheel_dir_no_match_deferred,
            _test_no_match_error_incompatible_by_default,
            _test_no_match_error_compatible_when_deferred,
            _test_pycross_library_proxy_no_match_deferred,
            _test_pycross_wheel_library_precompile_auto,
            _test_pycross_wheel_library_precompile_disabled,
            _test_pycross_wheel_library_precompile_force_disabled,
            _test_pycross_wheel_library_precompile_enabled_checked_hash,
            _test_pycross_wheel_library_precompile_force_enabled_opt,
            _test_pycross_wheel_library_precompile_attr_enabled_flag_auto,
            _test_pycross_wheel_library_precompile_attr_enabled_flag_disabled,
            _test_pycross_wheel_library_precompile_attr_enabled_flag_force_disabled,
            _test_pycross_wheel_library_precompile_attr_disabled_flag_enabled,
            _test_pycross_wheel_library_precompile_attr_disabled_flag_force_enabled,
            _test_pycross_wheel_library_precompile_invalidation_mode_explicit,
            _test_pycross_wheel_library_precompile_invalidation_mode_unchecked_explicit,
            _test_pycross_wheel_library_precompile_optimize_level,
            _test_pycross_wheel_library_precompile_missing_toolchain_skipped,
        ],
    )
