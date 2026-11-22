"""Tests for parse_dependency_group_entries in lock_common.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_common.bzl", "parse_dependency_group_entries")

# buildifier: disable=bzl-visibility
load("//pycross/private:translator_common.bzl", "compute_requested_dependency_groups", "resolve_lock_graph")

# --- test: basic testonly group ---

# buildifier: disable=unused-variable
def _test_parse_basic_testonly_impl(env, target):
    """['default', 'group:dev;testonly'] -> group:dev is testonly."""
    result = parse_dependency_group_entries(["default", "group:dev;testonly"])

    env.expect.that_collection(result.dependency_groups).contains_exactly(["default", "group:dev"])
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["default"])
    env.expect.that_bool(result.wildcard_testonly).equals(False)

def _test_parse_basic_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_basic_testonly_impl)

# --- test: wildcard then specific testonly ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_then_specific_testonly_impl(env, target):
    """['*', 'group:dev;testonly'] -> wildcard not testonly, group:dev overrides to testonly."""
    result = parse_dependency_group_entries(["*", "group:dev;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_wildcard_then_specific_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_then_specific_testonly_impl)

# --- test: specific testonly then wildcard resets ---

# buildifier: disable=unused-variable
def _test_parse_specific_testonly_then_wildcard_impl(env, target):
    """['group:dev;testonly', '*'] -> * comes last, resets group:dev's testonly."""
    result = parse_dependency_group_entries(["group:dev;testonly", "*"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_specific_testonly_then_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_specific_testonly_then_wildcard_impl)

# --- test: wildcard testonly with specific override ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_testonly_with_override_impl(env, target):
    """['*;testonly', 'group:dev'] -> everything testonly except group:dev."""
    result = parse_dependency_group_entries(["*;testonly", "group:dev"])

    env.expect.that_bool(result.wildcard_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["group:dev"])

def _test_parse_wildcard_testonly_with_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_testonly_with_override_impl)

# --- test: wildcard testonly alone ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_testonly_alone_impl(env, target):
    """['*;testonly'] -> everything testonly, no overrides."""
    result = parse_dependency_group_entries(["*;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_wildcard_testonly_alone(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_testonly_alone_impl)

# --- test: no testonly at all ---

# buildifier: disable=unused-variable
def _test_parse_no_testonly_impl(env, target):
    """['default', 'group:dev'] -> nothing testonly."""
    result = parse_dependency_group_entries(["default", "group:dev"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["default", "group:dev"])

def _test_parse_no_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_no_testonly_impl)

# --- test: transitive with testonly ---

# buildifier: disable=unused-variable
def _test_parse_transitive_testonly_impl(env, target):
    """['default', 'group:dev;testonly', 'transitive;testonly'] -> transitive_testonly is True."""
    result = parse_dependency_group_entries(["default", "group:dev;testonly", "transitive;testonly"])

    env.expect.that_bool(result.include_transitive).equals(True)
    env.expect.that_bool(result.transitive_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])

    # "transitive" should NOT appear in dependency_groups
    env.expect.that_collection(result.dependency_groups).contains_exactly(["default", "group:dev"])

def _test_parse_transitive_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_transitive_testonly_impl)

# --- test: double wildcard, last wins ---

# buildifier: disable=unused-variable
def _test_parse_double_wildcard_impl(env, target):
    """['*;testonly', 'group:dev;testonly', '*', 'group:test;testonly'] -> second * resets.

    First *;testonly sets wildcard_testonly=True.
    group:dev;testonly is a specific override.
    Second * (not testonly) resets wildcard_testonly=False and clears group:dev override.
    group:test;testonly is a new specific override after the second *.
    """
    result = parse_dependency_group_entries(["*;testonly", "group:dev;testonly", "*", "group:test;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)

    # group:dev;testonly was before the second *, so it's reset
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:test"])
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_double_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_double_wildcard_impl)

# --- Test suite ---

# --- tests: invalid specs fail, for every lock format ---

def _bad_groups_subject_impl(ctx):
    parsed = parse_dependency_group_entries(ctx.attr.groups)
    compute_requested_dependency_groups(
        dependency_groups = parsed.dependency_groups,
        testonly_groups = parsed.testonly_groups,
        non_testonly_groups = parsed.non_testonly_groups,
        wildcard_testonly = parsed.wildcard_testonly,
        available_groups = ["default", "optional:extra1", "group:dev"],
        project_name = "proj",
    )
    return []

_bad_groups_subject = rule(
    implementation = _bad_groups_subject_impl,
    attrs = {"groups": attr.string_list()},
)

def _bad_groups_test(name, groups, expected):
    util.helper_target(_bad_groups_subject, name = name + "_subject", groups = groups)
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = lambda env, target: env.expect.that_target(target).failures().contains_predicate(matching.contains(expected)),
        expect_failure = True,
    )

