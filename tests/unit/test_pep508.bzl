"""Tests for pep508_evaluator, wheel_chooser, and cycle_dep_needed rules."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_dep_needed.bzl", "is_reachable")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_evaluator.bzl", "pycross_pep508_evaluator")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_marker_values.bzl", "Pep508EnvInfo", "marker_value_attrs", "with_extra")

# buildifier: disable=bzl-visibility
load("//pycross/private:target_platform.bzl", "PycrossTargetPlatformInfo", "pycross_target_platform")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "marker_evaluator_name", "marker_uses_extra")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_chooser.bzl", "pycross_wheel_chooser", "pycross_wheel_matched", "select_best_wheel")

_LINUX_MARKERS = {
    "os_name": "posix",
    "sys_platform": "linux",
    "platform_machine": "x86_64",
    "platform_system": "Linux",
    "platform_release": "",
    "platform_version": "",
    "python_version": "3.11",
    "python_full_version": "3.11.0",
    "implementation_name": "cpython",
    "implementation_version": "3.11.0",
    "platform_python_implementation": "CPython",
}

# ============================================================================
# Pure-function tests for select_best_wheel
# ============================================================================

_WHEEL_CANDIDATES = [
    "pkg-1.0-py3-none-any.whl",
    "pkg-1.0-cp311-cp311-manylinux_2_17_x86_64.whl",
    "pkg-1.0-cp311-cp311-manylinux_2_28_x86_64.whl",
    "pkg-1.0-cp311-cp311-macosx_11_0_arm64.whl",
    "pkg-1.0-cp311-cp311-win_amd64.whl",
]

# ── Test: linux x86_64 picks manylinux_2_28 (highest priority) ───────

def _test_wheel_linux_x86_impl(env, _target):
    supported_tags = [
        "cp311-cp311-manylinux_2_28_x86_64",
        "cp311-cp311-manylinux_2_17_x86_64",
        "py3-none-any",
    ]
    best = select_best_wheel(_WHEEL_CANDIDATES, supported_tags)
    if best == None:
        env.fail("Expected a wheel match for linux x86_64")
    elif best != "pkg-1.0-cp311-cp311-manylinux_2_28_x86_64.whl":
        env.fail("Expected manylinux_2_28, got " + best)

def _test_wheel_linux_x86(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_linux_x86_impl,
    )

# ── Test: mac arm64 picks macosx wheel ───────────────────────────────

def _test_wheel_mac_arm64_impl(env, _target):
    supported_tags = [
        "cp311-cp311-macosx_11_0_arm64",
        "py3-none-any",
    ]
    best = select_best_wheel(_WHEEL_CANDIDATES, supported_tags)
    if best == None:
        env.fail("Expected a wheel match for darwin arm64")
    elif best != "pkg-1.0-cp311-cp311-macosx_11_0_arm64.whl":
        env.fail("Expected macosx_11_0_arm64, got " + best)

def _test_wheel_mac_arm64(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_mac_arm64_impl,
    )

# ── Test: falls back to py3-none-any on unknown platform ─────────────

def _test_wheel_fallback_any_impl(env, _target):
    supported_tags = [
        "py3-none-any",
    ]
    best = select_best_wheel(_WHEEL_CANDIDATES, supported_tags)
    if best == None:
        env.fail("Expected py3-none-any fallback")
    elif best != "pkg-1.0-py3-none-any.whl":
        env.fail("Expected py3-none-any fallback, got " + best)

def _test_wheel_fallback_any(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_fallback_any_impl,
    )

# ── Test: no match returns None ──────────────────────────────────────

def _test_wheel_no_match_impl(env, _target):
    candidates = [
        "pkg-1.0-cp312-cp312-manylinux_2_28_x86_64.whl",
    ]
    supported_tags = [
        "cp311-cp311-manylinux_2_17_x86_64",
    ]
    best = select_best_wheel(candidates, supported_tags)
    if best != None:
        env.fail("Expected no match for wrong python version, got " + best)

def _test_wheel_no_match(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_no_match_impl,
    )

# ── Test: abi3 wheel matches ────────────────────────────────────────

def _test_wheel_abi3_impl(env, _target):
    candidates = [
        "pkg-1.0-cp311-abi3-manylinux_2_17_x86_64.whl",
        "pkg-1.0-py3-none-any.whl",
    ]
    supported_tags = [
        "cp311-abi3-manylinux_2_17_x86_64",
        "py3-none-any",
    ]
    best = select_best_wheel(candidates, supported_tags)
    if best == None:
        env.fail("Expected abi3 wheel match")
    elif best != "pkg-1.0-cp311-abi3-manylinux_2_17_x86_64.whl":
        env.fail("Expected abi3 wheel, got " + best)

def _test_wheel_abi3(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_abi3_impl,
    )

# ============================================================================
# Analysis test: evaluator rule returns FeatureFlagInfo
# ============================================================================

def _test_evaluator_rule_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])
    env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals("true")

def _test_evaluator_rule(name):
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = (
            "sys_platform == 'linux' and os.name == 'posix' and " +
            "sys.platform == 'linux' and platform.machine == 'x86_64' and " +
            "python_implementation == 'CPython' and platform.python_implementation == 'CPython'"
        ),
        os_name = "posix",
        sys_platform = "linux",
        platform_machine = "x86_64",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_evaluator",
        impl = _test_evaluator_rule_impl,
    )

# ============================================================================
# Analysis test: wheel chooser rule returns FeatureFlagInfo
# ============================================================================

def _test_chooser_rule_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([])
    env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals("pkg-1.0-py3-none-any.whl")

def _test_chooser_rule(name):
    pycross_target_platform(
        name = name + "_tags",
        libc = "glibc",
        tags = ["manual"],
    )

    pycross_wheel_chooser(
        name = name + "_chooser",
        candidates = ["pkg-1.0-py3-none-any.whl"],
        supported_tags = ":" + name + "_tags",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_chooser",
        impl = _test_chooser_rule_impl,
    )

def _test_wheel_priority_map_impl(env, target):
    info = target[PycrossTargetPlatformInfo]
    env.expect.that_bool(type(info.tag_priority) == "dict").equals(True)
    env.expect.that_bool("py3-none-any" in info.tag_priority).equals(True)

    # First-candidate-wins tie breaking when two candidates share the same best tag.
    tied = [
        "pkg-1.0-1-py3-none-any.whl",
        "pkg-1.0-2-py3-none-any.whl",
    ]
    env.expect.that_str(select_best_wheel(tied, info.tag_priority)).equals(tied[0])

    # Precomputed dict selects the higher-priority platform wheel over py3-none-any.
    ranks = {
        "cp311-cp311-manylinux_2_28_x86_64": 0,
        "py3-none-any": 500,
    }
    env.expect.that_str(select_best_wheel(_WHEEL_CANDIDATES, ranks)).equals(
        "pkg-1.0-cp311-cp311-manylinux_2_28_x86_64.whl",
    )

def _test_wheel_priority_map(name):
    pycross_target_platform(
        name = name + "_tags",
        libc = "glibc",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_tags",
        impl = _test_wheel_priority_map_impl,
    )

def _test_wheel_matched_true_impl(env, target):
    env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals("true")

def _test_wheel_matched_true(name):
    pycross_target_platform(
        name = name + "_tags",
        libc = "glibc",
        tags = ["manual"],
    )
    pycross_wheel_chooser(
        name = name + "_chooser",
        candidates = ["pkg-1.0-py3-none-any.whl"],
        supported_tags = ":" + name + "_tags",
        tags = ["manual"],
    )
    pycross_wheel_matched(
        name = name + "_matched",
        chooser = ":" + name + "_chooser",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_matched",
        impl = _test_wheel_matched_true_impl,
    )

def _test_wheel_matched_false_impl(env, target):
    env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals("false")

def _test_wheel_matched_false(name):
    pycross_target_platform(
        name = name + "_tags",
        platforms = ["manylinux_2_17_x86_64"],
        tags = ["manual"],
    )
    pycross_wheel_chooser(
        name = name + "_chooser",
        candidates = ["pkg-1.0-cp311-cp311-win_amd64.whl"],
        supported_tags = ":" + name + "_tags",
        tags = ["manual"],
    )
    pycross_wheel_matched(
        name = name + "_matched",
        chooser = ":" + name + "_chooser",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_matched",
        impl = _test_wheel_matched_false_impl,
    )

# ============================================================================
# Cycle dep reachability tests
# ============================================================================

_CYCLE_EDGES = {
    "alpha@1.0": [
        {"dep": "beta@2.0"},
        {"dep": "gamma@1.0", "marker": "sys_platform == 'darwin'"},
    ],
    "beta@2.0": [
        {"dep": "alpha@1.0"},
    ],
    "gamma@1.0": [
        {"dep": "alpha@1.0"},
    ],
}

# buildifier: disable=unused-variable
def _test_cycle_reachable_impl(env, target):
    """beta@2.0 is unconditionally reachable from alpha@1.0 (including dotted/alias marker vars)."""
    result = is_reachable(_CYCLE_EDGES, "alpha@1.0", "beta@2.0", _LINUX_MARKERS)
    env.expect.that_bool(result).equals(True)
    dotted_edges = {
        "alpha@1.0": [
            {
                "dep": "beta@2.0",
                "marker": "os.name == 'posix' and platform.machine == 'x86_64' and python_implementation == 'CPython'",
            },
        ],
        "beta@2.0": [{"dep": "alpha@1.0"}],
    }
    env.expect.that_bool(is_reachable(dotted_edges, "alpha@1.0", "beta@2.0", _LINUX_MARKERS)).equals(True)

def _test_cycle_reachable(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_reachable_impl)

# buildifier: disable=unused-variable
def _test_cycle_marker_gated_impl(env, target):
    """gamma@1.0 is only reachable on darwin, not on linux."""

    # On linux, gamma is NOT reachable (marker says darwin)
    env.expect.that_bool(is_reachable(_CYCLE_EDGES, "alpha@1.0", "gamma@1.0", _LINUX_MARKERS)).equals(False)

    # On darwin, gamma IS reachable
    mac_markers = dict(_LINUX_MARKERS)
    mac_markers["sys_platform"] = "darwin"
    mac_markers["os_name"] = "posix"
    mac_markers["platform_system"] = "Darwin"
    env.expect.that_bool(is_reachable(_CYCLE_EDGES, "alpha@1.0", "gamma@1.0", mac_markers)).equals(True)

def _test_cycle_marker_gated(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_marker_gated_impl)

# buildifier: disable=unused-variable
def _test_cycle_self_reachable_impl(env, target):
    """A node is always reachable from itself."""
    env.expect.that_bool(is_reachable(_CYCLE_EDGES, "alpha@1.0", "alpha@1.0", _LINUX_MARKERS)).equals(True)

def _test_cycle_self_reachable(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_self_reachable_impl)

# ── Test: compound (multi) tags match individual supported tags ───────

def _test_wheel_compound_tags_impl(env, _target):
    candidates = [
        "numpy-1.26.4-cp310.cp311-cp310.cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    ]

    # cp311 is in the compound python and abi tags; manylinux_2_17_x86_64 is in the compound platform tag
    best1 = select_best_wheel(candidates, ["cp311-cp311-manylinux_2_17_x86_64"])
    if best1 == None:
        env.fail("Expected compound tag match for cp311-cp311-manylinux_2_17_x86_64")
    elif best1 != candidates[0]:
        env.fail("Expected numpy compound wheel, got " + best1)

    # cp310 is in the compound python and abi tags; manylinux2014_x86_64 is in the compound platform tag
    best2 = select_best_wheel(candidates, ["cp310-cp310-manylinux2014_x86_64"])
    if best2 == None:
        env.fail("Expected compound tag match for cp310-cp310-manylinux2014_x86_64")
    elif best2 != candidates[0]:
        env.fail("Expected numpy compound wheel, got " + best2)

def _test_wheel_compound_tags(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_wheel_compound_tags_impl,
    )

# ── Test: multi-hop marker-gated cycle reachability ──────────────────

_WIN_MARKERS = {
    "os_name": "nt",
    "sys_platform": "win32",
    "platform_machine": "x86_64",
    "platform_system": "Windows",
    "platform_release": "",
    "platform_version": "",
    "python_version": "3.11",
    "python_full_version": "3.11.0",
    "implementation_name": "cpython",
    "implementation_version": "3.11.0",
    "platform_python_implementation": "CPython",
}

_MULTI_HOP_EDGES = {
    "a@1.0": [
        {"dep": "b@1.0", "marker": "sys_platform == 'linux'"},
    ],
    "b@1.0": [
        {"dep": "c@1.0", "marker": "sys_platform == 'linux'"},
    ],
    "c@1.0": [
        {"dep": "a@1.0"},
    ],
}

# buildifier: disable=unused-variable
def _test_cycle_multi_hop_marker_impl(env, target):
    """c@1.0 is reachable from a@1.0 on linux (both gates pass), but not on windows."""

    # On linux, both marker gates pass so c is reachable
    env.expect.that_bool(is_reachable(_MULTI_HOP_EDGES, "a@1.0", "c@1.0", _LINUX_MARKERS)).equals(True)

    # On windows, the first gate blocks so c is NOT reachable
    env.expect.that_bool(is_reachable(_MULTI_HOP_EDGES, "a@1.0", "c@1.0", _WIN_MARKERS)).equals(False)

def _test_cycle_multi_hop_marker(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_multi_hop_marker_impl)

# ── Test: target_platform Windows ARM64/x86_32 and marker edge cases ─

def _test_target_platform_win_arm64_impl(env, target):
    info = target[PycrossTargetPlatformInfo]
    env.expect.that_collection(info.platforms).contains_exactly(["win_arm64"])
    env.expect.that_str(info.markers["python_version"]).equals("3.12")
    env.expect.that_str(info.markers["python_full_version"]).equals("3.12.0")
    env.expect.that_str(info.markers["implementation_version"]).equals("3.12.0")

def _test_target_platform_win_arm64(name):
    pycross_target_platform(
        name = name + "_plat",
        os_name = "nt",
        sys_platform = "win32",
        platform_machine = "ARM64",
        python_version = "3.12",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_plat",
        impl = _test_target_platform_win_arm64_impl,
    )

def _test_target_platform_win_x86_32_impl(env, target):
    info = target[PycrossTargetPlatformInfo]
    env.expect.that_collection(info.platforms).contains_exactly(["win32"])
    env.expect.that_str(info.markers["python_version"]).equals("3.11")
    env.expect.that_str(info.markers["python_full_version"]).equals("3.11.5")

def _test_target_platform_win_x86_32(name):
    pycross_target_platform(
        name = name + "_plat",
        os_name = "nt",
        sys_platform = "win32",
        platform_machine = "x86_32",
        python_full_version = "3.11.5",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_plat",
        impl = _test_target_platform_win_x86_32_impl,
    )

def _test_target_platform_linux_x86_32_and_pypy_impl(env, target):
    info = target[PycrossTargetPlatformInfo]
    env.expect.that_collection(info.platforms).contains_exactly(["manylinux_2_28_i686"])
    env.expect.that_str(info.implementation).equals("pp")
    env.expect.that_str(info.markers["implementation_name"]).equals("pypy")
    env.expect.that_str(info.markers["platform_python_implementation"]).equals("PyPy")

def _test_target_platform_linux_x86_32_and_pypy(name):
    pycross_target_platform(
        name = name + "_plat",
        os_name = "posix",
        sys_platform = "linux",
        platform_machine = "x86_32",
        libc = "glibc",
        python_version = "3.11",
        implementation_name = "pypy",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_plat",
        impl = _test_target_platform_linux_x86_32_and_pypy_impl,
    )

def _test_marker_uses_extra_impl(env, _target):
    env.expect.that_bool(marker_uses_extra("extra == 'test'")).equals(True)
    env.expect.that_bool(marker_uses_extra("sys_platform == 'linux' and extra == 'dev'")).equals(True)
    env.expect.that_bool(marker_uses_extra("sys_platform == 'linux'")).equals(False)
    env.expect.that_bool(marker_uses_extra("'foo' in extras")).equals(False)
    env.expect.that_bool(marker_uses_extra("platform_version == 'extra'")).equals(False)
    env.expect.that_str(marker_evaluator_name("'foo' in extras", "dev")).equals(
        marker_evaluator_name("'foo' in extras", ""),
    )
    env.expect.that_str(marker_evaluator_name("extra == 'dev'", "dev")).not_equals(
        marker_evaluator_name("extra == 'dev'", ""),
    )

    # Memoization cache stores parsed results only for markers containing "extra".
    cache = {}
    env.expect.that_bool(marker_uses_extra("extra == 'dev'", cache = cache)).equals(True)
    env.expect.that_bool(marker_uses_extra("'foo' in extras", cache = cache)).equals(False)
    env.expect.that_bool(marker_uses_extra("platform_version == 'extra'", cache = cache)).equals(False)
    env.expect.that_bool(marker_uses_extra("sys_platform == 'linux'", cache = cache)).equals(False)
    env.expect.that_bool(marker_uses_extra("", cache = cache)).equals(False)
    env.expect.that_dict(cache).contains_exactly({
        "extra == 'dev'": True,
        "'foo' in extras": False,
        "platform_version == 'extra'": False,
    })

    # Pre-populated cache entries return directly without calling pypackaging.markers.parse.
    sentinel_true = "invalid syntax extra ==="
    sentinel_false = "also invalid extra ==="
    cache[sentinel_true] = True
    cache[sentinel_false] = False
    env.expect.that_bool(marker_uses_extra(sentinel_true, cache = cache)).equals(True)
    env.expect.that_bool(marker_uses_extra(sentinel_false, cache = cache)).equals(False)

    # marker_evaluator_name populates and reuses extra_cache with identical output.
    eval_cache = {}
    env.expect.that_str(marker_evaluator_name("extra == 'dev'", "dev", extra_cache = eval_cache)).equals(
        marker_evaluator_name("extra == 'dev'", "dev"),
    )
    env.expect.that_str(marker_evaluator_name("'foo' in extras", "dev", extra_cache = eval_cache)).equals(
        marker_evaluator_name("'foo' in extras", "dev"),
    )
    env.expect.that_str(marker_evaluator_name("sys_platform == 'linux'", "dev", extra_cache = eval_cache)).equals(
        marker_evaluator_name("sys_platform == 'linux'", "dev"),
    )
    env.expect.that_dict(eval_cache).contains_exactly({
        "extra == 'dev'": True,
        "'foo' in extras": False,
    })
    eval_cache[sentinel_true] = True
    eval_cache[sentinel_false] = False
    env.expect.that_str(marker_evaluator_name(sentinel_true, "dev", extra_cache = eval_cache)).not_equals(
        marker_evaluator_name(sentinel_true, "", extra_cache = eval_cache),
    )
    env.expect.that_str(marker_evaluator_name(sentinel_false, "dev", extra_cache = eval_cache)).equals(
        marker_evaluator_name(sentinel_false, "", extra_cache = eval_cache),
    )

def _test_marker_uses_extra(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_marker_uses_extra_impl,
    )

# ── Test: single //pycross/private/markers:env dep & override precedence ─

_LEGACY_MARKER_TARGET_ATTRS = [
    "_os_name_target",
    "_sys_platform_target",
    "_platform_machine_target",
    "_platform_system_target",
    "_platform_release_target",
    "_platform_version_target",
    "_python_version_target",
    "_python_full_version_target",
    "_implementation_name_target",
    "_implementation_version_target",
    "_platform_python_implementation_target",
]

_MARKER_VALUE_PRIVATE_ATTRS = [k for k in marker_value_attrs().keys() if k.startswith("_")]

_MarkerDepsInfo = provider(
    doc = "Observed marker env dependencies on a rule under test.",
    fields = ["attr_names", "private_target_attrs", "pep508_env_label", "has_pep508_env_provider"],
)

def _inspect_marker_deps_aspect_impl(_target, ctx):
    attr_names = dir(ctx.rule.attr)
    private_target_attrs = [
        a
        for a in attr_names
        if a.startswith("_") and type(getattr(ctx.rule.attr, a)) == "Target"
    ]
    env_target = getattr(ctx.rule.attr, "_pep508_env", None)
    return [
        _MarkerDepsInfo(
            attr_names = attr_names,
            private_target_attrs = private_target_attrs,
            pep508_env_label = env_target.label if env_target else None,
            has_pep508_env_provider = bool(env_target and Pep508EnvInfo in env_target),
        ),
    ]

_inspect_marker_deps_aspect = aspect(implementation = _inspect_marker_deps_aspect_impl)

def _test_evaluator_single_env_dep_impl(env, target):
    info = target[_MarkerDepsInfo]
    env.expect.that_bool(info.has_pep508_env_provider).equals(True)
    env.expect.that_str(str(info.pep508_env_label)).equals(str(Label("//pycross/private/markers:env")))
    env.expect.that_collection(info.private_target_attrs).contains_exactly(["_pep508_env"])
    for legacy_attr in _LEGACY_MARKER_TARGET_ATTRS:
        env.expect.that_collection(info.attr_names).not_contains(legacy_attr)
    env.expect.that_collection(_MARKER_VALUE_PRIVATE_ATTRS).contains_exactly(["_pep508_env"])
    env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals("true")

def _test_evaluator_single_env_dep(name):
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = "platform_release == '6.1.0' and platform_version == '#42 SMP'",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_evaluator",
        extra_target_under_test_aspects = [_inspect_marker_deps_aspect],
        config_settings = {
            str(Label("//pycross/settings:pep508_platform_release")): "6.1.0",
            str(Label("//pycross/settings:pep508_platform_version")): "#42 SMP",
        },
        impl = _test_evaluator_single_env_dep_impl,
    )

def _test_evaluator_override_precedence_impl(env, target):
    env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals("true")

def _test_evaluator_override_python_version_derivation(name):
    # Explicit python_version must derive python_full_version and implementation_version
    # instead of picking up the host toolchain's full version.
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = (
            "python_version == '3.12' and " +
            "python_full_version == '3.12.0' and " +
            "implementation_version == '3.12.0'"
        ),
        python_version = "3.12",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_evaluator",
        impl = _test_evaluator_override_precedence_impl,
    )

def _test_evaluator_override_three_part_python_version(name):
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = (
            "python_version == '3.12' and " +
            "python_full_version == '3.12.7' and " +
            "implementation_version == '3.12.7'"
        ),
        python_version = "3.12.7",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_evaluator",
        impl = _test_evaluator_override_precedence_impl,
    )

def _test_evaluator_override_pypy_derivation(name):
    # Explicit implementation_name='pypy' derives platform_python_implementation='PyPy'
    # instead of picking up the default 'CPython' flag value.
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = "implementation_name == 'pypy' and platform_python_implementation == 'PyPy'",
        implementation_name = "pypy",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_evaluator",
        impl = _test_evaluator_override_precedence_impl,
    )

def _test_evaluator_override_pypy_respects_custom_ppi_flag(name):
    # A non-default //pycross/settings:pep508_platform_python_implementation flag
    # still wins when platform_python_implementation attr is unset.
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = "implementation_name == 'pypy' and platform_python_implementation == 'CustomPy'",
        implementation_name = "pypy",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_evaluator",
        config_settings = {
            str(Label("//pycross/settings:pep508_platform_python_implementation")): "CustomPy",
        },
        impl = _test_evaluator_override_precedence_impl,
    )

def _test_with_extra_impl(env, _target):
    base = {"sys_platform": "linux", "extra": ""}
    env.expect.that_dict(with_extra(base, "")).contains_exactly(base)
    updated = with_extra(base, "dev")
    env.expect.that_str(updated["extra"]).equals("dev")
    env.expect.that_str(base["extra"]).equals("")

    no_extra_key = {"sys_platform": "linux"}
    env.expect.that_dict(with_extra(no_extra_key, "")).contains_exactly(no_extra_key)
    env.expect.that_str(with_extra(no_extra_key, "test")["extra"]).equals("test")

    with_variants = {"sys_platform": "linux", "extra": ["", "__variant_cuda"]}
    replaced = with_extra(with_variants, "dev")
    env.expect.that_collection(replaced["extra"]).contains_exactly(["dev", "__variant_cuda"]).in_order()
    env.expect.that_collection(with_extra(replaced, "dev")["extra"]).contains_exactly(["dev", "__variant_cuda"]).in_order()
    env.expect.that_collection(with_variants["extra"]).contains_exactly(["", "__variant_cuda"]).in_order()

def _test_with_extra(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_with_extra_impl,
    )

# ============================================================================
# Test suite
# ============================================================================

def pep508_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_wheel_linux_x86,
            _test_wheel_mac_arm64,
            _test_wheel_fallback_any,
            _test_wheel_no_match,
            _test_wheel_abi3,
            _test_wheel_compound_tags,
            _test_evaluator_rule,
            _test_chooser_rule,
            _test_wheel_priority_map,
            _test_wheel_matched_true,
            _test_wheel_matched_false,
            _test_target_platform_win_arm64,
            _test_target_platform_win_x86_32,
            _test_target_platform_linux_x86_32_and_pypy,
            _test_marker_uses_extra,
            _test_evaluator_single_env_dep,
            _test_evaluator_override_python_version_derivation,
            _test_evaluator_override_three_part_python_version,
            _test_evaluator_override_pypy_derivation,
            _test_evaluator_override_pypy_respects_custom_ppi_flag,
            _test_with_extra,
            _test_cycle_reachable,
            _test_cycle_marker_gated,
            _test_cycle_self_reachable,
            _test_cycle_multi_hop_marker,
        ],
    )
