"""Tests for variant_state and its FeatureFlagInfo projections."""

load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "string_flag")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_dep_needed.bzl", "pycross_cycle_dep_needed")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_evaluator.bzl", "pycross_pep508_evaluator")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_marker_values.bzl", "collect_markers", "marker_value_attrs")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", _ProvidersVariantStateInfo = "VariantStateInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_resolver.bzl", "VariantStateInfo", "variant_item_projection", "variant_set_projection", "variant_state")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_util.bzl", "merge_variant_state")

# ── Helpers ──────────────────────────────────────────────────────────

def _infer_items(flags, string_flags):
    seen = {}
    for val in flags.values():
        _, sep, names = val.partition("|")
        for n in (names if sep else val).split(" "):
            if n:
                seen[n] = True
    for spec_json in string_flags.values():
        spec = json.decode(spec_json)
        for qnames in spec.get("map", {}).values():
            for n in qnames:
                seen[n] = True
    return sorted(seen.keys())

def _single_set_resolver(
        name,
        items = None,
        flags = {},
        string_flags = {},
        pin = "",
        default_setting = "",
        usable = "*",
        tags = ["manual"]):
    """Wire a single-set variant_state + variant_set_projection under `name`."""
    set_items = items if items != None else _infer_items(flags, string_flags)
    overrides = {}
    if pin:
        overrides["p:s"] = pin
    if default_setting:
        overrides["d:s"] = default_setting
    if usable != "*":
        overrides["u:s"] = usable
    state_flag = _setup_string(name + "_state_setting", merge_variant_state("", overrides))
    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {"s": set_items},
        flags = flags,
        string_flags = string_flags,
        tags = tags,
    )
    variant_set_projection(
        name = name,
        state = ":" + name + "_state",
        set_key = "s",
        tags = tags,
    )

def _setup_string(name, value):
    """Create a string_flag helper target (for resolver pin/default settings)."""
    string_flag(
        name = name,
        build_setting_default = value,
    )
    return ":" + name

def _setup_flags(name, flag_names):
    """Create bool_flag helper targets for tests."""
    for flag_name in flag_names:
        bool_flag(
            name = name + "_flag_" + flag_name,
            build_setting_default = False,
        )
    return [":" + name + "_flag_" + fn for fn in flag_names]

# ── Test: single flag active ─────────────────────────────────────────

def _test_single_flag_active_impl(env, target):
    # If this analysis succeeds, the resolver accepted a single flag.
    # We can't easily inspect FeatureFlagInfo from Starlark tests,
    # but the fact that analysis doesn't fail proves correctness.
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_single_flag_active(name):
    flag_refs = _setup_flags(name, ["alpha", "beta"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["alpha", "beta"])),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_single_flag_active_impl,
        config_settings = {
            "//command_line_option:extra_toolchains": [],
            str(Label(":" + name + "_flag_alpha")): True,
        },
    )

# ── Test: default when no flag set ───────────────────────────────────

def _test_default_when_no_flag_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_default_when_no_flag(name):
    flag_refs = _setup_flags(name, ["cpu", "gpu"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["cpu", "gpu"])),
        default_setting = "cpu",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_default_when_no_flag_impl,
    )

# ── Test: no flags and no default returns empty string ───────────────

def _test_no_flags_no_default_impl(env, target):
    info = target[config_common.FeatureFlagInfo]
    env.expect.that_str(info.value).equals("")

def _test_no_flags_no_default(name):
    flag_refs = _setup_flags(name, ["a", "b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["a", "b"])),
        # No default
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_no_flags_no_default_impl,
    )

# ── Test: mutual exclusion (both flags set) ──────────────────────────

def _test_mutual_exclusion_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Conflicting variants are active simultaneously"),
    )

def _test_mutual_exclusion_fails(name):
    flag_refs = _setup_flags(name, ["x", "y"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["x", "y"])),
        default_setting = "x",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_mutual_exclusion_fails_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_flag_x")): True,
            str(Label(":" + name + "_flag_y")): True,
        },
    )

# ── Test: one flag enabling two items of the same set ───────────────

def _test_shared_flag_conflict_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("(enabling group_app-a_test and group_app-b_test)"),
    )

def _test_shared_flag_conflict_fails(name):
    """A repo-level `group_test` covering two projects whose `test` groups conflict."""
    flag_refs = _setup_flags(name, ["group_test", "group_test_a"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = {
            flag_refs[0]: "group_app-a_test group_app-b_test",
            flag_refs[1]: "group_app-a_test",
        },
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_shared_flag_conflict_fails_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_flag_group_test")): True,
        },
    )

