"""Variant flag collection, transition settings, and `_variants/BUILD.bazel` generation."""

load("//pycross/private:build_text.bzl", "alias", "config_setting_group")
load(
    "//pycross/private:lock_contract.bzl",
    "VARIANTS_STRING_FLAG_TARGET",
    "VARIANT_STATE_DEFAULT_PREFIX",
    "VARIANT_STATE_PIN_PREFIX",
    "VARIANT_STATE_USABLE_PREFIX",
    "lock_constraint_label",
    "lock_unselected_label",
    "variant_state_key",
)
load("//pycross/private:variant_util.bzl", "excluded_variant_items", "variant_item_qname", "variant_set_suffix")
load(":selects.bzl", "unselected_condition")

def collect_variants(variant_sets):
    """Collect this repo's variant flags, conflict sets and defaults from its lock.

    Args:
        variant_sets: The lock's `variants` list.

    Returns:
        struct(
            flags = {flag: [qnames]},  # this repo's _variants flags and the items they enable
            sets = {set_suffix: struct(qnames, flags, default, pin, requested)},
        )
    """
    flags = {}
    sets = {}
    for variant_set in variant_sets:
        qnames = []
        display_items = []
        set_flags = {}  # flag -> [qnames in this set]
        item_flags = []  # (qname, [flags])
        for item in variant_set["items"]:
            qname = variant_item_qname(item)
            qnames.append(qname)
            pkg = item.get("package", "")
            kind = item.get("kind", "")
            iname = item.get("name", "")
            if kind == "extra" and iname:
                display_items.append("{}[{}]".format(pkg, iname) if pkg else "extra '{}'".format(iname))
            elif kind == "group" and iname:
                display_items.append("{}:{}".format(pkg, iname) if pkg else "group '{}'".format(iname))
            elif kind == "project" and pkg:
                display_items.append(pkg)
            else:
                display_items.append(qname)
            item_flags.append((qname, item.get("flags", [])))
            for flag in item.get("flags", []):
                flag_qnames = flags.setdefault(flag, [])
                if qname not in flag_qnames:
                    flag_qnames.append(qname)
                set_flags.setdefault(flag, []).append(qname)

        # For messages: per item, the first of its flags that selects only that
        # item in this set (e.g. `extra_cpu`, or `group_app-a_test` when
        # `group_test` would enable two conflicting items).
        usable = []
        for _, item_flag_list in item_flags:
            for flag in item_flag_list:
                if len(set_flags[flag]) == 1:
                    if flag not in usable:
                        usable.append(flag)
                    break
        if qnames:
            sets[variant_set_suffix(qnames)] = struct(
                qnames = qnames,
                display_items = display_items,
                flags = usable,
                default = variant_set.get("repo_default", ""),
                pin = variant_set.get("repo_pin", ""),
                requested = variant_set.get("repo_requested", []),
            )
    return struct(flags = flags, sets = sets)

def excluded_items(variant_info, pins_by_set):
    """The items that conflict with an item the repo pins.

    Args:
        variant_info: Result of collect_variants.
        pins_by_set: {set suffix: pinned qname}.

    Returns:
        {qname: True}.
    """
    return excluded_variant_items(
        [vset.qnames for vset in variant_info.sets.values()],
        pins_by_set.values(),
    )

def effective_defaults(variant_info, pins_by_set = None, excluded = None):
    """Return `{set_suffix: default_qname}` for unpinned sets with a non-excluded default.

    Args:
        variant_info: Result of `collect_variants`.
        pins_by_set: Optional `{set suffix: pinned qname}` dict.
        excluded: Optional `{qname: True}` dict of items excluded by pins.

    Returns:
        Dict `{set_suffix: default_qname}`.
    """
    pins_by_set = pins_by_set or {}
    excluded = excluded or {}
    defaults = {}
    for set_suffix, vset in sorted(variant_info.sets.items()):
        # A default that conflicts with a pin in another set would select both.
        if set_suffix not in pins_by_set and not vset.pin and vset.default and vset.default not in excluded:
            defaults[set_suffix] = vset.default
    return defaults

