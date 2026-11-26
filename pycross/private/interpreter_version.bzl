"""Provides a config flag that returns the micro-level version of the selected rules_python toolchain."""

load("@pythons_hub//:versions.bzl", "MINOR_MAPPING", "PYTHON_VERSIONS")
load(":pep508_marker_values.bzl", "flag_value")
load(":python_versions.bzl", "resolve_interpreter_version")

def _rules_python_interpreter_version_impl(ctx):
    value = resolve_interpreter_version(
        flag_value(ctx.attr._python_version_flag),
        ctx.attr.default_version,
        MINOR_MAPPING,
        PYTHON_VERSIONS,
    )
    return [config_common.FeatureFlagInfo(value = value)]

rules_python_interpreter_version = rule(
    implementation = _rules_python_interpreter_version_impl,
    doc = (
        "Builds a target that returns the currently-selected rules_pycross toolchain version " +
        "as a FeatureFlagInfo value for use in config_setting flag_values."
    ),
    attrs = {
        "default_version": attr.string(mandatory = True),
        "_python_version_flag": attr.label(
            default = "@rules_python//python/config_settings:python_version",
        ),
    },
)