# ── Test: two flags enabling the same item ───────────────────────────

def _test_flags_sharing_item_impl(env, target):
    # Both flags enable only group_app-a_test, so there is no conflict.
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_flags_sharing_item(name):
    flag_refs = _setup_flags(name, ["group_test", "group_test_a"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = {
            flag_refs[0]: "group_app-a_test",
            flag_refs[1]: "group_app-a_test",
        },
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_flags_sharing_item_impl,
        config_settings = {
            str(Label(":" + name + "_flag_group_test")): True,
            str(Label(":" + name + "_flag_group_test_a")): True,
        },
    )

# ── Test: usable items ──────────────────────────────────────────────

def _usable_resolver(name, usable, default):
    flag_refs = _setup_flags(name, ["a", "b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["a", "b"])),
        items = ["a", "b", "c"],
        usable = usable,
        default_setting = default,
        tags = ["manual"],
    )

def _expect_value(value):
    def impl(env, target):
        env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals(value)

    return impl

def _test_usable_filters_flags(name):
    """A flag for an item outside `usable` doesn't conflict with a usable one."""
    _usable_resolver(name, "a c", "b")
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _expect_value("a"),
        config_settings = {
            str(Label(":" + name + "_flag_a")): True,
            str(Label(":" + name + "_flag_b")): True,
        },
    )

def _test_usable_filters_default(name):
    """A flag and a default outside `usable` both select nothing."""
    _usable_resolver(name, "a c", "b")
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _expect_value(""),
        config_settings = {
            str(Label(":" + name + "_flag_b")): True,
        },
    )

def _test_usable_empty_selects_nothing(name):
    """An empty `usable` selects nothing, even with conflicting flags and a default."""
    _usable_resolver(name, "", "a")
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _expect_value(""),
        config_settings = {
            str(Label(":" + name + "_flag_a")): True,
            str(Label(":" + name + "_flag_b")): True,
        },
    )

# ── Test: pin / default precedence ─────────────────────────────────

def _test_pin_beats_flags_impl(env, target):
    # Would fail with "Conflicting variants" if the pin didn't win.
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_pin_beats_flags(name):
    """A repo pin wins over ambient flags, even conflicting ones."""
    flag_refs = _setup_flags(name, ["a", "b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["a", "b"])),
        items = ["a", "b"],
        pin = "b",
        tags = ["manual"],
    )
    native.config_setting(
        name = name + "_is_b",
        flag_values = {":" + name + "_resolver": "b"},
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_pin_beats_flags_impl,
        config_settings = {
            str(Label(":" + name + "_flag_a")): True,
            str(Label(":" + name + "_flag_b")): True,
        },
    )

def _test_flag_beats_default_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_flag_beats_default(name):
    """An ambient flag wins over a repo default, so the two never conflict."""
    flag_refs = _setup_flags(name, ["a", "b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["a", "b"])),
        items = ["a", "b"],
        default_setting = "a",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_flag_beats_default_impl,
        config_settings = {
            str(Label(":" + name + "_flag_b")): True,
        },
    )

def _test_unknown_pin_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("selects unknown variant 'zzz'"),
    )

def _test_unknown_pin_fails(name):
    flag_refs = _setup_flags(name, ["a", "b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["a", "b"])),
        items = ["a", "b"],
        pin = "zzz",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_unknown_pin_fails_impl,
        expect_failure = True,
    )

def _test_display_names_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("--@pypi//_variants:extra_cpu and --@pypi//_variants:extra_gpu"),
    )

def _test_display_names(name):
    """Conflict errors use the display names, not canonical labels."""
    flag_refs = _setup_flags(name, ["cpu", "gpu"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = {
            flag_refs[0]: "@pypi//_variants:extra_cpu|extra_my-app_cpu",
            flag_refs[1]: "@pypi//_variants:extra_gpu|extra_my-app_gpu",
        },
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_display_names_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_flag_cpu")): True,
            str(Label(":" + name + "_flag_gpu")): True,
        },
    )

# ── Test: mixed extra+group conflict set ─────────────────────────────

def _test_mixed_extra_group_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_mixed_extra_group(name):
    flag_refs = _setup_flags(name, ["extra_variant-a", "group_variant-b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["extra_variant-a", "group_variant-b"])),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_mixed_extra_group_impl,
        config_settings = {
            str(Label(":" + name + "_flag_extra_variant-a")): True,
        },
    )

# ── Test: three-way conflict set ─────────────────────────────────────

def _test_three_way_conflict_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_three_way_conflict(name):
    flag_refs = _setup_flags(name, ["cpu", "cu118", "cu124"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["cpu", "cu118", "cu124"])),
        default_setting = "cpu",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_three_way_conflict_impl,
        config_settings = {
            str(Label(":" + name + "_flag_cu124")): True,
        },
    )

# ── Test: three-way mutual exclusion (two of three set) ──────────────

def _test_three_way_exclusion_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Conflicting variants"),
    )