def usable_settings(variant_info, pins_by_set, excluded):
    """`u:<set>` overrides in `//_lock:_state` for a transitioned repo.

    Variant resolvers read every repo's flags. Inside a repo with its own
    transition, a flag meant for another repo could otherwise activate an item
    that this repo didn't request, or that conflicts with one it pins, and
    switch versions in shared packages. Each unpinned set is limited to the
    items the repo requests that aren't excluded.

    Args:
        variant_info: Result of collect_variants.
        pins_by_set: {set suffix: pinned qname}.
        excluded: Result of excluded_items.

    Returns:
        `{"u:<set>": space-separated usable qnames}` for sets that aren't fully usable.
    """
    result = {}
    for set_suffix, vset in sorted(variant_info.sets.items()):
        if set_suffix in pins_by_set:
            continue
        usable = [q for q in vset.requested if q not in excluded]
        if len(usable) < len(vset.qnames):
            result[variant_state_key(VARIANT_STATE_USABLE_PREFIX, set_suffix)] = " ".join(sorted(usable))
    return result

def transition_settings(variant_info, variant_pins, member_name, has_other_flags):
    """The `//_lock:_state` overrides that a repo's transition merges.

    Args:
        variant_info: Result of collect_variants.
        variant_pins: {set suffix: qname} that the repo's flags/settings select.
        member_name: The repo name, for messages.
        has_other_flags: Whether the repo transitions for other reasons (its
            own `flags` or `settings`).

    Returns:
        struct(state_overrides = {key: value}, pins_by_set, defaults_by_set, excluded).
    """
    pins_by_set = dict(variant_pins)
    for set_suffix, vset in sorted(variant_info.sets.items()):
        if not vset.pin:
            continue

        # The only item of the set that the repo requests.
        if pins_by_set.get(set_suffix, vset.pin) != vset.pin:
            fail("{}: flags/settings select {}, but the repo requests only {} from that conflict set".format(
                member_name,
                pins_by_set[set_suffix],
                vset.pin,
            ))
        pins_by_set[set_suffix] = vset.pin
    excluded = excluded_items(variant_info, pins_by_set)
    defaults_by_set = effective_defaults(variant_info, pins_by_set, excluded)

    state_overrides = {}
    for set_suffix, qname in sorted(pins_by_set.items()):
        state_overrides[variant_state_key(VARIANT_STATE_PIN_PREFIX, set_suffix)] = qname
    for set_suffix, qname in sorted(defaults_by_set.items()):
        state_overrides[variant_state_key(VARIANT_STATE_DEFAULT_PREFIX, set_suffix)] = qname
    if has_other_flags or state_overrides:
        state_overrides.update(usable_settings(variant_info, pins_by_set, excluded))
    return struct(
        state_overrides = state_overrides,
        pins_by_set = pins_by_set,
        defaults_by_set = defaults_by_set,
        excluded = excluded,
    )

