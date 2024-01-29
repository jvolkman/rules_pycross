"""Provides a config flag that returns the micro-level version of the selected rules_python toolchain."""

load("@rules_python//python:versions.bzl", "TOOL_VERSIONS")

def _rules_python_interpreter_version_impl(ctx):
    return [
        config_common.FeatureFlagInfo(value = ctx.attr.version),
    ]

_rules_python_interpreter_version = rule(
    implementation = _rules_python_interpreter_version_impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)

def rules_python_interpreter_version(name, **kwargs):
    """Builds a target that returns the currently-selected rules_pycross toolchain version.

    This value can be used in a config_setting; e.g.,
    config_setting(
        name = "foo",
        flag_values = {
            "@rules_pycross//pycross/private:rules_python_interpreter_version": "3.12.0",
        },
    )
    """

    selects = {
        "@rules_python//python/config_settings:is_python_%s" % version: version
        for version in sorted(TOOL_VERSIONS)
    }
    selects["//conditions:default"] = ""

    _rules_python_interpreter_version(
        name = name,
        version = select(selects),
        **kwargs
    )