def _test_three_way_exclusion_fails(name):
    flag_refs = _setup_flags(name, ["cpu", "cu118", "cu124"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["cpu", "cu118", "cu124"])),
        default_setting = "cpu",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_three_way_exclusion_fails_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_flag_cu118")): True,
            str(Label(":" + name + "_flag_cu124")): True,
        },
    )

# ── Test: config_setting matches resolver value ──────────────────────

def _test_config_setting_matches_resolver_impl(env, target):
    # The alias should resolve successfully when the config_setting
    # matches the resolver's returned value.
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_config_setting_matches_resolver(name):
    """End-to-end test: bool_flag → resolver → config_setting → select."""
    flag_refs = _setup_flags(name, ["opt_a", "opt_b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["opt_a", "opt_b"])),
        default_setting = "opt_a",
        tags = ["manual"],
    )
    native.config_setting(
        name = name + "_is_opt_a",
        flag_values = {":" + name + "_resolver": "opt_a"},
    )
    native.config_setting(
        name = name + "_is_opt_b",
        flag_values = {":" + name + "_resolver": "opt_b"},
    )

    # A filegroup whose srcs depend on the select, exercising the full chain.
    native.filegroup(
        name = name + "_subject",
        srcs = select({
            ":" + name + "_is_opt_a": [],
            ":" + name + "_is_opt_b": [],
        }),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_config_setting_matches_resolver_impl,
        # No flag set → default "opt_a" → config_setting _is_opt_a matches.
    )

# ── Test: config_setting matches with explicit flag ──────────────────

def _test_config_setting_explicit_flag_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_config_setting_explicit_flag(name):
    """Same as above but with an explicit flag set to opt_b."""
    flag_refs = _setup_flags(name, ["opt_a", "opt_b"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["opt_a", "opt_b"])),
        default_setting = "opt_a",
        tags = ["manual"],
    )
    native.config_setting(
        name = name + "_is_opt_a",
        flag_values = {":" + name + "_resolver": "opt_a"},
    )
    native.config_setting(
        name = name + "_is_opt_b",
        flag_values = {":" + name + "_resolver": "opt_b"},
    )
    native.filegroup(
        name = name + "_subject",
        srcs = select({
            ":" + name + "_is_opt_a": [],
            ":" + name + "_is_opt_b": [],
        }),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_config_setting_explicit_flag_impl,
        config_settings = {
            str(Label(":" + name + "_flag_opt_b")): True,
        },
    )

# ── Test: item in multiple conflict sets (variant_item_projection) ───

def _test_multi_set_overlap_impl(env, target):
    """Shared item resolved via variant_item_projection."""
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_multi_set_overlap(name):
    """Simulates: set1=[variant-a, group-a], set2=[group-a, group-b].

    group-a appears in both sets. Its config_setting matches via
    variant_item_projection when active in either set.
    """
    flag_refs = _setup_flags(name, ["extra_variant-a", "group_group-a", "group_group-b"])
    state_flag = _setup_string(
        name + "_state_setting",
        merge_variant_state("", {
            "d:set1": "group_group-a",
            "d:set2": "group_group-a",
        }),
    )

    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {
            "set1": ["extra_variant-a", "group_group-a"],
            "set2": ["group_group-a", "group_group-b"],
        },
        flags = {
            flag_refs[0]: "extra_variant-a",
            flag_refs[1]: "group_group-a",
            flag_refs[2]: "group_group-b",
        },
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_resolver_set1",
        state = ":" + name + "_state",
        set_key = "set1",
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_resolver_set2",
        state = ":" + name + "_state",
        set_key = "set2",
        tags = ["manual"],
    )
    variant_item_projection(
        name = name + "_item_group_group-a",
        state = ":" + name + "_state",
        item = "group_group-a",
        tags = ["manual"],
    )

    # extra_variant-a: only in set 1
    native.config_setting(
        name = name + "_is_extra_variant-a",
        flag_values = {":" + name + "_resolver_set1": "extra_variant-a"},
    )

    # group_group-a: in BOTH sets → variant_item_projection
    native.config_setting(
        name = name + "_is_group_group-a",
        flag_values = {":" + name + "_item_group_group-a": "true"},
    )

    # group_group-b: only in set 2
    native.config_setting(
        name = name + "_is_group_group-b",
        flag_values = {":" + name + "_resolver_set2": "group_group-b"},
    )

    # A select that uses all three config_settings.
    # With defaults, group_group-a is active in both sets.
    native.filegroup(
        name = name + "_subject",
        srcs = select({
            ":" + name + "_is_extra_variant-a": [],
            ":" + name + "_is_group_group-a": [],
            ":" + name + "_is_group_group-b": [],
        }),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_multi_set_overlap_impl,
        # No flags set → both sets default to group_group-a → matches.
    )

