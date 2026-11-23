"""Generator, table-driven semantics, and cross-repo safety-net tests for conflict variants."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo", "bool_flag", "string_flag")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "render_lock_build_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_resolver.bzl", "pycross_no_variant_selected", "variant_set_projection", "variant_state")

_VariantTupleInfo = provider(
    doc = "Resolved variant values across a set of resolvers.",
    fields = {"values": "dict[str, str]: set_id -> resolved FeatureFlagInfo value."},
)

def _variant_tuple_impl(ctx):
    values = {}
    for target, set_id in ctx.attr.resolvers.items():
        values[set_id] = target[config_common.FeatureFlagInfo].value
    if ctx.attr.build_flag:
        values["_build_flag"] = "true" if ctx.attr.build_flag[BuildSettingInfo].value else "false"
    return [_VariantTupleInfo(values = values)]

_variant_tuple = rule(
    implementation = _variant_tuple_impl,
    attrs = {
        "build_flag": attr.label(
            providers = [BuildSettingInfo],
        ),
        "resolvers": attr.label_keyed_string_dict(
            providers = [config_common.FeatureFlagInfo],
        ),
    },
    provides = [_VariantTupleInfo],
)

# ── Transition rules for consumer-pinned → __build inheritance & reset ──

_PIN_INH_PIN_S1 = "//tests/unit:_pin_inh_pin_s1"
_PIN_INH_DEFAULT_S1 = "//tests/unit:_pin_inh_default_s1"
_PIN_INH_USABLE_S1 = "//tests/unit:_pin_inh_usable_s1"
_PIN_INH_USABLE_S2 = "//tests/unit:_pin_inh_usable_s2"
_PIN_INH_BUILD_FLAG = "//tests/unit:_pin_inh_build_flag"

def _consumer_pin_transition_impl(_settings, _attr):
    return {
        _PIN_INH_PIN_S1: "g-b",
        _PIN_INH_USABLE_S2: "",
    }

_consumer_pin_transition = transition(
    implementation = _consumer_pin_transition_impl,
    inputs = [],
    outputs = [_PIN_INH_PIN_S1, _PIN_INH_USABLE_S2],
)

def _flagged_build_transition_impl(_settings, _attr):
    return {
        _PIN_INH_BUILD_FLAG: True,
        _PIN_INH_DEFAULT_S1: "g-a",
        _PIN_INH_USABLE_S1: "",
    }

_flagged_build_transition = transition(
    implementation = _flagged_build_transition_impl,
    inputs = [],
    outputs = [_PIN_INH_BUILD_FLAG, _PIN_INH_DEFAULT_S1, _PIN_INH_USABLE_S1],
)

def _reset_state_transition_impl(_settings, _attr):
    return {
        _PIN_INH_PIN_S1: "",
        _PIN_INH_DEFAULT_S1: "",
        _PIN_INH_USABLE_S1: "*",
        _PIN_INH_USABLE_S2: "*",
    }

_reset_state_transition = transition(
    implementation = _reset_state_transition_impl,
    inputs = [],
    outputs = [_PIN_INH_PIN_S1, _PIN_INH_DEFAULT_S1, _PIN_INH_USABLE_S1, _PIN_INH_USABLE_S2],
)

def _forward_tuple_impl(ctx):
    return [ctx.attr.dep[_VariantTupleInfo]]

_consumer_pin_wrapper = rule(
    implementation = _forward_tuple_impl,
    attrs = {"dep": attr.label(mandatory = True, providers = [_VariantTupleInfo])},
    cfg = _consumer_pin_transition,
    provides = [_VariantTupleInfo],
)

_flagged_build_wrapper = rule(
    implementation = _forward_tuple_impl,
    attrs = {"dep": attr.label(mandatory = True, providers = [_VariantTupleInfo])},
    cfg = _flagged_build_transition,
    provides = [_VariantTupleInfo],
)

_reset_state_wrapper = rule(
    implementation = _forward_tuple_impl,
    attrs = {"dep": attr.label(mandatory = True, providers = [_VariantTupleInfo])},
    cfg = _reset_state_transition,
    provides = [_VariantTupleInfo],
)

def _extract_block(text, name):
    marker = '    name = "{}",'.format(name)
    if marker not in text:
        return ""
    before, after = text.split(marker, 1)
    header = before.rsplit("\n\n", 1)[-1]
    body = after.split("\n)\n", 1)[0]
    return header + marker + body + "\n)"

# ── Generator unit tests for package_repo's _lock/BUILD.bazel ────────

# buildifier: disable=unused-variable
def _test_render_lock_build_overlapping_and_disjoint_impl(env, target):
    """All conflict sets share one variant_state; sets use variant_set_projection and multi-set items use variant_item_projection."""
    variant_sets = [
        {
            "qnames": ["group_g-a", "group_g-b"],
            "flags": {
                "@app//_variants:group_g-a": ["group_g-a"],
                "@app//_variants:group_g-b": ["group_g-b"],
            },
            "member_flags": {
                "app": {"group_g-a": ["group_g-a"], "group_g-b": ["group_g-b"]},
            },
        },
        {
            "qnames": ["group_g-a", "extra_x"],
            "flags": {
                "@app//_variants:group_g-a": ["group_g-a"],
                "@app//_variants:extra_x": ["extra_x"],
            },
            "member_flags": {
                "app": {"group_g-a": ["group_g-a"], "extra_x": ["extra_x"]},
            },
        },
        {
            "qnames": ["extra_p", "extra_q"],
            "flags": {
                "@app//_variants:extra_p": ["extra_p"],
                "@app//_variants:extra_q": ["extra_q"],
            },
            "member_flags": {
                "app": {"extra_p": ["extra_p"], "extra_q": ["extra_q"]},
            },
        },
    ]
    variant_items = {q: True for s in variant_sets for q in s["qnames"]}
    qname_to_resolvers = {
        "group_g-a": ["_resolver_group_g-a_group_g-b", "_resolver_extra_x_group_g-a"],
        "group_g-b": ["_resolver_group_g-a_group_g-b"],
        "extra_x": ["_resolver_extra_x_group_g-a"],
        "extra_p": ["_resolver_extra_p_extra_q"],
        "extra_q": ["_resolver_extra_p_extra_q"],
    }
    member_variant_flags = {
        "app": {
            "group_g-a": True,
            "group_g-b": True,
            "extra_x": True,
            "extra_p": True,
            "extra_q": True,
        },
    }

    rendered = render_lock_build_for_testing(
        variant_items,
        variant_sets,
        qname_to_resolvers,
        member_variant_flags,
    )

    # Single joint variant_state holds all sets, settings, and consolidated flags once.
    state = _extract_block(rendered, "_variant_state")
    env.expect.that_str(state).contains('"group_g-a_group_g-b": ["group_g-a","group_g-b"],')
    env.expect.that_str(state).contains('"extra_x_group_g-a": ["extra_x","group_g-a"],')
    env.expect.that_str(state).contains('"extra_p_extra_q": ["extra_p","extra_q"],')
    env.expect.that_str(state).contains('":_pin_group_g-a_group_g-b": "group_g-a_group_g-b",')
    env.expect.that_str(state).contains('":_default_extra_x_group_g-a": "extra_x_group_g-a",')
    env.expect.that_str(state).contains('":_usable_extra_p_extra_q": "extra_p_extra_q",')
    env.expect.that_str(state).contains('"@app//_variants:group_g-a": "@app//_variants:group_g-a|group_g-a",')
    env.expect.that_int(rendered.count('"@app//_variants:_variants":')).equals(1)
    env.expect.that_bool("_explicit_" in rendered).equals(False)
    env.expect.that_bool("rival_resolvers" in rendered).equals(False)
    env.expect.that_bool("selects.config_setting_group" in rendered).equals(False)

    # Each set emits a thin variant_set_projection under its `_resolver_<set>` name.
    res1 = _extract_block(rendered, "_resolver_group_g-a_group_g-b")
    env.expect.that_str(res1).contains('state = ":_variant_state",')
    env.expect.that_str(res1).contains('set_key = "group_g-a_group_g-b",')
    res_disjoint = _extract_block(rendered, "_resolver_extra_p_extra_q")
    env.expect.that_str(res_disjoint).contains('state = ":_variant_state",')
    env.expect.that_str(res_disjoint).contains('set_key = "extra_p_extra_q",')

    # Multi-set item `group_g-a` uses a variant_item_projection; single-set items match `_resolver_*` directly.
    item_ga = _extract_block(rendered, "_item_group_g-a")
    env.expect.that_str(item_ga).contains('state = ":_variant_state",')
    env.expect.that_str(item_ga).contains('item = "group_g-a",')
    is_ga = _extract_block(rendered, "is_group_g-a")
    env.expect.that_str(is_ga).contains('flag_values = {":_item_group_g-a": "true"},')
    is_gb = _extract_block(rendered, "is_group_g-b")
    env.expect.that_str(is_gb).contains('flag_values = {":_resolver_group_g-a_group_g-b": "group_g-b"},')
    env.expect.that_bool("_item_group_g-b" in rendered).equals(False)
    env.expect.that_bool("_via_" in rendered).equals(False)

def _test_render_lock_build_overlapping_and_disjoint(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_build_overlapping_and_disjoint_impl)

# buildifier: disable=unused-variable
def _test_render_lock_build_three_set_chain_impl(env, target):
    """A 3-set chain wires all 3 sets into one variant_state and projects only the two shared items."""
    variant_sets = [
        {"qnames": ["group_g-a", "group_g-b"], "flags": {}, "member_flags": {}},
        {"qnames": ["extra_x", "group_g-a"], "flags": {}, "member_flags": {}},
        {"qnames": ["extra_x", "extra_y"], "flags": {}, "member_flags": {}},
    ]
    variant_items = {q: True for s in variant_sets for q in s["qnames"]}
    qname_to_resolvers = {
        "group_g-a": ["_resolver_group_g-a_group_g-b", "_resolver_extra_x_group_g-a"],
        "group_g-b": ["_resolver_group_g-a_group_g-b"],
        "extra_x": ["_resolver_extra_x_group_g-a", "_resolver_extra_x_extra_y"],
        "extra_y": ["_resolver_extra_x_extra_y"],
    }

    rendered = render_lock_build_for_testing(variant_items, variant_sets, qname_to_resolvers, {})

    state = _extract_block(rendered, "_variant_state")
    env.expect.that_str(state).contains('"group_g-a_group_g-b": ["group_g-a","group_g-b"],')
    env.expect.that_str(state).contains('"extra_x_group_g-a": ["extra_x","group_g-a"],')
    env.expect.that_str(state).contains('"extra_x_extra_y": ["extra_x","extra_y"],')

    env.expect.that_str(rendered).contains('name = "_item_group_g-a",')
    env.expect.that_str(rendered).contains('name = "_item_extra_x",')
    env.expect.that_bool("_item_group_g-b" in rendered).equals(False)
    env.expect.that_bool("_item_extra_y" in rendered).equals(False)
    env.expect.that_bool("_explicit_" in rendered).equals(False)

def _test_render_lock_build_three_set_chain(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_build_three_set_chain_impl)

# ── Table-driven resolver-semantics suite ────────────────────────────
#
# Tests resolver behavior across pins, bool_flags, //_variants string_flags,
# usable filters, defaults, and a 3-set overlapping chain:
#   s1 = [g-a, g-b]
#   s2 = [g-a, x]
#   s3 = [x, y]
# Written declaratively so the exact same table can validate a future joint
# variant_state implementation by swapping only `_wire_chain_resolvers`.

_CHAIN_SETS = {
    "s1": ["g-a", "g-b"],
    "s2": ["g-a", "x"],
    "s3": ["x", "y"],
}

_CHAIN_ALL_ITEMS = ["g-a", "g-b", "x", "y"]

def _wire_chain_resolvers(prefix, pins = {}, defaults = {}, usables = {}):
    """Wire a 3-set overlapping chain via one variant_state + projections and return (tuple_target, flag_labels, sf_label)."""
    bool_labels = {}
    for item in _CHAIN_ALL_ITEMS:
        fname = "{}_bf_{}".format(prefix, item)
        util.helper_target(bool_flag, name = fname, build_setting_default = False)
        bool_labels[item] = ":" + fname

    sf_name = "{}_variants".format(prefix)
    util.helper_target(string_flag, name = sf_name, build_setting_default = "")
    sf_label = ":" + sf_name

    pin_map = {}
    default_map = {}
    usable_map = {}
    for sid in sorted(_CHAIN_SETS.keys()):
        pin_name = "{}_pin_{}".format(prefix, sid)
        def_name = "{}_default_{}".format(prefix, sid)
        usable_name = "{}_usable_{}".format(prefix, sid)
        util.helper_target(string_flag, name = pin_name, build_setting_default = pins.get(sid, ""))
        util.helper_target(string_flag, name = def_name, build_setting_default = defaults.get(sid, ""))
        util.helper_target(string_flag, name = usable_name, build_setting_default = usables.get(sid, "*"))
        pin_map[":" + pin_name] = sid
        default_map[":" + def_name] = sid
        usable_map[":" + usable_name] = sid

    state_name = "{}_state".format(prefix)
    spec = {
        "display": "@repo//_variants",
        "valid": list(_CHAIN_ALL_ITEMS),
        "map": {item: [item] for item in _CHAIN_ALL_ITEMS},
    }
    util.helper_target(
        variant_state,
        name = state_name,
        sets = _CHAIN_SETS,
        pins = pin_map,
        defaults = default_map,
        usables = usable_map,
        flags = {bool_labels[item]: "@repo//_variants:{}|{}".format(item, item) for item in _CHAIN_ALL_ITEMS},
        string_flags = {sf_label: json.encode(spec)},
    )

    resolver_map = {}
    for sid in sorted(_CHAIN_SETS.keys()):
        res_name = "{}_resolver_{}".format(prefix, sid)
        util.helper_target(
            variant_set_projection,
            name = res_name,
            state = ":" + state_name,
            set_key = sid,
        )
        resolver_map[":" + res_name] = sid

    tuple_name = "{}_tuple".format(prefix)
    util.helper_target(_variant_tuple, name = tuple_name, resolvers = resolver_map)
    return ":" + tuple_name, bool_labels, sf_label

_SEMANTICS_CASES = [
    struct(
        id = "defaults_only",
        defaults = {"s1": "g-a", "s2": "g-a"},
        expected = {"s1": "g-a", "s2": "g-a", "s3": ""},
    ),
    struct(
        id = "no_flags_no_defaults",
        expected = {"s1": "", "s2": "", "s3": ""},
    ),
    struct(
        id = "bool_rival_suppresses_s2_default",
        defaults = {"s1": "g-a", "s2": "g-a"},
        bools = ["g-b"],
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "string_rival_suppresses_s2_default",
        defaults = {"s1": "g-a", "s2": "g-a"},
        variants = "g-b",
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "bool_x_suppresses_s1_default_and_selects_s3",
        defaults = {"s1": "g-a", "s2": "g-a"},
        bools = ["x"],
        expected = {"s1": "", "s2": "x", "s3": "x"},
    ),
    struct(
        id = "string_x_suppresses_s1_default_and_selects_s3",
        defaults = {"s1": "g-a", "s2": "g-a"},
        variants = "x",
        expected = {"s1": "", "s2": "x", "s3": "x"},
    ),
    struct(
        id = "chain_endpoints_gb_and_y",
        defaults = {"s1": "g-a", "s2": "g-a"},
        variants = "g-b,y",
        expected = {"s1": "g-b", "s2": "", "s3": "y"},
    ),
    struct(
        id = "chain_ga_default_with_y",
        defaults = {"s1": "g-a", "s2": "g-a"},
        bools = ["y"],
        expected = {"s1": "g-a", "s2": "g-a", "s3": "y"},
    ),
    struct(
        id = "pin_gb_beats_flag_and_usable_blocks_ga_in_s2",
        pins = {"s1": "g-b"},
        defaults = {"s1": "g-a", "s2": "g-a"},
        usables = {"s1": "g-b", "s2": "x"},
        bools = ["g-a"],
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "pin_gb_suppresses_s2_default",
        pins = {"s1": "g-b"},
        defaults = {"s1": "g-a", "s2": "g-a"},
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "pin_ga_ignores_rival_flags",
        pins = {"s1": "g-a", "s2": "g-a"},
        usables = {"s1": "g-a", "s2": "g-a", "s3": "y"},
        bools = ["g-b"],
        variants = "x",
        expected = {"s1": "g-a", "s2": "g-a", "s3": ""},
    ),
    struct(
        id = "usable_filters_bool_rival_flag",
        defaults = {"s1": "g-a", "s2": "g-a"},
        usables = {"s1": "g-a"},
        bools = ["g-b"],
        expected = {"s1": "g-a", "s2": "g-a", "s3": ""},
    ),
    struct(
        id = "usable_filters_string_rival_flag",
        defaults = {"s1": "g-a", "s2": "g-a"},
        usables = {"s1": "g-a"},
        variants = "g-b",
        expected = {"s1": "g-a", "s2": "g-a", "s3": ""},
    ),
    struct(
        id = "usable_empty_clears_set",
        defaults = {"s1": "g-a", "s2": "g-a"},
        usables = {"s2": ""},
        expected = {"s1": "g-a", "s2": "", "s3": ""},
    ),
    struct(
        id = "bool_and_string_agree",
        defaults = {"s1": "g-a", "s2": "g-a"},
        bools = ["g-b"],
        variants = "g-b",
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "err_conflicting_bool_flags",
        bools = ["g-a", "g-b"],
        expected_error = "Conflicting variants are active simultaneously: --@repo//_variants:g-a and --@repo//_variants:g-b. Only one variant from each conflict set may be enabled at a time.",
    ),
    struct(
        id = "err_conflicting_string_tokens",
        variants = "g-a,g-b",
        expected_error = "Conflicting variants are active simultaneously: --@repo//_variants=g-a and --@repo//_variants=g-b. Only one variant from each conflict set may be enabled at a time.",
    ),
    struct(
        id = "err_conflicting_bool_and_string",
        bools = ["g-a"],
        variants = "x",
        expected_error = "Conflicting variants are active simultaneously: --@repo//_variants:g-a and --@repo//_variants=x. Only one variant from each conflict set may be enabled at a time.",
    ),
    struct(
        id = "err_conflicting_chain_s3",
        variants = "x,y",
        expected_error = "Conflicting variants are active simultaneously: --@repo//_variants=x and --@repo//_variants=y. Only one variant from each conflict set may be enabled at a time.",
    ),
    struct(
        id = "err_unknown_token",
        variants = "typo",
        expected_error = "@repo//_variants selects unknown variant 'typo' (expected one of: g-a, g-b, x, y)",
    ),
    struct(
        id = "err_unknown_token_when_pinned",
        pins = {"s1": "g-a", "s2": "g-a", "s3": "x"},
        variants = "typo",
        expected_error = "@repo//_variants selects unknown variant 'typo' (expected one of: g-a, g-b, x, y)",
    ),
    struct(
        id = "err_unknown_token_when_unusable",
        usables = {"s1": "", "s2": "", "s3": ""},
        variants = "typo",
        expected_error = "@repo//_variants selects unknown variant 'typo' (expected one of: g-a, g-b, x, y)",
    ),
]

def _expect_tuple_impl(expected):
    def _impl(env, target):
        actual = target[_VariantTupleInfo].values
        env.expect.that_dict(actual).contains_exactly(expected)

        # Harness-level conflict invariant: across all resolved sets, the active
        # items must never include two distinct members of the same conflict set.
        active = {v: True for v in actual.values() if v}
        for _sid, items in sorted(_CHAIN_SETS.items()):
            active_in_set = [item for item in items if item in active]
            env.expect.that_bool(len(active_in_set) <= 1).equals(True)

    return _impl

def _expect_error_impl(expected_error):
    def _impl(env, target):
        env.expect.that_target(target).failures().contains_predicate(
            matching.contains(expected_error),
        )

    return _impl

def _register_semantics_case_test(name, case):
    target, bool_labels, sf_label = _wire_chain_resolvers(
        name,
        pins = getattr(case, "pins", {}),
        defaults = getattr(case, "defaults", {}),
        usables = getattr(case, "usables", {}),
    )
    config_settings = {}
    for b in getattr(case, "bools", []):
        config_settings[str(Label(bool_labels[b]))] = True
    if getattr(case, "variants", ""):
        config_settings[str(Label(sf_label))] = case.variants

    expected_error = getattr(case, "expected_error", None)
    if expected_error:
        analysis_test(
            name = name,
            target = target,
            impl = _expect_error_impl(expected_error),
            expect_failure = True,
            config_settings = config_settings,
        )
    else:
        analysis_test(
            name = name,
            target = target,
            impl = _expect_tuple_impl(case.expected),
            config_settings = config_settings,
        )

# ── Cross-repo leak (#393), pinned vs sibling flag, and default-only ─

def _test_cross_repo_leak_393(name):
    """#393: a transitioned repo's usable narrowing ignores a sibling repo's CLI flag on an unpinned set."""
    sibling_cpu = name + "_sibling_cpu"
    util.helper_target(bool_flag, name = sibling_cpu, build_setting_default = False)
    pin_s1 = name + "_pin_s1"
    usable_s1 = name + "_usable_s1"
    usable_s2 = name + "_usable_s2"
    util.helper_target(string_flag, name = pin_s1, build_setting_default = "extra_gpu")
    util.helper_target(string_flag, name = usable_s1, build_setting_default = "extra_gpu")

    # S2 is [extra_cpu, group_gpu-test]; pinning extra_gpu excludes extra_cpu so usable_s2 is "group_gpu-test".
    util.helper_target(string_flag, name = usable_s2, build_setting_default = "group_gpu-test")

    util.helper_target(
        variant_state,
        name = name + "_state",
        sets = {
            "s1": ["extra_cpu", "extra_gpu"],
            "s2": ["extra_cpu", "group_gpu-test"],
        },
        pins = {":" + pin_s1: "s1"},
        usables = {
            ":" + usable_s1: "s1",
            ":" + usable_s2: "s2",
        },
        flags = {":" + sibling_cpu: "@runtime//_variants:extra_cpu|extra_cpu"},
    )
    util.helper_target(
        variant_set_projection,
        name = name + "_resolver_s1",
        state = ":" + name + "_state",
        set_key = "s1",
    )
    util.helper_target(
        variant_set_projection,
        name = name + "_resolver_s2",
        state = ":" + name + "_state",
        set_key = "s2",
    )
    util.helper_target(
        _variant_tuple,
        name = name + "_tuple",
        resolvers = {
            ":" + name + "_resolver_s1": "s1",
            ":" + name + "_resolver_s2": "s2",
        },
    )
    analysis_test(
        name = name,
        target = ":" + name + "_tuple",
        impl = _expect_tuple_impl({"s1": "extra_gpu", "s2": ""}),
        config_settings = {
            str(Label(":" + sibling_cpu)): True,
        },
    )

