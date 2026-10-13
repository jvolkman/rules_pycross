"""Tests for pycross_exec_platform_transition and target-scoped settings."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")

_ObservedSettingsInfo = provider(
    doc = "Observed build settings.",
    fields = [
        "glibc_version",
        "macos_version",
        "musl_version",
        "pep508_implementation_name",
        "pep508_platform_python_implementation",
        "pep508_platform_release",
        "pep508_platform_version",
        "py_linux_libc",
    ],
)

_SETTING_ATTRS = {
    "_glibc_version": attr.label(default = "//pycross/settings:glibc_version"),
    "_macos_version": attr.label(default = "//pycross/settings:macos_version"),
    "_musl_version": attr.label(default = "//pycross/settings:musl_version"),
    "_pep508_implementation_name": attr.label(default = "//pycross/settings:pep508_implementation_name"),
    "_pep508_platform_python_implementation": attr.label(default = "//pycross/settings:pep508_platform_python_implementation"),
    "_pep508_platform_release": attr.label(default = "//pycross/settings:pep508_platform_release"),
    "_pep508_platform_version": attr.label(default = "//pycross/settings:pep508_platform_version"),
    "_py_linux_libc": attr.label(default = "@rules_python//python/config_settings:py_linux_libc"),
}

def _observe_settings(ctx):
    return _ObservedSettingsInfo(
        glibc_version = ctx.attr._glibc_version[BuildSettingInfo].value,
        macos_version = ctx.attr._macos_version[BuildSettingInfo].value,
        musl_version = ctx.attr._musl_version[BuildSettingInfo].value,
        pep508_implementation_name = ctx.attr._pep508_implementation_name[BuildSettingInfo].value,
        pep508_platform_python_implementation = ctx.attr._pep508_platform_python_implementation[BuildSettingInfo].value,
        pep508_platform_release = ctx.attr._pep508_platform_release[BuildSettingInfo].value,
        pep508_platform_version = ctx.attr._pep508_platform_version[BuildSettingInfo].value,
        py_linux_libc = ctx.attr._py_linux_libc[BuildSettingInfo].value,
    )

def _mock_dep_impl(ctx):
    return [
        DefaultInfo(),
        _observe_settings(ctx),
    ]

_mock_dep = rule(
    implementation = _mock_dep_impl,
    attrs = _SETTING_ATTRS,
)

_SubjectInfo = provider(
    doc = "Subject and dependency build settings.",
    fields = ["target_settings", "transitioned_settings", "exec_settings"],
)

def _mock_rule_impl(ctx):
    dep = ctx.attr.dep[0] if type(ctx.attr.dep) == "list" else ctx.attr.dep
    return [
        DefaultInfo(),
        _SubjectInfo(
            target_settings = _observe_settings(ctx),
            transitioned_settings = dep[_ObservedSettingsInfo],
            exec_settings = ctx.attr.exec_dep[_ObservedSettingsInfo] if ctx.attr.exec_dep else None,
        ),
    ]

_mock_rule = rule(
    implementation = _mock_rule_impl,
    attrs = {
        "dep": attr.label(cfg = pycross_exec_platform_transition),
        "exec_dep": attr.label(cfg = "exec"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | _SETTING_ATTRS,
)

def _test_transitions_basic(name):
    util.helper_target(_mock_dep, name = name + "_dep")
    util.helper_target(_mock_rule, name = name + "_subject", dep = name + "_dep")
    analysis_test(name = name, target = name + "_subject", impl = _test_transitions_basic_impl)

def _test_transitions_basic_impl(env, target):
    env.expect.that_target(target).has_provider(DefaultInfo)

def _test_transitions_resets_target_settings(name):
    util.helper_target(_mock_dep, name = name + "_dep")
    util.helper_target(
        _mock_rule,
        name = name + "_subject",
        dep = name + "_dep",
        exec_dep = name + "_dep",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            str(Label("//pycross/settings:glibc_version")): "2.17",
            str(Label("//pycross/settings:macos_version")): "12.0",
            str(Label("//pycross/settings:musl_version")): "1.1",
            str(Label("//pycross/settings:pep508_implementation_name")): "pypy",
            str(Label("//pycross/settings:pep508_platform_python_implementation")): "PyPy",
            str(Label("//pycross/settings:pep508_platform_release")): "5.15.0",
            str(Label("//pycross/settings:pep508_platform_version")): "#1 SMP",
            str(Label("@rules_python//python/config_settings:py_linux_libc")): "musl",
        },
        impl = _test_transitions_resets_target_settings_impl,
    )

def _test_transitions_resets_target_settings_impl(env, target):
    info = target[_SubjectInfo]

    # Target config sees the overridden values.
    env.expect.that_str(info.target_settings.glibc_version).equals("2.17")
    env.expect.that_str(info.target_settings.macos_version).equals("12.0")
    env.expect.that_str(info.target_settings.musl_version).equals("1.1")
    env.expect.that_str(info.target_settings.pep508_implementation_name).equals("pypy")
    env.expect.that_str(info.target_settings.pep508_platform_python_implementation).equals("PyPy")
    env.expect.that_str(info.target_settings.pep508_platform_release).equals("5.15.0")
    env.expect.that_str(info.target_settings.pep508_platform_version).equals("#1 SMP")
    env.expect.that_str(info.target_settings.py_linux_libc).equals("musl")

    # pycross_exec_platform_transition resets all target settings to their defaults.
    env.expect.that_str(info.transitioned_settings.glibc_version).equals("2.28")
    env.expect.that_str(info.transitioned_settings.macos_version).equals("15.0")
    env.expect.that_str(info.transitioned_settings.musl_version).equals("1.2")
    env.expect.that_str(info.transitioned_settings.pep508_implementation_name).equals("cpython")
    env.expect.that_str(info.transitioned_settings.pep508_platform_python_implementation).equals("CPython")
    env.expect.that_str(info.transitioned_settings.pep508_platform_release).equals("")
    env.expect.that_str(info.transitioned_settings.pep508_platform_version).equals("")
    env.expect.that_str(info.transitioned_settings.py_linux_libc).equals("glibc")

    # On Bazel 9+, scope = "target" also resets pycross settings across cfg = "exec".
    # bazel_features 1.11.0 has no dedicated flag for target-scoped build settings,
    # so use a Bazel 9.0+ feature flag as the version gate.
    if bazel_features.rules.no_struct_field_denylist:
        env.expect.that_str(info.exec_settings.glibc_version).equals("2.28")
        env.expect.that_str(info.exec_settings.macos_version).equals("15.0")
        env.expect.that_str(info.exec_settings.musl_version).equals("1.2")
        env.expect.that_str(info.exec_settings.pep508_implementation_name).equals("cpython")
        env.expect.that_str(info.exec_settings.pep508_platform_python_implementation).equals("CPython")
        env.expect.that_str(info.exec_settings.pep508_platform_release).equals("")
        env.expect.that_str(info.exec_settings.pep508_platform_version).equals("")

def transitions_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_transitions_basic,
            _test_transitions_resets_target_settings,
        ],
    )