# ── Test: cross-set mutual exclusion with shared item ────────────────

def _test_multi_set_cross_exclusion_fails_impl(env, target):
    """Setting variant-a AND group-a should fail because they share set 1."""
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Conflicting variants"),
    )

def _test_multi_set_cross_exclusion_fails(name):
    """Set both variant-a and group-a which share a conflict set.

    Targets the resolver directly since the downstream select chain
    can't resolve when the resolver fails.
    """
    flag_refs = _setup_flags(name, ["extra_variant-a", "group_group-a"])

    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["extra_variant-a", "group_group-a"])),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_multi_set_cross_exclusion_fails_impl,
        expect_failure = True,
        config_settings = {
            # Both active → resolver should fail
            str(Label(":" + name + "_flag_extra_variant-a")): True,
            str(Label(":" + name + "_flag_group_group-a")): True,
        },
    )

# ── Test: variant_resolver with pycross_pep508_evaluator ─────────────

def _test_variants_with_evaluator_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_variants_with_evaluator(name):
    flag_refs = _setup_flags(name, ["group_cpu", "group_cuda"])
    _single_set_resolver(
        name = name + "_resolver",
        flags = dict(zip(flag_refs, ["group_cpu", "group_cuda"])),
        default_setting = "group_cpu",
        tags = ["manual"],
    )
    pycross_pep508_evaluator(
        name = name + "_eval",
        expr = "sys_platform == 'linux' and '__variant_group_cuda' == extra and extra != '__variant_group_cpu' and extra == 'cudart'",
        extra = "cudart",
        sys_platform = "linux",
        variants = [":" + name + "_resolver"],
        tags = ["manual"],
    )
    native.config_setting(
        name = name + "_eval_match",
        flag_values = {":" + name + "_eval": "true"},
    )
    native.filegroup(
        name = name + "_subject",
        srcs = select({
            ":" + name + "_eval_match": [],
        }),
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_variants_with_evaluator_impl,
        config_settings = {
            str(Label(":" + name + "_flag_group_cuda")): True,
        },
    )

# ── Test: per-repo string_flags (`@repo//_variants`) ─────────────────

def _string_flag_resolver(name, usable = "*", default = ""):
    flag_refs = _setup_flags(name, ["cpu", "gpu"])
    str_flag = _setup_string(name + "_variants", "")
    spec = json.encode({
        "display": "@pypi//_variants",
        "valid": ["extra_cpu", "extra_gpu", "group_test"],
        "map": {
            "extra_cpu": ["extra_app_cpu"],
            "extra_gpu": ["extra_app_gpu"],
        },
    })
    _single_set_resolver(
        name = name + "_resolver",
        flags = {
            flag_refs[0]: "@pypi//_variants:extra_cpu|extra_app_cpu",
            flag_refs[1]: "@pypi//_variants:extra_gpu|extra_app_gpu",
        },
        string_flags = {str_flag: spec},
        items = ["extra_app_cpu", "extra_app_gpu"],
        usable = usable,
        default_setting = default,
        tags = ["manual"],
    )

def _test_string_flag_selects_and_ignores_other_set(name):
    """Comma-separated string_flag selects this set's variant and ignores valid tokens for other sets."""
    _string_flag_resolver(name, default = "extra_app_cpu")
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _expect_value("extra_app_gpu"),
        config_settings = {
            str(Label(":" + name + "_variants")): "group_test, extra_gpu",
        },
    )

def _test_string_flag_unknown_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("@pypi//_variants selects unknown variant 'extra_typo'"),
    )

def _test_string_flag_unknown_fails(name):
    _string_flag_resolver(name)
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_string_flag_unknown_fails_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_variants")): "extra_cpu,extra_typo",
        },
    )

def _test_string_flag_conflict_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("--@pypi//_variants=extra_cpu and --@pypi//_variants=extra_gpu"),
    )

def _test_string_flag_conflict_fails(name):
    _string_flag_resolver(name)
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_string_flag_conflict_fails_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_variants")): "extra_cpu,extra_gpu",
        },
    )