def _test_pinned_repo_ignores_sibling_cli_flag(name):
    """A pinned repo ignores a sibling repo's CLI flag selecting a rival variant."""
    target, bool_labels, sf_label = _wire_chain_resolvers(
        name,
        pins = {"s1": "g-a", "s2": "g-a"},
        usables = {"s1": "g-a", "s2": "g-a", "s3": "y"},
    )
    analysis_test(
        name = name,
        target = target,
        impl = _expect_tuple_impl({"s1": "g-a", "s2": "g-a", "s3": ""}),
        config_settings = {
            str(Label(bool_labels["g-b"])): True,
            str(Label(sf_label)): "x",
        },
    )

def _test_default_only_repo_fails_on_sibling_rival_flag(name):
    """A default-only repo (no pin, usable=*) suppresses its S2 default and hits _no_variant when a sibling flag picks rival g-b."""
    _tuple, bool_labels, _sf_label = _wire_chain_resolvers(
        name,
        defaults = {"s1": "g-a", "s2": "g-a"},
    )
    util.helper_target(
        native.config_setting,
        name = name + "_is_ga_via_s2",
        flag_values = {":" + name + "_resolver_s2": "g-a"},
    )
    util.helper_target(
        native.config_setting,
        name = name + "_unselected_s2",
        flag_values = {":" + name + "_resolver_s2": ""},
    )
    util.helper_target(
        pycross_no_variant_selected,
        name = name + "_no_variant_s2",
        message = "Set one of the _variants flags on your pycross repo: group_g-a, extra_x",
    )
    util.helper_target(native.filegroup, name = name + "_real_pkg", srcs = [])
    util.helper_target(
        native.alias,
        name = name + "_pkg",
        actual = select({
            ":" + name + "_is_ga_via_s2": ":" + name + "_real_pkg",
            ":" + name + "_unselected_s2": ":" + name + "_no_variant_s2",
        }),
    )
    analysis_test(
        name = name,
        target = ":" + name + "_pkg",
        impl = _expect_error_impl("Set one of the _variants flags on your pycross repo: group_g-a, extra_x"),
        expect_failure = True,
        config_settings = {
            str(Label(bool_labels["g-b"])): True,
        },
    )

