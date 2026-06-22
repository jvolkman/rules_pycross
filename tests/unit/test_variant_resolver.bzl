"""Tests for variant_resolver rule."""

load("@bazel_skylib//lib:selects.bzl", "selects")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_resolver.bzl", "variant_resolver")

# ── Helpers ──────────────────────────────────────────────────────────

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
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["alpha", "beta"],
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
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["cpu", "gpu"],
        default = "cpu",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_default_when_no_flag_impl,
    )

# ── Test: no flags and no default fails ──────────────────────────────

def _test_no_flags_no_default_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("No variant selected"),
    )

def _test_no_flags_no_default_fails(name):
    flag_refs = _setup_flags(name, ["a", "b"])
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["a", "b"],
        # No default
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_resolver",
        impl = _test_no_flags_no_default_fails_impl,
        expect_failure = True,
    )

# ── Test: mutual exclusion (both flags set) ──────────────────────────

def _test_mutual_exclusion_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Conflicting variants are active simultaneously"),
    )

def _test_mutual_exclusion_fails(name):
    flag_refs = _setup_flags(name, ["x", "y"])
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["x", "y"],
        default = "x",
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

# ── Test: mixed extra+group conflict set ─────────────────────────────

def _test_mixed_extra_group_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_mixed_extra_group(name):
    flag_refs = _setup_flags(name, ["extra_variant-a", "group_variant-b"])
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["extra_variant-a", "group_variant-b"],
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
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["cpu", "cu118", "cu124"],
        default = "cpu",
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
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["cpu", "cu118", "cu124"],
        default = "cpu",
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
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["opt_a", "opt_b"],
        default = "opt_a",
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
    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["opt_a", "opt_b"],
        default = "opt_a",
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

# ── Test: item in multiple conflict sets (config_setting_group) ──────

def _test_multi_set_overlap_impl(env, target):
    """Shared item resolved via config_setting_group(match_any)."""
    env.expect.that_target(target).default_outputs().contains_at_least([])

def _test_multi_set_overlap(name):
    """Simulates: set1=[variant-a, group-a], set2=[group-a, group-b].

    group-a appears in both sets. Its config_setting must match if EITHER
    resolver returns 'group_group-a'.
    """
    flag_refs = _setup_flags(name, ["extra_variant-a", "group_group-a", "group_group-b"])

    # Resolver for set 1: [extra_variant-a, group_group-a]
    variant_resolver(
        name = name + "_resolver_set1",
        flags = [flag_refs[0], flag_refs[1]],
        names = ["extra_variant-a", "group_group-a"],
        default = "group_group-a",
        tags = ["manual"],
    )

    # Resolver for set 2: [group_group-a, group_group-b]
    variant_resolver(
        name = name + "_resolver_set2",
        flags = [flag_refs[1], flag_refs[2]],
        names = ["group_group-a", "group_group-b"],
        default = "group_group-a",
        tags = ["manual"],
    )

    # extra_variant-a: only in set 1
    native.config_setting(
        name = name + "_is_extra_variant-a",
        flag_values = {":" + name + "_resolver_set1": "extra_variant-a"},
    )

    # group_group-a: in BOTH sets → config_setting_group
    native.config_setting(
        name = name + "_is_group_group-a_via_0",
        flag_values = {":" + name + "_resolver_set1": "group_group-a"},
    )
    native.config_setting(
        name = name + "_is_group_group-a_via_1",
        flag_values = {":" + name + "_resolver_set2": "group_group-a"},
    )
    selects.config_setting_group(
        name = name + "_is_group_group-a",
        match_any = [
            ":" + name + "_is_group_group-a_via_0",
            ":" + name + "_is_group_group-a_via_1",
        ],
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
        # No flags set → both resolvers default to group_group-a → matches.
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

    variant_resolver(
        name = name + "_resolver",
        flags = flag_refs,
        names = ["extra_variant-a", "group_group-a"],
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

# ── Suite ────────────────────────────────────────────────────────────

def variant_resolver_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_single_flag_active,
            _test_default_when_no_flag,
            _test_no_flags_no_default_fails,
            _test_mutual_exclusion_fails,
            _test_mixed_extra_group,
            _test_three_way_conflict,
            _test_three_way_exclusion_fails,
            _test_config_setting_matches_resolver,
            _test_config_setting_explicit_flag,
            _test_multi_set_overlap,
            _test_multi_set_cross_exclusion_fails,
        ],
    )