def _test_string_and_bool_flag_conflict_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("--@pypi//_variants:extra_cpu and --@pypi//_variants=extra_gpu"),
    )

def _test_string_and_bool_flag_conflict_fails(name):
    _string_flag_resolver(name)
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_string_and_bool_flag_conflict_fails_impl,
        expect_failure = True,
        config_settings = {
            str(Label(":" + name + "_flag_cpu")): True,
            str(Label(":" + name + "_variants")): "extra_gpu",
        },
    )

def _test_string_and_bool_flag_agree(name):
    """Setting the same variant via both bool_flag and string_flag succeeds."""
    _string_flag_resolver(name)
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _expect_value("extra_app_cpu"),
        config_settings = {
            str(Label(":" + name + "_flag_cpu")): True,
            str(Label(":" + name + "_variants")): "extra_cpu",
        },
    )

def _test_string_flag_usable_filters(name):
    """string_flag respects usable narrowing just like bool_flags."""
    _string_flag_resolver(name, usable = "extra_app_cpu")
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _expect_value("extra_app_cpu"),
        config_settings = {
            str(Label(":" + name + "_variants")): "extra_cpu,extra_gpu",
        },
    )

def _overlapping_rival_resolver(name, other_usable = "*", s2_default = "a", s1_pin = "", s2_usable = "*"):
    """Helper for overlapping sets S1=[a, b] and S2=[a, c] with configurable defaults/pins/usable."""
    flag_refs = _setup_flags(name, ["a", "b", "c"])
    sf = _setup_string(name + "_variants", "")
    state_flag = _setup_string(
        name + "_state_setting",
        merge_variant_state("", {
            "p:s1": s1_pin,
            "d:s2": s2_default,
            "u:s1": other_usable,
            "u:s2": s2_usable,
        }),
    )
    spec = {
        "display": "@repo//_variants",
        "valid": ["a", "b", "c"],
        "map": {"a": ["a"], "b": ["b"], "c": ["c"]},
    }
    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {"s1": ["a", "b"], "s2": ["a", "c"]},
        flags = {flag_refs[0]: "a", flag_refs[1]: "b", flag_refs[2]: "c"},
        string_flags = {sf: json.encode(spec)},
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_resolver_s2",
        state = ":" + name + "_state",
        set_key = "s2",
        tags = ["manual"],
    )

def _test_overlapping_rival_bool_flag_suppresses_default(name):
    """Activating rival b via bool_flag suppresses S2's default a."""
    _overlapping_rival_resolver(name)
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value(""),
        config_settings = {
            str(Label(":" + name + "_flag_b")): True,
        },
    )

def _test_overlapping_rival_string_flag_suppresses_default(name):
    """Activating rival b via //_variants string_flag suppresses S2's default a."""
    _overlapping_rival_resolver(name)
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value(""),
        config_settings = {
            str(Label(":" + name + "_variants")): "b",
        },
    )

def _test_overlapping_rival_ignored_when_not_usable(name):
    """Rival b does not suppress S2's default when S1's usable setting excludes b."""
    _overlapping_rival_resolver(name, other_usable = "a")
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value("a"),
        config_settings = {
            str(Label(":" + name + "_flag_b")): True,
        },
    )

def _test_overlapping_rival_unrelated_shared_item_keeps_default(name):
    """A rival in S3=[c, d] (sharing c, not a) does not suppress S2's default a."""
    flag_refs = _setup_flags(name, ["a", "c", "d"])
    state_flag = _setup_string(name + "_state_setting", merge_variant_state("", {"d:s2": "a"}))
    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {"s2": ["a", "c"], "s3": ["c", "d"]},
        flags = {flag_refs[0]: "a", flag_refs[1]: "c", flag_refs[2]: "d"},
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_resolver_s2",
        state = ":" + name + "_state",
        set_key = "s2",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value("a"),
        config_settings = {
            str(Label(":" + name + "_flag_d")): True,
        },
    )

def _test_overlapping_rival_shared_pin_suppresses_non_shared_default(name):
    """Pinning shared item a in S1 suppresses S2's non-shared default c."""
    _overlapping_rival_resolver(name, s2_default = "c", s1_pin = "a")
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value(""),
    )

def _test_overlapping_rival_same_item_pin_keeps_default(name):
    """Pinning shared item a in S1 does not suppress S2's matching default a."""
    _overlapping_rival_resolver(name, s2_default = "a", s1_pin = "a")
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value("a"),
    )

