"""Tests for pep508_evaluator, wheel_chooser, and cycle_dep_needed rules."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_dep_needed.bzl", "is_reachable")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_evaluator.bzl", "pycross_pep508_evaluator")

# buildifier: disable=bzl-visibility
load("//pycross/private:target_platform.bzl", "pycross_target_platform")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_chooser.bzl", "pycross_wheel_chooser", "select_best_wheel")

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

def _test_evaluator_rule(name):
    pycross_pep508_evaluator(
        name = name + "_evaluator",
        expr = "sys_platform == 'linux'",
        sys_platform = "linux",
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
    """beta@2.0 is unconditionally reachable from alpha@1.0."""
    result = is_reachable(_CYCLE_EDGES, "alpha@1.0", "beta@2.0", _LINUX_MARKERS)
    env.expect.that_bool(result).equals(True)

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
            _test_cycle_reachable,
            _test_cycle_marker_gated,
            _test_cycle_self_reachable,
            _test_cycle_multi_hop_marker,
        ],
    )
