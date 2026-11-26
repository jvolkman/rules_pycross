"""Module docstring for tests."""

load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo", "PycrossUnsupportedWheelInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private:proxy.bzl", "pycross_file_proxy", "pycross_library_proxy")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_resolver.bzl", "pycross_no_variant_selected")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_dir.bzl", "pycross_wheel_dir")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_library.bzl", "pycross_wheel_library", "pycross_wheel_metadata")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_zipimport_library.bzl", "pycross_wheel_zipimport_library")

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
    env.expect.that_target(target).has_provider(PycrossUnsupportedWheelInfo)

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

def _test_pycross_wheel_dir_basic(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_dir,
        name = name + "_subject",
        src = name + "_wheel",
        whldir_name = "test-1.0.whldir",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_dir_basic_impl,
    )

def _test_pycross_wheel_dir_basic_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossWheelDir")
    action.argv().contains("wrap-wheel")
    action.argv().contains(wheel_dir.path)

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

    # The failing output must be present in default_runfiles so a downstream
    # py_binary / py_test depending on a fork-select proxy whose branches all
    # fall through to no_match_error triggers the deferred failure action at
    # build time instead of succeeding with an empty environment.
    runfile_names = [f.basename for f in target[DefaultInfo].default_runfiles.files.to_list()]
    env.expect.that_bool(any([n.startswith("_unsupported_") and n.endswith(".out") for n in runfile_names])).equals(True)

    # The inner _proxy already contextualized the sentinel, so _subject forwards it
    # without registering a duplicate PycrossUnsupportedPackage action.
    env.expect.that_str(target[PycrossUnsupportedWheelInfo].package).contains("_proxy")
    actions = [a for a in target.actions if a.mnemonic == "PycrossUnsupportedPackage"]
    env.expect.that_int(len(actions)).equals(0)

def _test_pycross_file_proxy_preserves_wheel_dir_unsupported(name):
    util.helper_target(
        pycross_wheel_dir,
        name = name + "_whldir",
        src = "//pycross/private:no_match_error",
        whldir_name = name + ".whldir",
    )
    util.helper_target(
        pycross_file_proxy,
        name = name + "_subject",
        actual = ":" + name + "_whldir",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_pycross_file_proxy_preserves_wheel_dir_unsupported_impl,
    )

def _test_pycross_file_proxy_preserves_wheel_dir_unsupported_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossUnsupportedWheelInfo)
    env.expect.that_str(target[PycrossUnsupportedWheelInfo].package).contains("_whldir")
    out_files = target[DefaultInfo].files.to_list()
    env.expect.that_int(len(out_files)).equals(1)
    env.expect.that_bool(out_files[0].is_directory).equals(True)
    env.expect.that_int(len([a for a in target.actions if a.mnemonic == "PycrossUnsupportedPackage"])).equals(0)

def _test_pycross_library_proxy_preserves_wheel_library_unsupported(name):
    util.helper_target(
        pycross_wheel_library,
        name = name + "_lib",
        wheel = "//pycross/private:no_match_error",
    )
    util.helper_target(
        pycross_library_proxy,
        name = name + "_subject",
        actual = ":" + name + "_lib",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_pycross_library_proxy_preserves_wheel_library_unsupported_impl,
    )

def _test_pycross_library_proxy_preserves_wheel_library_unsupported_impl(env, target):
    env.expect.that_target(target).has_provider(PycrossUnsupportedWheelInfo)
    env.expect.that_target(target).has_provider(PycrossExtractedWheelInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)
    env.expect.that_str(target[PycrossUnsupportedWheelInfo].package).contains("_lib")
    env.expect.that_int(len([a for a in target.actions if a.mnemonic == "PycrossUnsupportedPackage"])).equals(0)

def _test_no_variant_selected_fails_by_default(name):
    util.helper_target(
        pycross_no_variant_selected,
        name = name + "_subject",
        message = "No uv conflict variant selected. Set one of the _variants flags on your pycross repo: extra_a, extra_b",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        expect_failure = True,
        impl = _test_no_variant_selected_fails_by_default_impl,
    )

# buildifier: disable=unused-variable
def _test_no_variant_selected_fails_by_default_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("No uv conflict variant selected. Set one of"),
    )

def _test_no_variant_selected_deferred(name):
    util.helper_target(
        pycross_no_variant_selected,
        name = name + "_subject",
        message = "No uv conflict variant selected. Set one of the _variants flags on your pycross repo: extra_a, extra_b",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_no_variant_selected_deferred_impl,
    )

# buildifier: disable=unused-variable
def _test_no_variant_selected_deferred_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    env.expect.that_bool(PycrossUnsupportedWheelInfo in target).equals(False)

    whl = target[DefaultInfo].files.to_list()[0]
    action = env.expect.that_target(target).action_generating(whl.short_path)
    action.mnemonic().equals("PycrossNoVariantSelected")
    action.env().contains_exactly({
        "PYCROSS_ERROR": "No uv conflict variant selected. Set one of the _variants flags on your pycross repo: extra_a, extra_b",
    })

    runfile_names = [f.basename for f in target[DefaultInfo].default_runfiles.files.to_list()]
    env.expect.that_collection(runfile_names).contains(whl.basename)