def variants_build(variant_info, workspace_repo, repo_name, unselected_groups = None, pins_by_set = None, defaults_by_set = None, excluded = None, expose_variant_flags = True):
    """Render _variants/BUILD.bazel: this repo's variant flags.

    The workspace repo's variant resolvers read these bool_flags (see
    package_repo.bzl), so one flag here can enable the same extra/group in
    several projects. `is_<flag>` matches when all of the items the flag
    enables are active. For this repo's default variant, it also matches when
    nothing in the set is selected, so first-party select()s outside the repo's
    transition see the default too.

    Args:
        variant_info: Result of collect_variants.
        workspace_repo: Name of the workspace (backing) repo.
        repo_name: This repo's apparent name, for messages.
        unselected_groups: {name: [set suffixes]} of `_unselected_all_*`
            groups that the repo's selects reference.
        pins_by_set: {set suffix: qname} this repo's transition pins.
        defaults_by_set: Optional precomputed {set suffix: default qname}
            (from `transition_settings`). Computed from `variant_info` when omitted.
        excluded: {qname: True} of items that conflict with those pins.
        expose_variant_flags: Whether to emit user-facing `_variants` flags and
            `is_<flag>` config_settings (False for auto-generated `<ws>__build`).

    Returns:
        The file content, or None if the repo has no variants.
    """
    flags = variant_info.flags if expose_variant_flags else {}
    if not flags and not variant_info.sets:
        return None

    pins_by_set = pins_by_set or {}
    excluded = excluded or {}
    if defaults_by_set == None:
        defaults_by_set = effective_defaults(variant_info, pins_by_set, excluded)
    defaults = {}  # qname -> [all set suffixes containing qname] for repo defaults/pins
    if expose_variant_flags:
        default_qnames = {}
        for set_suffix, vset in variant_info.sets.items():
            sel = pins_by_set.get(set_suffix) or vset.pin or defaults_by_set.get(set_suffix)
            if sel:
                default_qnames[sel] = True
        for qname in default_qnames.keys():
            defaults[qname] = [
                set_suffix
                for set_suffix, vset in variant_info.sets.items()
                if qname in vset.qnames
            ]

    body = []
    needs_selects = False

    # `_selected_<qname>` for each item this repo pins or defaults to: active,
    # or nothing in its sets is selected (outside the repo's transition).
    groups = dict(unselected_groups or {})
    selected = {}  # qname -> condition label
    for qname, set_suffixes in sorted(defaults.items()):
        needs_selects = True
        unselected = unselected_condition(sorted(set_suffixes), workspace_repo, local_prefix = ":")
        groups.update(unselected.groups)
        selected[qname] = ":_selected_{}".format(qname)
        body.extend(config_setting_group(
            "_selected_{}".format(qname),
            "match_any",
            [lock_constraint_label(workspace_repo, qname), unselected.condition],
        ))

    # `_unselected_all_<hash>`: all of several conflict sets are unselected.
    for name, set_suffixes in sorted(groups.items()):
        needs_selects = True
        body.extend(config_setting_group(
            name,
            "match_all",
            [lock_unselected_label(workspace_repo, s) for s in set_suffixes],
        ))

    if flags:
        body.extend([
            "string_flag(",
            '    name = "{}",'.format(VARIANTS_STRING_FLAG_TARGET),
            '    build_setting_default = "",',
            ")",
            "",
        ])

    for flag, qnames in sorted(flags.items()):
        body.extend([
            "bool_flag(",
            '    name = "{}",'.format(flag),
            "    build_setting_default = False,",
            ")",
            "",
        ])
        conditions = [selected.get(q, lock_constraint_label(workspace_repo, q)) for q in qnames]
        if len(qnames) == 1:
            body.extend(alias("is_{}".format(flag), conditions[0]))
            continue
        needs_selects = True
        body.extend(config_setting_group("is_{}".format(flag), "match_all", conditions))

    for set_suffix, vset in sorted(variant_info.sets.items()):
        if expose_variant_flags and vset.flags:
            message = "No uv conflict variant selected. Set one of the _variants flags on your pycross repo: {} (e.g. --@{}//_variants:{}=True or --@{}//_variants={})".format(
                ", ".join(vset.flags),
                repo_name,
                vset.flags[0],
                repo_name,
                vset.flags[0],
            )
        else:
            readable_items = ", ".join(vset.display_items)
            message = "No uv conflict variant selected, and @{} has no _variants flag for it ({}). Select it through a repo for the declaring project.".format(
                repo_name,
                readable_items,
            )
        body.extend([
            "pycross_no_variant_selected(",
            '    name = "_no_variant_{}",'.format(set_suffix),
            "    message = {},".format(json.encode(message)),
            ")",
            "",
        ])

    header = ['package(default_visibility = ["//visibility:public"])', ""]
    if needs_selects:
        header.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    if flags:
        header.append('load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "string_flag")')
    if variant_info.sets:
        header.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "pycross_no_variant_selected")')
    header.append("")
    return "\n".join(header + body)
