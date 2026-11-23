"""Joint conflict-variant state rule and FeatureFlagInfo projections.

A single `variant_state` target per workspace reads every repo's bool_flags,
`//_variants` string_flags, and the canonical `//_lock:_state` setting once,
and computes the consistent assignment across all conflict sets:

  1. Validate all `//_variants` string_flag tokens up front so typos fail loudly.
  2. Apply explicit selections per set: repo pin > usable-filtered flags,
     failing if more than one item is active in any conflict set.
  3. Compute the items excluded by those explicit selections across all
     overlapping conflict sets (using `excluded_variant_items`).
  4. Apply each remaining set's usable repo default unless it is excluded.

Thin projection rules (`variant_set_projection` for `_resolver_<set>`, and
`variant_item_projection` for multi-set items `_item_<qname>`) expose
`config_common.FeatureFlagInfo` values so `config_setting` targets and PEP 508
marker evaluators can match them directly without two-stage rival plumbing or
`_is_<q>_via_<j>` groups.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(":deferred_failure.bzl", "register_failure_action")
load(":util.bzl", "decode_variant_state", "excluded_variant_items")

VariantStateInfo = provider(
    doc = "Resolved conflict-variant selections for all conflict sets in a workspace.",
    fields = {
        "sets": "dict[str, str]: set_key -> active variant item qname, or '' if unselected.",
        "active_items": "dict[str, bool]: set of active variant item qnames across all sets.",
    },
)

def _check_item(set_items, value, source):
    if set_items and value not in set_items:
        fail("{} selects unknown variant '{}' (expected one of: {})".format(
            source,
            value,
            ", ".join(set_items),
        ))
    return value

def _parse_usable_str(value, set_items, source):
    """Return `{qname: True}` allowed by `value`, or None if all items are usable (`*`)."""
    if value == "*":
        return None
    usable = {}
    for name in value.split(" "):
        if name:
            usable[_check_item(set_items, name, source)] = True
    return usable

def _parse_string_flags(ctx):
    """Validate all string_flags tokens and return decoded `(display, flag_map, tokens)` tuples."""
    parsed = []
    for flag, spec_json in ctx.attr.string_flags.items():
        raw = flag[BuildSettingInfo].value
        if not raw:
            continue
        spec = json.decode(spec_json)
        display = spec.get("display") or str(flag.label)
        flag_map = spec.get("map", {})
        valid = spec.get("valid", sorted(flag_map.keys()))
        tokens = []
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
            tokens.append(token)
        parsed.append((display, flag_map, tokens))
    return parsed

def _parse_bool_flags(ctx):
    """Return `(display, names)` tuples for every active bool_flag."""
    parsed = []
    for flag, value in ctx.attr.flags.items():
        if not flag[BuildSettingInfo].value:
            continue
        display, sep, names = value.partition("|")
        if not sep:
            display, names = str(flag.label), value
        parsed.append((display, names.split(" ")))
    return parsed

def _variant_state_impl(ctx):
    sets = ctx.attr.sets

    # Validate unknown tokens in `//_variants` string_flags before evaluating
    # pins or unusable sets so typos fail loudly everywhere.
    parsed_string_flags = _parse_string_flags(ctx)
    parsed_bool_flags = _parse_bool_flags(ctx)

    raw_state = ctx.attr.state[BuildSettingInfo].value if ctx.attr.state else ""
    state_label = str(ctx.attr.state.label) if ctx.attr.state else ""
    state = decode_variant_state(raw_state)

    # Stage 1: resolve explicit selections (pin > usable-filtered flags) per set.
    explicit = {}
    usable_by_set = {}
    for set_key, set_items in sorted(sets.items()):
        pin = state.get("p:" + set_key, "")
        if pin:
            explicit[set_key] = _check_item(set_items, pin, state_label)
            continue

        # Absent `"u:<set>"` in `_state` (including reset `""`) means `"*"` (all
        # items usable), whereas explicit `""` means no items are usable.
        usable = _parse_usable_str(state.get("u:" + set_key, "*"), set_items, state_label)
        usable_by_set[set_key] = usable
        if usable != None and not usable:
            explicit[set_key] = ""
            continue

        set_items_dict = {item: True for item in set_items}
        active = []
        active_flags = []
        for display, names in parsed_bool_flags:
            enabled = [
                name
                for name in names
                if name in set_items_dict and (usable == None or name in usable)
            ]
            if not enabled:
                continue
            active_flags.append(display)
            for name in enabled:
                if name not in active:
                    active.append(name)

        for display, flag_map, tokens in parsed_string_flags:
            for token in tokens:
                names = flag_map.get(token)
                if not names:
                    continue
                enabled = [
                    name
                    for name in names
                    if name in set_items_dict and (usable == None or name in usable)
                ]
                if not enabled:
                    continue
                flag_display = "{}={}".format(display, token)
                if flag_display not in active_flags:
                    active_flags.append(flag_display)
                for name in enabled:
                    if name not in active:
                        active.append(name)

        if len(active) > 1:
            detail = " (enabling {})".format(" and ".join(active)) if len(active_flags) == 1 else ""
            fail(
                "Conflicting variants are active simultaneously: {}{}. ".format(
                    " and ".join(["--" + f for f in active_flags]),
                    detail,
                ) + "Only one variant from each conflict set may be enabled at a time.",
            )
        explicit[set_key] = active[0] if active else ""

    # Stage 2: compute items excluded by any explicit selection across all sets,
    # then apply defaults that are usable and not excluded.
    explicit_active = {v: True for v in explicit.values() if v}
    rivals_excluded = excluded_variant_items(sets.values(), explicit_active)

    resolved = {}
    for set_key, set_items in sorted(sets.items()):
        if explicit[set_key]:
            resolved[set_key] = explicit[set_key]
            continue

        usable = usable_by_set.get(set_key)
        default = state.get("d:" + set_key, "")
        if default and (usable == None or default in usable):
            checked_default = _check_item(set_items, default, state_label)
            if checked_default not in rivals_excluded:
                resolved[set_key] = checked_default
                continue
        resolved[set_key] = ""

    active_items = {v: True for v in resolved.values() if v}

    # Final defense-in-depth invariant: no conflict set may have more than one
    # active item across the workspace's resolved assignment.
    for set_key, set_items in sorted(sets.items()):
        active_in_set = [item for item in set_items if item in active_items]
        if len(active_in_set) > 1:
            fail(
                "Inconsistent conflict variant state: {} are both active but conflict in set '{}' (resolved={}).".format(
                    " and ".join(active_in_set),
                    set_key,
                    resolved,
                ),
            )

    return [VariantStateInfo(sets = resolved, active_items = active_items)]

variant_state = rule(
    implementation = _variant_state_impl,
    provides = [VariantStateInfo],
    attrs = {
        "flags": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            doc = "Maps each bool_flag to the space-separated qualified names of the items it enables, " +
                  "optionally prefixed with a display name for error messages (`<display>|<names>`).",
        ),
        "sets": attr.string_list_dict(
            mandatory = True,
            doc = "Maps each conflict set key to the sorted list of item qualified names in that set.",
        ),
        "state": attr.label(
            providers = [BuildSettingInfo],
            doc = "Canonical `//_lock:_state` string_flag encoding per-set pins, defaults, and usable narrowing.",
        ),
        "string_flags": attr.label_keyed_string_dict(
            providers = [BuildSettingInfo],
            doc = "Maps each repo's `//_variants` string_flag to a JSON-encoded spec " +
                  "`{\"display\": str, \"valid\": [flag_name, ...], \"map\": {flag_name: [qname, ...]}}`.",
        ),
    },
)

def _variant_set_projection_impl(ctx):
    state = ctx.attr.state[VariantStateInfo]
    return [config_common.FeatureFlagInfo(value = state.sets.get(ctx.attr.set_key, ""))]

variant_set_projection = rule(
    implementation = _variant_set_projection_impl,
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "set_key": attr.string(
            mandatory = True,
            doc = "Conflict set key in `VariantStateInfo.sets` to project.",
        ),
        "state": attr.label(
            mandatory = True,
            providers = [VariantStateInfo],
            doc = "The workspace's `variant_state` target.",
        ),
    },
)

def _variant_item_projection_impl(ctx):
    state = ctx.attr.state[VariantStateInfo]
    return [config_common.FeatureFlagInfo(value = "true" if ctx.attr.item in state.active_items else "false")]

variant_item_projection = rule(
    implementation = _variant_item_projection_impl,
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "item": attr.string(
            mandatory = True,
            doc = "Variant item qualified name to check in `VariantStateInfo.active_items`.",
        ),
        "state": attr.label(
            mandatory = True,
            providers = [VariantStateInfo],
            doc = "The workspace's `variant_state` target.",
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
