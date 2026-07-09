"""Variant resolver rule for conflict set mutual exclusion enforcement.

Each variant resolver reads a set of bool_flags that represent the items in
a single conflict set. It validates that at most one flag is set, and returns
a config_common.FeatureFlagInfo whose value is the qualified name of the
active variant. This lets config_setting targets reference the resolver
rather than individual bool_flags, providing:

  1. Build-time enforcement of mutual exclusion (fail if >1 flag is set).
  2. Clean default handling (return default variant when no flag is set).
  3. A single point of indirection per conflict set.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _variant_resolver_impl(ctx):
    active = []
    for i, flag in enumerate(ctx.attr.flags):
        if flag[BuildSettingInfo].value:
            active.append(ctx.attr.names[i])

    if len(active) > 1:
        fail(
            "Conflicting variants are active simultaneously: {}. ".format(
                " and ".join(["--" + name for name in active]),
            ) + "Only one variant from each conflict set may be enabled at a time.",
        )

    if active:
        value = active[0]
    elif ctx.attr.default:
        value = ctx.attr.default
    else:
        fail(
            "No variant selected and no default configured for conflict set. " +
            "Set one of: " + ", ".join(ctx.attr.names),
        )

    return [config_common.FeatureFlagInfo(value = value)]

variant_resolver = rule(
    implementation = _variant_resolver_impl,
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "flags": attr.label_list(
            providers = [BuildSettingInfo],
            doc = "The bool_flag targets for each item in the conflict set.",
        ),
        "names": attr.string_list(
            doc = "The qualified name for each flag, in the same order as flags.",
        ),
        "default": attr.string(
            default = "",
            doc = "The default variant qualified name when no flag is set.",
        ),
    },
)
