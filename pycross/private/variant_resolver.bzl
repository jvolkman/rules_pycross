"""Variant resolver rule for conflict set mutual exclusion enforcement.

Each variant resolver reads the bool_flags that enable the items in a single
conflict set (a flag may enable more than one item). It validates that at most one flag is set, and returns
a config_common.FeatureFlagInfo whose value is the qualified name of the
active variant. This lets config_setting targets reference the resolver
rather than individual bool_flags, providing:

  1. Build-time enforcement of mutual exclusion (fail if >1 flag is set).
  2. Clean default handling (return default variant when no flag is set).
  3. A single point of indirection per conflict set.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(":deferred_failure.bzl", "register_failure_action")

def _variant_resolver_impl(ctx):
    active = []
    active_flags = []
    for flag, names in ctx.attr.flags.items():
        if not flag[BuildSettingInfo].value:
            continue
        active_flags.append(str(flag.label))
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
        value = active[0]
    elif ctx.attr.default:
        value = ctx.attr.default
    else:
        value = ""

    return [config_common.FeatureFlagInfo(value = value)]

variant_resolver = rule(
    implementation = _variant_resolver_impl,
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "flags": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            doc = "Maps each bool_flag to the space-separated qualified names of the items it enables. " +
                  "A flag can enable several items (e.g. a repo-level `group_test` covering two projects).",
        ),
        "default": attr.string(
            default = "",
            doc = "The default variant qualified name when no flag is set.",
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
