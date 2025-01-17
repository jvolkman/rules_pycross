"""Provides a config flag that returns the micro-level version of the selected rules_python toolchain."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@pythons_hub//:versions.bzl", "MINOR_MAPPING")

def _rules_python_interpreter_version_impl(ctx):
    value = _flag_value(ctx.attr._python_version_flag)
    value = MINOR_MAPPING.get(value, value)

    if not value:
        value = ctx.attr.default_version

    return [config_common.FeatureFlagInfo(value = value)]

_rules_python_interpreter_version = rule(
    implementation = _rules_python_interpreter_version_impl,
    attrs = {
        "default_version": attr.string(mandatory = True),
        "_python_version_flag": attr.label(
            default = "@rules_python//python/config_settings:python_version",
        ),
    },
)

def _flag_value(s):
    if config_common.FeatureFlagInfo in s:
        return s[config_common.FeatureFlagInfo].value
    else:
        return s[BuildSettingInfo].value

def rules_python_interpreter_version(name, default_version, **kwargs):
    """Builds a target that returns the currently-selected rules_pycross toolchain version.

    This value can be used in a config_setting; e.g.,
    config_setting(
        name = "foo",
        flag_values = {
            "@rules_pycross//pycross/private:rules_python_interpreter_version": "3.12.0",
        },
    )
    """

    _rules_python_interpreter_version(
        name = name,
        default_version = default_version,
        **kwargs
    )