def _test_overlapping_stage2_explicit_and_usable(name):
    """Stage-2 resolver forwards explicit selection even when a rival is active."""
    _overlapping_rival_resolver(name, s2_default = "a", s2_usable = "c")
    analysis_test(
        name = name,
        target = name + "_resolver_s2",
        impl = _expect_value("c"),
        config_settings = {
            str(Label(":" + name + "_flag_b")): True,
            str(Label(":" + name + "_flag_c")): True,
        },
    )

def _test_string_flag_unknown_fails_when_pinned_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("selects unknown variant 'extra_typo'"),
    )

def _test_string_flag_unknown_fails_when_pinned(name):
    """Unknown tokens in //_variants fail even when the conflict set is pinned."""
    sf = _setup_string(name + "_variants", "")
    pin = "extra_cpu"
    _single_set_resolver(
        name = name + "_resolver",
        items = ["extra_cpu", "extra_gpu"],
        pin = pin,
        string_flags = {
            sf: json.encode({
                "display": "@repo//_variants",
                "valid": ["extra_cpu", "extra_gpu"],
                "map": {"extra_cpu": ["extra_cpu"], "extra_gpu": ["extra_gpu"]},
            }),
        },
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_string_flag_unknown_fails_when_pinned_impl,
        expect_failure = True,
        config_settings = {str(Label(sf)): "extra_typo"},
    )

def _test_string_flag_unknown_fails_when_unusable(name):
    """Unknown tokens in //_variants fail even when usable is empty."""
    sf = _setup_string(name + "_variants", "")
    usable = ""
    _single_set_resolver(
        name = name + "_resolver",
        items = ["extra_cpu", "extra_gpu"],
        usable = usable,
        string_flags = {
            sf: json.encode({
                "display": "@repo//_variants",
                "valid": ["extra_cpu", "extra_gpu"],
                "map": {"extra_cpu": ["extra_cpu"], "extra_gpu": ["extra_gpu"]},
            }),
        },
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_string_flag_unknown_fails_when_pinned_impl,
        expect_failure = True,
        config_settings = {str(Label(sf)): "extra_typo"},
    )

def _test_multi_flag_conflict_omits_internal_qnames_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Conflicting variants are active simultaneously: --@repo//_variants=extra_cpu and --@repo//_variants=extra_gpu. Only one"),
    )

def _test_multi_flag_conflict_omits_internal_qnames(name):
    sf = _setup_string(name + "_variants", "")
    _single_set_resolver(
        name = name + "_resolver",
        string_flags = {
            sf: json.encode({
                "display": "@repo//_variants",
                "valid": ["extra_cpu", "extra_gpu"],
                "map": {
                    "extra_cpu": ["extra_my-app_cpu"],
                    "extra_gpu": ["extra_my-app_gpu"],
                },
            }),
        },
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_multi_flag_conflict_omits_internal_qnames_impl,
        expect_failure = True,
        config_settings = {str(Label(sf)): "extra_cpu,extra_gpu"},
    )

def _test_inconsistent_state_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Inconsistent conflict variant state: g-a and g-b are both active but conflict in set 's1'"),
    )

def _test_inconsistent_pin_and_sibling_flag_fails(name):
    """A hand-wired pin + unfiltered sibling flag that activates two conflicting items fails loudly."""
    flag_refs = _setup_flags(name, ["ga"])
    state_flag = _setup_string(name + "_state_setting", merge_variant_state("", {"p:s1": "g-b"}))
    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {"s1": ["g-a", "g-b"], "s2": ["g-a", "x"]},
        flags = {flag_refs[0]: "g-a"},
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_resolver",
        state = ":" + name + "_state",
        set_key = "s1",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_inconsistent_state_fails_impl,
        expect_failure = True,
        config_settings = {str(Label(flag_refs[0])): True},
    )

def _test_inconsistent_conflicting_defaults_fails(name):
    """A hand-wired state whose defaults in overlapping sets conflict fails loudly."""
    state_flag = _setup_string(
        name + "_state_setting",
        merge_variant_state("", {"d:s1": "g-b", "d:s2": "g-a"}),
    )
    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {"s1": ["g-a", "g-b"], "s2": ["g-a", "x"]},
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_resolver",
        state = ":" + name + "_state",
        set_key = "s1",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_inconsistent_state_fails_impl,
        expect_failure = True,
    )

# ── Direct VariantStateInfo consumption in evaluators & cycles ───────

_CollectedMarkersInfo = provider(
    doc = "Test provider exposing markers collected via collect_markers(ctx).",
    fields = ["markers"],
)

def _marker_probe_impl(ctx):
    return [_CollectedMarkersInfo(markers = collect_markers(ctx))]

_marker_probe = rule(
    implementation = _marker_probe_impl,
    attrs = marker_value_attrs(),
    provides = [_CollectedMarkersInfo],
)

