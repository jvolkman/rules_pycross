"""Variant resolver rule for conflict set mutual exclusion enforcement.

Each variant resolver reads the bool_flags that enable the items in a single
conflict set (a flag may enable more than one item). It validates that at most one flag is set, and returns
a config_common.FeatureFlagInfo whose value is the qualified name of the
active variant. This lets config_setting targets reference the resolver
rather than individual bool_flags, providing:

  1. Build-time enforcement of mutual exclusion (fail if >1 flag is set).
  2. Pins and defaults set by generated repos' transitions: pin > flags > default.
  3. A single point of indirection per conflict set.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(":deferred_failure.bzl", "register_failure_action")

def _setting_value(target):
    return target[BuildSettingInfo].value if target else ""

def _check_item(ctx, value, source):
    if ctx.attr.items and value not in ctx.attr.items:
        fail("{} selects unknown variant '{}' (expected one of: {})".format(source, value, ", ".join(ctx.attr.items)))
    return value

def _variant_resolver_impl(ctx):
    # A repo pin (set by a pinned repo's transition) wins over everything.
    pin = _setting_value(ctx.attr.pin)
    if pin:
        return [config_common.FeatureFlagInfo(value = _check_item(ctx, pin, str(ctx.attr.pin.label)))]

    active = []
    active_flags = []
    for flag, value in ctx.attr.flags.items():
        if not flag[BuildSettingInfo].value:
            continue
        display, sep, names = value.partition("|")
        if not sep:
            display, names = str(flag.label), value
        active_flags.append(display)
        for name in names.split(" "):
            if name not in active:
                active.append(name)

    if len(active) > 1:
        fail(
            "Conflicting variants are active simultaneously: {} (enabling {}). ".format(
                " and ".join(["--" + f for f in active_flags]),
                " and ".join(active),
            ) + "Only one variant from each conflict set may be enabled at a time.",
        )
    if active:
        return [config_common.FeatureFlagInfo(value = active[0])]

    # A repo default (set by a repo's transition from its project's default-groups)
    # applies only when no flag selects a variant.
    default = _setting_value(ctx.attr.default_setting)
    if default:
        return [config_common.FeatureFlagInfo(value = _check_item(ctx, default, str(ctx.attr.default_setting.label)))]

    return [config_common.FeatureFlagInfo(value = "")]

variant_resolver = rule(
    implementation = _variant_resolver_impl,
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "default_setting": attr.label(
            providers = [BuildSettingInfo],
            doc = "A string setting naming the default variant, used when no flag or pin selects one.",
        ),
        "flags": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            doc = "Maps each bool_flag to the space-separated qualified names of the items it enables, " +
                  "optionally prefixed with a display name for error messages (`<display>|<names>`). " +
                  "A flag can enable several items (e.g. a repo-level `group_test` covering two projects).",
        ),
        "items": attr.string_list(
            doc = "All qualified names in the conflict set, used to validate pin and default values.",
        ),
        "pin": attr.label(
            providers = [BuildSettingInfo],
            doc = "A string setting naming the pinned variant. When set, it overrides the flags.",
        ),
    },
)

def _pycross_no_variant_selected_impl(ctx):
    if ctx.attr._unavailable_package_mode[BuildSettingInfo].value != "fail_at_execution":
        fail(ctx.attr.message)

    out = ctx.actions.declare_file(ctx.label.name + ".whl")
    register_failure_action(
        ctx,
        outputs = [out],
        message = ctx.attr.message,
        mnemonic = "PycrossNoVariantSelected",
        progress_message = "No uv conflict variant selected",
    )
    return [
        DefaultInfo(
            files = depset([out]),
            runfiles = ctx.runfiles(files = [out]),
        ),
        PyInfo(transitive_sources = depset()),
    ]

# Provides DefaultInfo and PyInfo so it type-checks as a select() branch for
# pycross_library_proxy and satisfies consumers when deferred to execution under
# unavailable_package_mode=fail_at_execution.
pycross_no_variant_selected = rule(
    implementation = _pycross_no_variant_selected_impl,
    provides = [DefaultInfo, PyInfo],
    attrs = {
        "message": attr.string(
            mandatory = True,
            doc = "Error message emitted when no variant is selected.",
        ),
        "_unavailable_package_mode": attr.label(
            default = Label("//pycross/settings:unavailable_package_mode"),
        ),
    },
)
