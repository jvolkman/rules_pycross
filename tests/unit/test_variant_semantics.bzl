"""Generator, table-driven semantics, and cross-repo safety-net tests for conflict variants."""

load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "string_flag")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "render_lock_build_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_resolver.bzl", "pycross_no_variant_selected", "variant_resolver")

_VariantTupleInfo = provider(
    doc = "Resolved variant values across a set of resolvers.",
    fields = {"values": "dict[str, str]: set_id -> resolved FeatureFlagInfo value."},
)

def _variant_tuple_impl(ctx):
    values = {}
    for target, set_id in ctx.attr.resolvers.items():
        values[set_id] = target[config_common.FeatureFlagInfo].value
    return [_VariantTupleInfo(values = values)]

_variant_tuple = rule(
    implementation = _variant_tuple_impl,
    attrs = {
        "resolvers": attr.label_keyed_string_dict(
            providers = [config_common.FeatureFlagInfo],
        ),
    },
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
    """Overlapping sets emit two-stage _explicit_/_resolver_ with rival_resolvers; disjoint sets stay single-stage."""
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

    # Set 1 ([group_g-a, group_g-b]) has _explicit_ (pin/flags/string_flags/usable, NO default_setting)
    # and _resolver_ (explicit/default_setting/usable/items/rival_resolvers).
    exp1 = _extract_block(rendered, "_explicit_group_g-a_group_g-b")
    env.expect.that_str(exp1).contains('pin = ":_pin_group_g-a_group_g-b",')
    env.expect.that_str(exp1).contains('usable = ":_usable_group_g-a_group_g-b",')
    env.expect.that_str(exp1).contains("flags = {")
    env.expect.that_str(exp1).contains("string_flags = {")
    env.expect.that_bool("default_setting" in exp1).equals(False)

    res1 = _extract_block(rendered, "_resolver_group_g-a_group_g-b")
    env.expect.that_str(res1).contains('explicit = ":_explicit_group_g-a_group_g-b",')
    env.expect.that_str(res1).contains('default_setting = ":_default_group_g-a_group_g-b",')
    env.expect.that_str(res1).contains('usable = ":_usable_group_g-a_group_g-b",')
    env.expect.that_str(res1).contains('items = ["group_g-a","group_g-b"],')
    env.expect.that_str(res1).contains('":_explicit_extra_x_group_g-a": "group_g-a",')

    # Set 2 ([extra_x, group_g-a]) mirrors Set 1.
    exp2 = _extract_block(rendered, "_explicit_extra_x_group_g-a")
    env.expect.that_str(exp2).contains('pin = ":_pin_extra_x_group_g-a",')
    env.expect.that_bool("default_setting" in exp2).equals(False)

    res2 = _extract_block(rendered, "_resolver_extra_x_group_g-a")
    env.expect.that_str(res2).contains('explicit = ":_explicit_extra_x_group_g-a",')
    env.expect.that_str(res2).contains('default_setting = ":_default_extra_x_group_g-a",')
    env.expect.that_str(res2).contains('":_explicit_group_g-a_group_g-b": "group_g-a",')

    # Disjoint set ([extra_p, extra_q]) gets a single resolver directly (no _explicit_, no rival_resolvers).
    env.expect.that_bool("_explicit_extra_p_extra_q" in rendered).equals(False)
    res_disjoint = _extract_block(rendered, "_resolver_extra_p_extra_q")
    env.expect.that_str(res_disjoint).contains('pin = ":_pin_extra_p_extra_q",')
    env.expect.that_str(res_disjoint).contains('default_setting = ":_default_extra_p_extra_q",')
    env.expect.that_str(res_disjoint).contains('usable = ":_usable_extra_p_extra_q",')
    env.expect.that_bool("rival_resolvers" in res_disjoint).equals(False)

    # Shared item `group_g-a` emits via config_settings + match_any group.
    env.expect.that_str(rendered).contains('name = "_is_group_g-a_via_0",')
    env.expect.that_str(rendered).contains('name = "_is_group_g-a_via_1",')
    env.expect.that_str(rendered).contains('name = "is_group_g-a",')

def _test_render_lock_build_overlapping_and_disjoint(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_render_lock_build_overlapping_and_disjoint_impl)

# buildifier: disable=unused-variable
def _test_render_lock_build_three_set_chain_impl(env, target):
    """A 3-set chain wires both neighbors into the middle set's rival_resolvers."""
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

    mid = _extract_block(rendered, "_resolver_extra_x_group_g-a")
    env.expect.that_str(mid).contains('":_explicit_extra_x_extra_y": "extra_x",')
    env.expect.that_str(mid).contains('":_explicit_group_g-a_group_g-b": "group_g-a",')

    end1 = _extract_block(rendered, "_resolver_group_g-a_group_g-b")
    env.expect.that_str(end1).contains('":_explicit_extra_x_group_g-a": "group_g-a",')
    env.expect.that_bool("_explicit_extra_x_extra_y" in end1).equals(False)

    end3 = _extract_block(rendered, "_resolver_extra_x_extra_y")
    env.expect.that_str(end3).contains('":_explicit_extra_x_group_g-a": "extra_x",')
    env.expect.that_bool("_explicit_group_g-a_group_g-b" in end3).equals(False)

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
    """Wire a 3-set overlapping chain of variant_resolvers and return (tuple_target, flag_labels)."""
    bool_labels = {}
    for item in _CHAIN_ALL_ITEMS:
        fname = "{}_bf_{}".format(prefix, item)
        util.helper_target(bool_flag, name = fname, build_setting_default = False)
        bool_labels[item] = ":" + fname

    sf_name = "{}_variants".format(prefix)
    util.helper_target(string_flag, name = sf_name, build_setting_default = "")
    sf_label = ":" + sf_name

    # First stage: explicit resolvers (pins + bool_flags + string_flags + usable).
    explicit_labels = {}
    usable_labels = {}
    for sid, items in sorted(_CHAIN_SETS.items()):
        pin_name = "{}_pin_{}".format(prefix, sid)
        usable_name = "{}_usable_{}".format(prefix, sid)
        util.helper_target(string_flag, name = pin_name, build_setting_default = pins.get(sid, ""))
        util.helper_target(string_flag, name = usable_name, build_setting_default = usables.get(sid, "*"))
        usable_labels[sid] = ":" + usable_name

        exp_name = "{}_explicit_{}".format(prefix, sid)
        spec = {
            "display": "@repo//_variants",
            "valid": list(_CHAIN_ALL_ITEMS),
            "map": {item: [item] for item in items},
        }
        util.helper_target(
            variant_resolver,
            name = exp_name,
            items = items,
            pin = ":" + pin_name,
            usable = ":" + usable_name,
            flags = {bool_labels[item]: "@repo//_variants:{}|{}".format(item, item) for item in items},
            string_flags = {sf_label: json.encode(spec)},
        )
        explicit_labels[sid] = ":" + exp_name

    # Second stage: final resolvers with defaults and rival_resolvers.
    resolver_map = {}
    for sid, items in sorted(_CHAIN_SETS.items()):
        def_name = "{}_default_{}".format(prefix, sid)
        util.helper_target(string_flag, name = def_name, build_setting_default = defaults.get(sid, ""))

        rivals = {}
        for other_sid, other_items in sorted(_CHAIN_SETS.items()):
            if other_sid == sid:
                continue
            shared = [q for q in items if q in other_items]
            if shared:
                rivals[explicit_labels[other_sid]] = " ".join(shared)

        res_name = "{}_resolver_{}".format(prefix, sid)
        util.helper_target(
            variant_resolver,
            name = res_name,
            explicit = explicit_labels[sid],
            default_setting = ":" + def_name,
            usable = usable_labels[sid],
            items = items,
            rival_resolvers = rivals,
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
        id = "pin_gb_beats_flag_in_s1",
        pins = {"s1": "g-b"},
        defaults = {"s1": "g-a", "s2": "g-a"},
        bools = ["g-a"],
        expected = {"s1": "g-b", "s2": "g-a", "s3": ""},
    ),
    struct(
        id = "pin_gb_suppresses_s2_default",
        pins = {"s1": "g-b"},
        defaults = {"s1": "g-a", "s2": "g-a"},
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "pin_gb_with_s2_usable_x_suppresses_s2_default",
        pins = {"s1": "g-b"},
        defaults = {"s1": "g-a", "s2": "g-a"},
        usables = {"s2": "x"},
        expected = {"s1": "g-b", "s2": "", "s3": ""},
    ),
    struct(
        id = "pin_ga_ignores_rival_flags",
        pins = {"s1": "g-a", "s2": "g-a"},
        bools = ["g-b"],
        variants = "x",
        expected = {"s1": "g-a", "s2": "g-a", "s3": "x"},
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
        env.expect.that_dict(target[_VariantTupleInfo].values).contains_exactly(expected)

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
        variant_resolver,
        name = name + "_explicit_s1",
        items = ["extra_cpu", "extra_gpu"],
        pin = ":" + pin_s1,
        usable = ":" + usable_s1,
        flags = {":" + sibling_cpu: "@runtime//_variants:extra_cpu|extra_cpu"},
    )
    util.helper_target(
        variant_resolver,
        name = name + "_explicit_s2",
        items = ["extra_cpu", "group_gpu-test"],
        usable = ":" + usable_s2,
        flags = {":" + sibling_cpu: "@runtime//_variants:extra_cpu|extra_cpu"},
    )
    util.helper_target(
        variant_resolver,
        name = name + "_resolver_s2",
        explicit = ":" + name + "_explicit_s2",
        usable = ":" + usable_s2,
        items = ["extra_cpu", "group_gpu-test"],
        rival_resolvers = {":" + name + "_explicit_s1": "extra_cpu"},
    )
    util.helper_target(
        _variant_tuple,
        name = name + "_tuple",
        resolvers = {
            ":" + name + "_explicit_s1": "s1",
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

def variant_semantics_test_suite(name):
    """Registers generator, table-driven semantics, and cross-repo variant safety-net tests.

    Args:
        name: Name of the generated test_suite target.
    """
    test_names = []
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