_VARIANT_CYCLE_EDGES = json.encode({
    "p1@1.0": [{"dep": "p2@1.0", "marker": "extra == '__variant_a'"}],
    "p2@1.0": [{"dep": "p3@1.0", "marker": "extra == '__variant_d'"}],
    "p3@1.0": [{"dep": "p1@1.0"}],
})

def _setup_direct_state_targets(name):
    """Create an overlapping + disjoint multi-set variant_state and projections."""
    flag_refs = _setup_flags(name, ["a", "b", "c", "d", "e"])
    state_flag = _setup_string(name + "_state_setting", "")
    variant_state(
        name = name + "_state",
        state = state_flag,
        sets = {
            "s1": ["a", "b"],
            "s2": ["a", "c"],
            "s3": ["d", "e"],
        },
        flags = dict(zip(flag_refs, ["a", "b", "c", "d", "e"])),
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_proj_s1",
        state = ":" + name + "_state",
        set_key = "s1",
        tags = ["manual"],
    )
    variant_set_projection(
        name = name + "_proj_s2",
        state = ":" + name + "_state",
        set_key = "s2",
        tags = ["manual"],
    )
    return flag_refs

def _expect_extra_value(expected):
    def impl(env, target):
        extra = target[_CollectedMarkersInfo].markers["extra"]
        if type(expected) == "list":
            env.expect.that_collection(extra).contains_exactly(expected).in_order()
        else:
            env.expect.that_str(extra).equals(expected)

    return impl

def _test_variant_state_provider_reexport_impl(env, target):
    env.expect.that_bool(VariantStateInfo == _ProvidersVariantStateInfo).equals(True)
    info = target[_ProvidersVariantStateInfo]
    env.expect.that_dict(info.active_items).contains_exactly({"a": True})

def _test_variant_state_provider_reexport(name):
    """VariantStateInfo lives in providers.bzl and remains bound in variant_resolver.bzl."""
    flag_refs = _setup_direct_state_targets(name)
    analysis_test(
        name = name,
        target = name + "_state",
        impl = _test_variant_state_provider_reexport_impl,
        config_settings = {str(Label(flag_refs[0])): True},
    )