def _test_unprefixed_typo_fails(name):
    _bad_groups_test(name, ["dfault"], "Unknown dependency group 'dfault'")

def _test_unknown_kind_wildcard_fails(name):
    _bad_groups_test(name, ["grp:*"], "Unknown dependency group 'grp:*'")

def _test_missing_group_fails(name):
    _bad_groups_test(name, ["group:nope"], "Project 'proj' does not have group 'group:nope'")

def _test_unknown_modifier_fails(name):
    _bad_groups_test(name, ["group:dev;testnly"], "Unknown modifier ';testnly'")

# buildifier: disable=unused-variable
def _test_kind_wildcard_testonly_after_star_impl(env, target):
    """Verify kind:*;testonly after * (and kind:* after *;testonly) applies to matching groups."""
    available = ["default", "optional:extra1", "group:dev", "group:test"]

    parsed = parse_dependency_group_entries(["*", "group:*;testonly"])
    req = compute_requested_dependency_groups(
        parsed.dependency_groups,
        parsed.testonly_groups,
        parsed.non_testonly_groups,
        parsed.wildcard_testonly,
        available,
    )
    env.expect.that_dict(req).contains_exactly({
        "default": False,
        "optional:extra1": False,
        "group:dev": True,
        "group:test": True,
    })

    # Specific group after kind:*;testonly overrides just that group.
    parsed2 = parse_dependency_group_entries(["*", "group:*;testonly", "group:dev"])
    req2 = compute_requested_dependency_groups(
        parsed2.dependency_groups,
        parsed2.testonly_groups,
        parsed2.non_testonly_groups,
        parsed2.wildcard_testonly,
        available,
    )
    env.expect.that_dict(req2).contains_exactly({
        "default": False,
        "optional:extra1": False,
        "group:dev": False,
        "group:test": True,
    })

    # kind:*;testonly after specific group:dev supersedes earlier group:dev.
    parsed3 = parse_dependency_group_entries(["*", "group:dev", "group:*;testonly"])
    req3 = compute_requested_dependency_groups(
        parsed3.dependency_groups,
        parsed3.testonly_groups,
        parsed3.non_testonly_groups,
        parsed3.wildcard_testonly,
        available,
    )
    env.expect.that_dict(req3).contains_exactly({
        "default": False,
        "optional:extra1": False,
        "group:dev": True,
        "group:test": True,
    })

    # kind:* non-testonly after *;testonly overrides just that kind to non-testonly.
    parsed4 = parse_dependency_group_entries(["*;testonly", "group:*"])
    req4 = compute_requested_dependency_groups(
        parsed4.dependency_groups,
        parsed4.testonly_groups,
        parsed4.non_testonly_groups,
        parsed4.wildcard_testonly,
        available,
    )
    env.expect.that_dict(req4).contains_exactly({
        "default": True,
        "optional:extra1": True,
        "group:dev": False,
        "group:test": False,
    })

    # Without '*': kind:*;testonly followed by specific group:dev keeps group:dev non-testonly,
    # while specific group:dev followed by kind:*;testonly marks both group:dev and group:test testonly.
    parsed5 = parse_dependency_group_entries(["group:*;testonly", "group:dev"])
    req5 = compute_requested_dependency_groups(
        parsed5.dependency_groups,
        parsed5.testonly_groups,
        parsed5.non_testonly_groups,
        parsed5.wildcard_testonly,
        available,
    )
    env.expect.that_dict(req5).contains_exactly({"group:dev": False, "group:test": True})

    parsed6 = parse_dependency_group_entries(["group:dev", "group:*;testonly"])
    req6 = compute_requested_dependency_groups(
        parsed6.dependency_groups,
        parsed6.testonly_groups,
        parsed6.non_testonly_groups,
        parsed6.wildcard_testonly,
        available,
    )
    env.expect.that_dict(req6).contains_exactly({"group:dev": True, "group:test": True})

def _test_kind_wildcard_testonly_after_star(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_kind_wildcard_testonly_after_star_impl)