def _test_no_variant_selected_long_name_deferred(name):
    long_target = name + "_" + "_".join(["extra_long_package_name_variant_%d" % i for i in range(10)])
    util.helper_target(
        pycross_no_variant_selected,
        name = long_target,
        message = "No uv conflict variant selected",
    )
    analysis_test(
        name = name,
        target = long_target,
        config_settings = {
            str(Label("//pycross/settings:unavailable_package_mode")): "fail_at_execution",
        },
        impl = _test_no_variant_selected_long_name_deferred_impl,
    )

# buildifier: disable=unused-variable
def _test_no_variant_selected_long_name_deferred_impl(env, target):
    whl = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(len(whl.basename) < 64).equals(True)
    env.expect.that_str(whl.basename).contains("_no_variant_")
    env.expect.that_bool(whl.basename.endswith(".whl")).equals(True)

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

def _test_pycross_wheel_library_precompile_invalidation_mode_flag(name):
    _define_precompile_subject(name, precompile = "enabled")
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:compilation_mode": "fastbuild",
            str(Label("//pycross/settings:precompile_invalidation_mode")): "unchecked_hash",
        },
        impl = _assert_precompile_enabled_unchecked_opt0_impl,
    )

def _test_pycross_wheel_library_precompile_invalidation_mode_attr_overrides_flag(name):
    _define_precompile_subject(
        name,
        precompile = "enabled",
        precompile_invalidation_mode = "checked_hash",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:compilation_mode": "fastbuild",
            str(Label("//pycross/settings:precompile_invalidation_mode")): "unchecked_hash",
        },
        impl = _assert_precompile_enabled_checked_opt0_impl,
    )

def _test_pycross_wheel_zipimport_library_file_uses_symlink(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_zipimport_library,
        name = name + "_subject",
        wheel = name + "_wheel",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_zipimport_library_file_uses_symlink_impl,
    )

def _test_pycross_wheel_zipimport_library_file_uses_symlink_impl(env, target):
    mnemonics = [a.mnemonic for a in target.actions]
    env.expect.that_collection(mnemonics).not_contains("PycrossLinkWheel")
    env.expect.that_collection(mnemonics).contains("Symlink")

def _test_pycross_wheel_zipimport_library_dir_uses_wheel_file_op(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_src",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_dir,
        name = name + "_wheel_dir",
        src = name + "_wheel_src",
        whldir_name = "test-1.0.whldir",
    )
    util.helper_target(
        pycross_wheel_zipimport_library,
        name = name + "_subject",
        wheel = name + "_wheel_dir",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pycross_wheel_zipimport_library_dir_uses_wheel_file_op_impl,
    )

def _test_pycross_wheel_zipimport_library_dir_uses_wheel_file_op_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossLinkWheel")
    action.argv().contains("unwrap-wheel")
    action.argv().contains_predicate(matching.str_endswith("test-1.0.whldir"))

def _test_pycross_wheel_library_precompile_single_file_pyc_symlinks(name):
    _define_precompile_subject(
        name,
        precompile = "enabled",
        precompile_optimize_level = 1,
        site_paths = ["six.py", "google/cloud/foo.py", "pkg"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:venvs_site_packages")): "yes",
        },
        impl = _test_pycross_wheel_library_precompile_single_file_pyc_symlinks_impl,
    )

def _test_pycross_wheel_library_precompile_single_file_pyc_symlinks_impl(env, target):
    venv_paths = [e.venv_path for e in target[PyInfo].venv_symlinks.to_list()]
    env.expect.that_collection(venv_paths).contains_at_least([
        "six.py",
        "google/cloud/foo.py",
        "pkg",
    ])
    env.expect.that_collection(venv_paths).contains_predicate(
        matching.str_matches("__pycache__/six.cpython-*.opt-1.pyc"),
    )
    env.expect.that_collection(venv_paths).contains_predicate(
        matching.str_matches("google/cloud/__pycache__/foo.cpython-*.opt-1.pyc"),
    )
    env.expect.that_collection(venv_paths).not_contains_predicate(
        matching.str_matches("*pkg*.pyc"),
    )

def _test_pycross_wheel_library_bin_only_venv_symlinks(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "mytool",
        package_version = "1.0",
        bin_paths = ["mytool"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:venvs_site_packages")): "yes",
        },
        impl = _test_pycross_wheel_library_bin_only_venv_symlinks_impl,
    )

def _test_pycross_wheel_library_bin_only_venv_symlinks_impl(env, target):
    venv_paths = [e.venv_path for e in target[PyInfo].venv_symlinks.to_list()]
    env.expect.that_collection(venv_paths).contains("mytool")
    env.expect.that_collection(venv_paths).not_contains("mytool-1.0.dist-info")

    # Empty site_paths still keeps site-packages on sys.path for build-time generated modules.
    env.expect.that_collection(target[PyInfo].imports.to_list()).contains_predicate(
        matching.str_endswith("/site-packages"),
    )