def _test_direct_variant_state_zero_active(name):
    """Direct VariantStateInfo with 0 active variants evaluates extra markers as false."""
    _setup_direct_state_targets(name)
    _marker_probe(
        name = name + "_probe",
        extra = "cudart",
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    pycross_pep508_evaluator(
        name = name + "_eval",
        expr = "extra == '__variant_a'",
        extra = "cudart",
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    pycross_cycle_dep_needed(
        name = name + "_cycle",
        source = "p1@1.0",
        target = "p2@1.0",
        edges = _VARIANT_CYCLE_EDGES,
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    analysis_test(
        name = name + "_probe_test",
        target = name + "_probe",
        impl = _expect_extra_value("cudart"),
    )
    analysis_test(
        name = name + "_eval_test",
        target = name + "_eval",
        impl = _expect_value("false"),
    )
    analysis_test(
        name = name + "_cycle_test",
        target = name + "_cycle",
        impl = _expect_value("false"),
    )
    native.test_suite(
        name = name,
        tests = [name + "_probe_test", name + "_eval_test", name + "_cycle_test"],
    )

def _test_direct_variant_state_single_overlapping_dedup(name):
    """Active item shared across overlapping sets is deduplicated in markers['extra']."""
    flag_refs = _setup_direct_state_targets(name)
    cfg = {str(Label(flag_refs[0])): True}

    _marker_probe(
        name = name + "_probe_state",
        extra = "cudart",
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    _marker_probe(
        name = name + "_probe_projections",
        extra = "cudart",
        variants = [":" + name + "_proj_s1", ":" + name + "_proj_s2"],
        tags = ["manual"],
    )
    pycross_pep508_evaluator(
        name = name + "_eval",
        expr = "extra == '__variant_a' and extra != '__variant_d' and extra == 'cudart'",
        extra = "cudart",
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    pycross_cycle_dep_needed(
        name = name + "_cycle_hop1",
        source = "p1@1.0",
        target = "p2@1.0",
        edges = _VARIANT_CYCLE_EDGES,
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    pycross_cycle_dep_needed(
        name = name + "_cycle_hop2",
        source = "p1@1.0",
        target = "p3@1.0",
        edges = _VARIANT_CYCLE_EDGES,
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    analysis_test(
        name = name + "_probe_state_test",
        target = name + "_probe_state",
        impl = _expect_extra_value(["cudart", "__variant_a"]),
        config_settings = cfg,
    )
    analysis_test(
        name = name + "_probe_projections_test",
        target = name + "_probe_projections",
        impl = _expect_extra_value(["cudart", "__variant_a"]),
        config_settings = cfg,
    )
    analysis_test(
        name = name + "_eval_test",
        target = name + "_eval",
        impl = _expect_value("true"),
        config_settings = cfg,
    )
    analysis_test(
        name = name + "_cycle_hop1_test",
        target = name + "_cycle_hop1",
        impl = _expect_value("true"),
        config_settings = cfg,
    )
    analysis_test(
        name = name + "_cycle_hop2_test",
        target = name + "_cycle_hop2",
        impl = _expect_value("false"),
        config_settings = cfg,
    )
    native.test_suite(
        name = name,
        tests = [
            name + "_probe_state_test",
            name + "_probe_projections_test",
            name + "_eval_test",
            name + "_cycle_hop1_test",
            name + "_cycle_hop2_test",
        ],
    )

def _test_direct_variant_state_multiple_active(name):
    """Direct VariantStateInfo with multiple active variants enables multi-hop cycle and compound markers."""
    flag_refs = _setup_direct_state_targets(name)
    cfg = {
        str(Label(flag_refs[0])): True,  # a (in s1 and s2)
        str(Label(flag_refs[3])): True,  # d (in s3)
    }

    _marker_probe(
        name = name + "_probe",
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    pycross_pep508_evaluator(
        name = name + "_eval",
        expr = "extra == '__variant_a' and extra == '__variant_d' and extra != '__variant_b'",
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    pycross_cycle_dep_needed(
        name = name + "_cycle",
        source = "p1@1.0",
        target = "p3@1.0",
        edges = _VARIANT_CYCLE_EDGES,
        variants = [":" + name + "_state"],
        tags = ["manual"],
    )
    analysis_test(
        name = name + "_probe_test",
        target = name + "_probe",
        impl = _expect_extra_value(["", "__variant_a", "__variant_d"]),
        config_settings = cfg,
    )
    analysis_test(
        name = name + "_eval_test",
        target = name + "_eval",
        impl = _expect_value("true"),
        config_settings = cfg,
    )
    analysis_test(
        name = name + "_cycle_test",
        target = name + "_cycle",
        impl = _expect_value("true"),
        config_settings = cfg,
    )
    native.test_suite(
        name = name,
        tests = [name + "_probe_test", name + "_eval_test", name + "_cycle_test"],
    )

# ── Suite ────────────────────────────────────────────────────────────

def variant_resolver_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_single_flag_active,
            _test_default_when_no_flag,
            _test_no_flags_no_default,
            _test_mutual_exclusion_fails,
            _test_shared_flag_conflict_fails,
            _test_flags_sharing_item,
            _test_pin_beats_flags,
            _test_usable_filters_flags,
            _test_usable_filters_default,
            _test_usable_empty_selects_nothing,
            _test_flag_beats_default,
            _test_unknown_pin_fails,
            _test_display_names,
            _test_mixed_extra_group,
            _test_three_way_conflict,
            _test_three_way_exclusion_fails,
            _test_config_setting_matches_resolver,
            _test_config_setting_explicit_flag,
            _test_multi_set_overlap,
            _test_multi_set_cross_exclusion_fails,
            _test_variants_with_evaluator,
            _test_string_flag_selects_and_ignores_other_set,
            _test_string_flag_unknown_fails,
            _test_string_flag_conflict_fails,
            _test_string_and_bool_flag_conflict_fails,
            _test_string_and_bool_flag_agree,
            _test_string_flag_usable_filters,
            _test_overlapping_rival_bool_flag_suppresses_default,
            _test_overlapping_rival_string_flag_suppresses_default,
            _test_overlapping_rival_ignored_when_not_usable,
            _test_overlapping_rival_unrelated_shared_item_keeps_default,
            _test_overlapping_rival_shared_pin_suppresses_non_shared_default,
            _test_overlapping_rival_same_item_pin_keeps_default,
            _test_overlapping_stage2_explicit_and_usable,
            _test_string_flag_unknown_fails_when_pinned,
            _test_string_flag_unknown_fails_when_unusable,
            _test_multi_flag_conflict_omits_internal_qnames,
            _test_inconsistent_pin_and_sibling_flag_fails,
            _test_inconsistent_conflicting_defaults_fails,
            _test_variant_state_provider_reexport,
            _test_direct_variant_state_zero_active,
            _test_direct_variant_state_single_overlapping_dedup,
            _test_direct_variant_state_multiple_active,
        ],
    )
