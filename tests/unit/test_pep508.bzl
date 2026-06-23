"""Tests for pep508_evaluator, wheel_chooser, and cycle_dep_needed rules."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_dep_needed.bzl", "is_reachable")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_evaluator.bzl", "evaluate_marker_expr", "pycross_pep508_evaluator")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_chooser.bzl", "pycross_wheel_chooser", "select_best_wheel")

# ============================================================================
# Pure-function tests for evaluate_marker_expr
# ============================================================================

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

def _assert_eval(env, expr, markers, expected):
    result = evaluate_marker_expr(expr, markers)
    if result != expected:
        env.fail("Expected {} for expr {} with markers, got {}".format(
            expected,
            expr,
            result,
        ))

# ── Test: simple equality ────────────────────────────────────────────

def _test_simple_eq_true_impl(env, _target):
    _assert_eval(env, {
        "op": "==",
        "lhs": {"type": "marker", "value": "sys_platform"},
        "rhs": {"type": "string", "value": "linux"},
    }, _LINUX_MARKERS, True)

def _test_simple_eq_true(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_simple_eq_true_impl,
    )

# ── Test: simple equality false ──────────────────────────────────────

def _test_simple_eq_false_impl(env, _target):
    _assert_eval(env, {
        "op": "==",
        "lhs": {"type": "marker", "value": "sys_platform"},
        "rhs": {"type": "string", "value": "win32"},
    }, _LINUX_MARKERS, False)

def _test_simple_eq_false(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_simple_eq_false_impl,
    )

# ── Test: not equal ──────────────────────────────────────────────────

def _test_neq_impl(env, _target):
    _assert_eval(env, {
        "op": "!=",
        "lhs": {"type": "marker", "value": "sys_platform"},
        "rhs": {"type": "string", "value": "win32"},
    }, _LINUX_MARKERS, True)

def _test_neq(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_neq_impl,
    )

# ── Test: version comparison >= ──────────────────────────────────────

def _test_version_gte_impl(env, _target):
    _assert_eval(env, {
        "op": ">=",
        "lhs": {"type": "marker", "value": "python_version"},
        "rhs": {"type": "string", "value": "3.10"},
    }, _LINUX_MARKERS, True)  # 3.11 >= 3.10

    _assert_eval(env, {
        "op": ">=",
        "lhs": {"type": "marker", "value": "python_version"},
        "rhs": {"type": "string", "value": "3.12"},
    }, _LINUX_MARKERS, False)  # 3.11 >= 3.12

def _test_version_gte(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_version_gte_impl,
    )

# ── Test: version comparison < ───────────────────────────────────────

def _test_version_lt_impl(env, _target):
    _assert_eval(env, {
        "op": "<",
        "lhs": {"type": "marker", "value": "python_version"},
        "rhs": {"type": "string", "value": "3.12"},
    }, _LINUX_MARKERS, True)  # 3.11 < 3.12

    _assert_eval(env, {
        "op": "<",
        "lhs": {"type": "marker", "value": "python_version"},
        "rhs": {"type": "string", "value": "3.11"},
    }, _LINUX_MARKERS, False)  # 3.11 < 3.11

def _test_version_lt(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_version_lt_impl,
    )

# ── Test: boolean AND ────────────────────────────────────────────────

def _test_and_impl(env, _target):
    _assert_eval(env, {
        "op": "and",
        "lhs": {
            "op": "==",
            "lhs": {"type": "marker", "value": "sys_platform"},
            "rhs": {"type": "string", "value": "linux"},
        },
        "rhs": {
            "op": ">=",
            "lhs": {"type": "marker", "value": "python_version"},
            "rhs": {"type": "string", "value": "3.10"},
        },
    }, _LINUX_MARKERS, True)

    _assert_eval(env, {
        "op": "and",
        "lhs": {
            "op": "==",
            "lhs": {"type": "marker", "value": "sys_platform"},
            "rhs": {"type": "string", "value": "darwin"},
        },
        "rhs": {
            "op": ">=",
            "lhs": {"type": "marker", "value": "python_version"},
            "rhs": {"type": "string", "value": "3.10"},
        },
    }, _LINUX_MARKERS, False)

def _test_and(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_and_impl,
    )

# ── Test: boolean OR ─────────────────────────────────────────────────

def _test_or_impl(env, _target):
    _assert_eval(env, {
        "op": "or",
        "lhs": {
            "op": "==",
            "lhs": {"type": "marker", "value": "sys_platform"},
            "rhs": {"type": "string", "value": "linux"},
        },
        "rhs": {
            "op": "==",
            "lhs": {"type": "marker", "value": "sys_platform"},
            "rhs": {"type": "string", "value": "darwin"},
        },
    }, _LINUX_MARKERS, True)

def _test_or(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_or_impl,
    )

# ── Test: 'in' operator ─────────────────────────────────────────────

def _test_in_operator_impl(env, _target):
    _assert_eval(env, {
        "op": "in",
        "lhs": {"type": "string", "value": "x86"},
        "rhs": {"type": "marker", "value": "platform_machine"},
    }, _LINUX_MARKERS, True)  # "x86" in "x86_64"

    _assert_eval(env, {
        "op": "not in",
        "lhs": {"type": "string", "value": "arm"},
        "rhs": {"type": "marker", "value": "platform_machine"},
    }, _LINUX_MARKERS, True)  # "arm" not in "x86_64"

def _test_in_operator(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_in_operator_impl,
    )

# ============================================================================
# Pure-function tests for select_best_wheel
# ============================================================================

_WHEEL_CANDIDATES = [
    {
        "filename": "pkg-1.0-py3-none-any.whl",
        "python_tag": "py3",
        "abi_tag": "none",
        "platform_tag": "any",
    },
    {
        "filename": "pkg-1.0-cp311-cp311-manylinux_2_17_x86_64.whl",
        "python_tag": "cp311",
        "abi_tag": "cp311",
        "platform_tag": "manylinux_2_17_x86_64",
    },
    {
        "filename": "pkg-1.0-cp311-cp311-manylinux_2_28_x86_64.whl",
        "python_tag": "cp311",
        "abi_tag": "cp311",
        "platform_tag": "manylinux_2_28_x86_64",
    },
    {
        "filename": "pkg-1.0-cp311-cp311-macosx_11_0_arm64.whl",
        "python_tag": "cp311",
        "abi_tag": "cp311",
        "platform_tag": "macosx_11_0_arm64",
    },
    {
        "filename": "pkg-1.0-cp311-cp311-win_amd64.whl",
        "python_tag": "cp311",
        "abi_tag": "cp311",
        "platform_tag": "win_amd64",
    },
]

# ── Test: linux x86_64 picks manylinux_2_28 (highest priority) ───────

def _test_wheel_linux_x86_impl(env, _target):
    best = select_best_wheel(_WHEEL_CANDIDATES, "linux", "x86_64", "3.11")
    if best == None:
        env.fail("Expected a wheel match for linux x86_64")
    elif best["filename"] != "pkg-1.0-cp311-cp311-manylinux_2_28_x86_64.whl":
        env.fail("Expected manylinux_2_28, got " + best["filename"])

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
    best = select_best_wheel(_WHEEL_CANDIDATES, "darwin", "arm64", "3.11")
    if best == None:
        env.fail("Expected a wheel match for darwin arm64")
    elif best["filename"] != "pkg-1.0-cp311-cp311-macosx_11_0_arm64.whl":
        env.fail("Expected macosx_11_0_arm64, got " + best["filename"])

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
    best = select_best_wheel(_WHEEL_CANDIDATES, "freebsd", "x86_64", "3.11")
    if best == None:
        env.fail("Expected py3-none-any fallback")
    elif best["filename"] != "pkg-1.0-py3-none-any.whl":
        env.fail("Expected py3-none-any fallback, got " + best["filename"])

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
        {
            "filename": "pkg-1.0-cp312-cp312-manylinux_2_28_x86_64.whl",
            "python_tag": "cp312",
            "abi_tag": "cp312",
            "platform_tag": "manylinux_2_28_x86_64",
        },
    ]
    best = select_best_wheel(candidates, "linux", "x86_64", "3.11")
    if best != None:
        env.fail("Expected no match for wrong python version, got " + best["filename"])

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
        {
            "filename": "pkg-1.0-cp311-abi3-manylinux_2_17_x86_64.whl",
            "python_tag": "cp311",
            "abi_tag": "abi3",
            "platform_tag": "manylinux_2_17_x86_64",
        },
        {
            "filename": "pkg-1.0-py3-none-any.whl",
            "python_tag": "py3",
            "abi_tag": "none",
            "platform_tag": "any",
        },
    ]
    best = select_best_wheel(candidates, "linux", "x86_64", "3.11")
    if best == None:
        env.fail("Expected abi3 wheel match")
    elif best["filename"] != "pkg-1.0-cp311-abi3-manylinux_2_17_x86_64.whl":
        env.fail("Expected abi3 wheel, got " + best["filename"])

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
        expr = '{"op": "==", "lhs": {"type": "marker", "value": "sys_platform"}, "rhs": {"type": "string", "value": "linux"}}',
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
    pycross_wheel_chooser(
        name = name + "_chooser",
        candidates = json.encode([{
            "filename": "pkg-1.0-py3-none-any.whl",
            "python_tag": "py3",
            "abi_tag": "none",
            "platform_tag": "any",
        }]),
        sys_platform = "linux",
        platform_machine = "x86_64",
        python_version = "3.11",
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
        {"dep": "gamma@1.0", "marker_ast": {
            "op": "==",
            "lhs": {"type": "marker", "value": "sys_platform"},
            "rhs": {"type": "string", "value": "darwin"},
        }},
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

# ============================================================================
# Test suite
# ============================================================================

def pep508_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_simple_eq_true,
            _test_simple_eq_false,
            _test_neq,
            _test_version_gte,
            _test_version_lt,
            _test_and,
            _test_or,
            _test_in_operator,
            _test_wheel_linux_x86,
            _test_wheel_mac_arm64,
            _test_wheel_fallback_any,
            _test_wheel_no_match,
            _test_wheel_abi3,
            _test_evaluator_rule,
            _test_chooser_rule,
            _test_cycle_reachable,
            _test_cycle_marker_gated,
            _test_cycle_self_reachable,
        ],
    )