# buildifier: disable=unused-variable
def _test_local_chain_cycle_testonly_and_dep_merge_impl(env, target):
    """Verify deep local member chains, local cycles, testonly propagation, and marker/extra dep merge dedup."""
    packages = [
        # 3-hop local chain: lib-a -> lib-b -> lib-c -> third-party (plus local cycle lib-c -> lib-a).
        {"name": "lib-a", "version": "0.1.0", "is_local": True, "files": [], "dependencies": [{"name": "lib-b", "specifier": "==0.1.0"}]},
        {"name": "lib-b", "version": "0.1.0", "is_local": True, "files": [], "dependencies": [{"name": "lib-c", "specifier": "==0.1.0"}]},
        {"name": "lib-c", "version": "0.1.0", "is_local": True, "files": [], "dependencies": [
            {"name": "lib-a", "specifier": "==0.1.0"},
            {"name": "pytest", "specifier": "==8.0.0"},
        ]},
        {"name": "pytest", "version": "8.0.0", "files": [{"name": "pytest-8.0.0-py3-none-any.whl", "sha256": "a" * 64}], "dependencies": []},
        {"name": "click", "version": "8.1.0", "extras": ["color"], "files": [{"name": "click-8.1.0-py3-none-any.whl", "sha256": "c" * 64}], "dependencies": []},
        # Non-testonly local chain also reaching shared-lib (reached as testonly too) and directly-pinned testonly click.
        {"name": "app-local", "version": "0.1.0", "is_local": True, "files": [], "dependencies": [
            {"name": "click", "specifier": "==8.1.0"},
            {"name": "shared-local", "specifier": "==0.1.0"},
        ]},
        {"name": "shared-local", "version": "0.1.0", "is_local": True, "files": [], "dependencies": [
            {"name": "shared-tp", "specifier": "==1.0.0"},
        ]},
        {"name": "shared-tp", "version": "1.0.0", "files": [{"name": "shared_tp-1.0.0-py3-none-any.whl", "sha256": "d" * 64}], "dependencies": []},
        # Duplicate package entry with distinct markers and distinct extras on the same dep name.
        {
            "name": "appdep",
            "version": "1.0.0",
            "files": [{"name": "appdep-1.0.0-py3-none-any.whl", "sha256": "b" * 64}],
            "dependencies": [
                {"name": "pytest", "specifier": "==8.0.0", "marker": "sys_platform == 'linux'"},
                {"name": "click", "specifier": "==8.1.0", "extras": []},
            ],
        },
        {
            "name": "appdep",
            "version": "1.0.0",
            "files": [{"name": "appdep-1.0.0-py3-none-any.whl", "sha256": "b" * 64}],
            "dependencies": [
                {"name": "pytest", "specifier": "==8.0.0", "marker": "sys_platform == 'win32'"},
                {"name": "click", "specifier": "==8.1.0", "extras": ["color"]},
            ],
        },
    ]
    raw = resolve_lock_graph(
        packages = packages,
        pinned_package_specs = {
            "lib-a": {"": "==0.1.0"},
            "shared-local": {"": "==0.1.0"},
            "app-local": {"": "==0.1.0"},
            "click": {"": "==8.1.0"},
            "appdep": {"": "==1.0.0"},
        },
        requires_python = ">=3.10",
        strict_dependencies = True,
        testonly_pins = ["lib-a", "shared-local", "click"],
    )
    env.expect.that_str(raw["pins"]["pytest"]).equals("pytest@8.0.0")
    env.expect.that_str(raw["pins"]["shared-tp"]).equals("shared-tp@1.0.0")
    env.expect.that_bool("lib-a" in raw["pins"]).equals(False)
    env.expect.that_bool("lib-b" in raw["pins"]).equals(False)
    env.expect.that_bool("lib-c" in raw["pins"]).equals(False)

    # Only pytest stays testonly; click and shared-tp are also reached via non-testonly app-local.
    env.expect.that_collection(raw["testonly_pins"]).contains_exactly(["pytest"])

    # Both linux/win32 marker edges and base/extra edges survived distinct_packages merge.
    appdep_deps = raw["packages"]["appdep@1.0.0"]["dependencies"]
    markers = sorted([d["marker"] for d in appdep_deps if d["name"] == "pytest"])
    env.expect.that_collection(markers).contains_exactly([
        "sys_platform == 'linux'",
        "sys_platform == 'win32'",
    ]).in_order()
    click_names = sorted([d["name"] for d in appdep_deps if d["name"].startswith("click")])
    env.expect.that_collection(click_names).contains_exactly(["click", "click[color]"]).in_order()

def _test_local_chain_cycle_testonly_and_dep_merge(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_local_chain_cycle_testonly_and_dep_merge_impl)

def parse_dependency_groups_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_parse_basic_testonly,
            _test_parse_wildcard_then_specific_testonly,
            _test_parse_specific_testonly_then_wildcard,
            _test_parse_wildcard_testonly_with_override,
            _test_parse_wildcard_testonly_alone,
            _test_parse_no_testonly,
            _test_parse_transitive_testonly,
            _test_parse_double_wildcard,
            _test_kind_wildcard_testonly_after_star,
            _test_local_chain_cycle_testonly_and_dep_merge,
            _test_unprefixed_typo_fails,
            _test_unknown_kind_wildcard_fails,
            _test_missing_group_fails,
            _test_unknown_modifier_fails,
        ],
    )