def _test_pycross_wheel_library_sdist_advisory_site_paths(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_file",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_metadata,
        name = name + "_wheel",
        wheel = name + "_wheel_file",
        site_paths = ["noxfile.py"],
        site_paths_exact = False,
        bin_paths = ["mytool"],
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "my_sdist",
        package_version = "1.0",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:venvs_site_packages")): "yes",
        },
        impl = _test_pycross_wheel_library_sdist_advisory_site_paths_impl,
    )

def _test_pycross_wheel_library_sdist_advisory_site_paths_impl(env, target):
    # Advisory sdist site_paths must NOT become venv LIB symlinks or drop [imp].
    venv_paths = [e.venv_path for e in target[PyInfo].venv_symlinks.to_list()]
    env.expect.that_collection(venv_paths).contains("mytool")
    env.expect.that_collection(venv_paths).not_contains("noxfile.py")
    env.expect.that_collection(venv_paths).not_contains("my_sdist-1.0.dist-info")
    env.expect.that_collection(target[PyInfo].imports.to_list()).contains_predicate(
        matching.str_endswith("/site-packages"),
    )

    # Full guessed site_paths remain on PycrossPackageInfo for modules_mapping.
    env.expect.that_collection(target[PycrossPackageInfo].site_paths).contains_exactly(["noxfile.py"])
    env.expect.that_bool(target[PycrossPackageInfo].site_paths_exact).equals(False)

    # Advisory guesses are not verified by --expected-site-path.
    install_action = env.expect.that_target(target).action_named("PycrossWheelInstall")
    install_action.argv().not_contains("--expected-site-path")

def _test_pycross_wheel_library_sdist_annotated_site_paths(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_file",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_metadata,
        name = name + "_wheel",
        wheel = name + "_wheel_file",
        site_paths = ["noxfile.py"],
        site_paths_exact = False,
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "my_sdist",
        package_version = "1.0",
        site_paths = ["real_pkg"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:venvs_site_packages")): "yes",
        },
        impl = _test_pycross_wheel_library_sdist_annotated_site_paths_impl,
    )

def _test_pycross_wheel_library_sdist_annotated_site_paths_impl(env, target):
    venv_paths = [e.venv_path for e in target[PyInfo].venv_symlinks.to_list()]
    env.expect.that_collection(venv_paths).contains_exactly(["real_pkg", "my_sdist-1.0.dist-info"])
    env.expect.that_collection(target[PyInfo].imports.to_list()).contains_exactly([])
    env.expect.that_bool(target[PycrossPackageInfo].site_paths_exact).equals(True)

    install_action = env.expect.that_target(target).action_named("PycrossWheelInstall")
    install_action.argv().contains_at_least(["--expected-site-path", "real_pkg"])

def _test_pycross_wheel_library_venvs_disabled_skips_expected_site_paths(name):
    util.helper_target(
        native.filegroup,
        name = name + "_wheel_file",
        srcs = ["test-1.0-py3-none-any.whl"],
    )
    util.helper_target(
        pycross_wheel_metadata,
        name = name + "_wheel",
        wheel = name + "_wheel_file",
        site_paths = ["real_pkg"],
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_subject",
        wheel = name + "_wheel",
        package_name = "my_pkg",
        package_version = "1.0",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("@rules_python//python/config_settings:venvs_site_packages")): "no",
        },
        impl = _test_pycross_wheel_library_venvs_disabled_skips_expected_site_paths_impl,
    )

def _test_pycross_wheel_library_venvs_disabled_skips_expected_site_paths_impl(env, target):
    install_action = env.expect.that_target(target).action_named("PycrossWheelInstall")
    install_action.argv().not_contains("--expected-site-path")

def pycross_wheel_library_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pycross_wheel_library_basic,
            _test_pycross_wheel_library_no_package_name,
            _test_pycross_wheel_library_no_match_deferred,
            _test_pycross_wheel_dir_basic,
            _test_pycross_wheel_dir_no_match_deferred,
            _test_no_match_error_incompatible_by_default,
            _test_no_match_error_compatible_when_deferred,
            _test_pycross_library_proxy_no_match_deferred,
            _test_pycross_file_proxy_preserves_wheel_dir_unsupported,
            _test_pycross_library_proxy_preserves_wheel_library_unsupported,
            _test_no_variant_selected_fails_by_default,
            _test_no_variant_selected_deferred,
            _test_no_variant_selected_long_name_deferred,
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
            _test_pycross_wheel_library_precompile_invalidation_mode_flag,
            _test_pycross_wheel_library_precompile_invalidation_mode_attr_overrides_flag,
            _test_pycross_wheel_zipimport_library_file_uses_symlink,
            _test_pycross_wheel_zipimport_library_dir_uses_wheel_file_op,
            _test_pycross_wheel_library_precompile_single_file_pyc_symlinks,
            _test_pycross_wheel_library_bin_only_venv_symlinks,
            _test_pycross_wheel_library_sdist_advisory_site_paths,
            _test_pycross_wheel_library_sdist_annotated_site_paths,
            _test_pycross_wheel_library_venvs_disabled_skips_expected_site_paths,
        ],
    )
