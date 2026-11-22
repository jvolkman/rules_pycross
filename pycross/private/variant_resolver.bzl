"""Variant resolver rule for conflict set mutual exclusion enforcement.

Each variant resolver reads the bool_flags and per-repo `//_variants`
string_flags that enable the items in a single conflict set (a flag may enable
more than one item). It validates that at most one item is active, and returns
a config_common.FeatureFlagInfo whose value is the qualified name of the
active variant. This lets config_setting targets reference the resolver
rather than individual flags, providing:

  1. Build-time enforcement of mutual exclusion (fail if >1 item is active).
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

def _usable_items(ctx):
    """The items this configuration may select, or None for all of them."""
    value = _setting_value(ctx.attr.usable) if ctx.attr.usable else "*"
    if value == "*":
        return None
    usable = {}
    for name in value.split(" "):
        if name:
            usable[_check_item(ctx, name, str(ctx.attr.usable.label))] = True
    return usable

def _parse_usable_value(value):
    """Parse a `_usable_<set>` string_flag value into None (`*`) or `{qname: True}`."""
    if value == "*":
        return None
    usable = {}
    for name in value.split(" "):
        if name:
            usable[name] = True
    return usable

def _rival_blocks_default(ctx, default):
    """Return True if an active CLI flag selects a rival of `default` in an overlapping set."""
    if not ctx.attr.rival_flags and not ctx.attr.string_flags:
        return False

    usable_by_set = {
        set_suffix: _parse_usable_value(flag[BuildSettingInfo].value)
        for flag, set_suffix in ctx.attr.rival_usables.items()
    }

    def _entry_active(entries):
        for entry in entries:
            item, rival_qname, other_suffix = entry[0], entry[1], entry[2]
            if item != default:
                continue
            other_usable = usable_by_set.get(other_suffix)
            if other_usable == None or rival_qname in other_usable:
                return True
        return False

    for flag, spec_json in ctx.attr.rival_flags.items():
        if not flag[BuildSettingInfo].value:
            continue
        if _entry_active(json.decode(spec_json)):
            return True

    for flag, spec_json in ctx.attr.string_flags.items():
        raw = flag[BuildSettingInfo].value
        if not raw:
            continue
        spec = json.decode(spec_json)
        rivals = spec.get("rivals")
        if not rivals:
            continue
        for token in raw.split(","):
            token = token.strip()
            if token and token in rivals and _entry_active(rivals[token]):
                return True

    return False

def _variant_resolver_impl(ctx):
    # A repo pin (set by a pinned repo's transition) wins over everything.
    pin = _setting_value(ctx.attr.pin)
    if pin:
        return [config_common.FeatureFlagInfo(value = _check_item(ctx, pin, str(ctx.attr.pin.label)))]

    # A transitioned repo limits the set to the items it can use, so flags meant
    # for other repos don't activate anything else here.
    usable = _usable_items(ctx)
    if usable != None and not usable:
        return [config_common.FeatureFlagInfo(value = "")]

    active = []
    active_flags = []
    for flag, value in ctx.attr.flags.items():
        if not flag[BuildSettingInfo].value:
            continue
        display, sep, names = value.partition("|")
        if not sep:
            display, names = str(flag.label), value
        enabled = [name for name in names.split(" ") if usable == None or name in usable]
        if not enabled:
            continue
        active_flags.append(display)
        for name in enabled:
            if name not in active:
                active.append(name)

    for flag, spec_json in ctx.attr.string_flags.items():
        raw = flag[BuildSettingInfo].value
        if not raw:
            continue
        spec = json.decode(spec_json)
        display = spec.get("display") or str(flag.label)
        flag_map = spec.get("map", {})
        valid = spec.get("valid", sorted(flag_map.keys()))
        for token in raw.split(","):
            token = token.strip()
            if not token:
                continue
            if token not in valid:
                fail("{} selects unknown variant '{}' (expected one of: {})".format(
                    display,
                    token,
                    ", ".join(valid),
                ))
            names = flag_map.get(token)
            if not names:
                continue
            enabled = [name for name in names if usable == None or name in usable]
            if not enabled:
                continue
            flag_display = "{}={}".format(display, token)
            if flag_display not in active_flags:
                active_flags.append(flag_display)
            for name in enabled:
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
    # applies only when no flag selects a variant in this set and no active CLI
    # flag selects a conflicting rival in an overlapping conflict set.
    default = _setting_value(ctx.attr.default_setting)
    if default and (usable == None or default in usable):
        checked_default = _check_item(ctx, default, str(ctx.attr.default_setting.label))
        if not _rival_blocks_default(ctx, checked_default):
            return [config_common.FeatureFlagInfo(value = checked_default)]

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
        "rival_flags": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            default = {},
            doc = "Maps bool_flags from overlapping conflict sets to JSON-encoded lists of " +
                  "`[item_in_this_set, rival_qname, other_set_suffix]` entries that suppress " +
                  "`default_setting` when active.",
        ),
        "rival_usables": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            default = {},
            doc = "Maps `_usable_<other_set>` string settings to `other_set_suffix` so rival " +
                  "flags ignored by an overlapping set's usable scope do not suppress `default_setting`.",
        ),
        "string_flags": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            doc = "Maps each repo's `//_variants` string_flag to a JSON-encoded spec " +
                  "`{\"display\": str, \"valid\": [flag_name, ...], \"map\": {flag_name: [qname, ...]}, " +
                  "\"rivals\": {flag_name: [[item, rival_qname, other_set_suffix], ...]}}`. " +
                  "Comma-separated tokens in the flag must appear in `valid`; tokens present in `map` " +
                  "enable the listed items in this conflict set, and tokens in `rivals` suppress `default_setting`.",
        ),
        "usable": attr.label(
            providers = [BuildSettingInfo],
            doc = "A string setting with the space-separated items that flags and the default may " +
                  "select, `*` for all of them. A transitioned repo narrows it to the items it requests " +
                  "that don't conflict with its pins.",
        ),
    },
)

def _pycross_no_variant_selected_impl(ctx):
    if ctx.attr._unavailable_package_mode[BuildSettingInfo].value != "fail_at_execution":
        fail(ctx.attr.message)

    out_name = "_no_variant_%x.whl" % (hash(ctx.label.name) & 0xffffffff)
    out = ctx.actions.declare_file(out_name)
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