def _expect_raw_tuple_impl(expected):
    def _impl(env, target):
        env.expect.that_dict(target[_VariantTupleInfo].values).contains_exactly(expected)

    return _impl

def _register_pin_inheritance_tests():
    """Register consumer-pinned -> __build pin-inheritance and reset tests."""
    util.helper_target(string_flag, name = "_pin_inh_pin_s1", build_setting_default = "")
    util.helper_target(string_flag, name = "_pin_inh_default_s1", build_setting_default = "")
    util.helper_target(string_flag, name = "_pin_inh_usable_s1", build_setting_default = "*")
    util.helper_target(string_flag, name = "_pin_inh_usable_s2", build_setting_default = "*")
    util.helper_target(bool_flag, name = "_pin_inh_build_flag", build_setting_default = False)
    util.helper_target(bool_flag, name = "_pin_inh_bf_x", build_setting_default = False)

    util.helper_target(
        variant_state,
        name = "_pin_inh_state",
        sets = {
            "s1": ["g-a", "g-b"],
            "s2": ["g-a", "x"],
        },
        pins = {":_pin_inh_pin_s1": "s1"},
        defaults = {":_pin_inh_default_s1": "s1"},
        usables = {
            ":_pin_inh_usable_s1": "s1",
            ":_pin_inh_usable_s2": "s2",
        },
        flags = {":_pin_inh_bf_x": "@repo//_variants:x|x"},
    )
    util.helper_target(
        variant_set_projection,
        name = "_pin_inh_res_s1",
        state = ":_pin_inh_state",
        set_key = "s1",
    )
    util.helper_target(
        variant_set_projection,
        name = "_pin_inh_res_s2",
        state = ":_pin_inh_state",
        set_key = "s2",
    )
    util.helper_target(
        _variant_tuple,
        name = "_pin_inh_probe",
        build_flag = ":_pin_inh_build_flag",
        resolvers = {
            ":_pin_inh_res_s1": "s1",
            ":_pin_inh_res_s2": "s2",
        },
    )

    # 1. Consumer-pinned -> plain __build (no transition) inherits consumer pin.
    util.helper_target(_consumer_pin_wrapper, name = "_pin_inh_plain_build", dep = ":_pin_inh_probe")
    analysis_test(
        name = "test_consumer_pin_inherited_by_plain_build",
        target = ":_pin_inh_plain_build",
        impl = _expect_raw_tuple_impl({"s1": "g-b", "s2": "", "_build_flag": "false"}),
    )

    # 2. Consumer-pinned -> __build with its own transition (explicit flag + default/usable,
    #    no pin) inherits consumer pin and applies its own flag.
    util.helper_target(_flagged_build_wrapper, name = "_pin_inh_flagged_inner", dep = ":_pin_inh_probe")
    util.helper_target(_consumer_pin_wrapper, name = "_pin_inh_flagged_build", dep = ":_pin_inh_flagged_inner")
    analysis_test(
        name = "test_consumer_pin_inherited_by_flagged_build",
        target = ":_pin_inh_flagged_build",
        impl = _expect_raw_tuple_impl({"s1": "g-b", "s2": "", "_build_flag": "true"}),
    )

    # 3. Consumer-pinned with usable_s2="" -> reset transition restores usable="*"
    #    (not ""), so an ambient flag for s2 selects "x" again.
    util.helper_target(_reset_state_wrapper, name = "_pin_inh_reset_inner", dep = ":_pin_inh_probe")
    util.helper_target(_consumer_pin_wrapper, name = "_pin_inh_after_reset", dep = ":_pin_inh_reset_inner")
    analysis_test(
        name = "test_reset_restores_all_usable",
        target = ":_pin_inh_after_reset",
        impl = _expect_raw_tuple_impl({"s1": "", "s2": "x", "_build_flag": "false"}),
        config_settings = {
            str(Label(":_pin_inh_bf_x")): True,
        },
    )

    return [
        ":test_consumer_pin_inherited_by_plain_build",
        ":test_consumer_pin_inherited_by_flagged_build",
        ":test_reset_restores_all_usable",
    ]

def variant_semantics_test_suite(name):
    """Registers generator, table-driven semantics, and cross-repo variant safety-net tests.

    Args:
        name: Name of the generated test_suite target.
    """
    test_names = _register_pin_inheritance_tests()
    for test_name, test_fn in [
        ("test_render_lock_build_overlapping_and_disjoint", _test_render_lock_build_overlapping_and_disjoint),
        ("test_render_lock_build_three_set_chain", _test_render_lock_build_three_set_chain),
        ("test_cross_repo_leak_393", _test_cross_repo_leak_393),
        ("test_pinned_repo_ignores_sibling_cli_flag", _test_pinned_repo_ignores_sibling_cli_flag),
        ("test_default_only_repo_fails_on_sibling_rival_flag", _test_default_only_repo_fails_on_sibling_rival_flag),
    ]:
        test_fn(test_name)
        test_names.append(":" + test_name)

    for case in _SEMANTICS_CASES:
        test_name = "test_variant_semantics_" + case.id
        _register_semantics_case_test(test_name, case)
        test_names.append(":" + test_name)

    native.test_suite(
        name = name,
        tests = test_names,
    )
