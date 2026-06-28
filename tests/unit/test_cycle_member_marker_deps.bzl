"""Tests for cycle reachability group computation."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_member_marker_deps.bzl", "compute_reachability_groups", "find_unconditional_deps")

# ── Test: Linear Chain Collapsing ─────────────────────────────────────

def _test_linear_chain_collapsing_impl(env, _target):
    """Verifies that linear unconditional chains are collapsed.
    A -> B -> C -> D -> A
    From A: B is non-collapsible (direct dep).
    C has one inbound edge (from B, unconditional) -> collapsed into B.
    D has one inbound edge (from C, unconditional) -> collapsed into B.
    """
    edges = {
        "A": [{"dep": "B"}],
        "B": [{"dep": "C"}],
        "C": [{"dep": "D"}],
        "D": [{"dep": "A"}],
    }
    other_members = ["B", "C", "D"]
    
    groups = compute_reachability_groups("A", other_members, edges)
    
    # Expected: B is the representative for B, C, D.
    # Groups are sorted by representative.
    # Each entry is (representative, group_members).
    env.expect.that_int(len(groups)).equals(1)
    rep, members = groups[0]
    env.expect.that_str(rep).equals("B")
    env.expect.that_collection(members).contains_exactly(["B", "C", "D"])

def _test_linear_chain_collapsing(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_linear_chain_collapsing_impl)

# ── Test: Multipath Guard ─────────────────────────────────────────────

def _test_multipath_guard_impl(env, _target):
    """Verifies that nodes with multiple inbound edges are NOT collapsed.
    A -> B -> C -> A
    A -> C
    From A: B is direct dep.
    C has two inbound edges (from B, and directly from A).
    Should NOT be collapsed because len(inbound) == 2.
    """
    edges = {
        "A": [{"dep": "B"}, {"dep": "C"}],
        "B": [{"dep": "C"}],
        "C": [{"dep": "A"}],
    }
    other_members = ["B", "C"]
    
    groups = compute_reachability_groups("A", other_members, edges)
    
    # Expected: B and C are their own representatives.
    env.expect.that_int(len(groups)).equals(2)
    
    rep0, members0 = groups[0]
    env.expect.that_str(rep0).equals("B")
    env.expect.that_collection(members0).contains_exactly(["B"])
    
    rep1, members1 = groups[1]
    env.expect.that_str(rep1).equals("C")
    env.expect.that_collection(members1).contains_exactly(["C"])

def _test_multipath_guard(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_multipath_guard_impl)

# ── Test: Direct Dependency Guard (Conservative) ──────────────────────

def _test_direct_dep_guard_impl(env, _target):
    """Verifies that direct dependencies are NOT collapsed into the member itself.
    A -> B -> A
    From A: B is a direct dep.
    Currently, logic says `pred != member`, so B is NOT collapsed into A's group.
    (This is what we want to change, but this tests current conservative behavior).
    """
    edges = {
        "A": [{"dep": "B"}],
        "B": [{"dep": "A"}],
    }
    other_members = ["B"]
    
    groups = compute_reachability_groups("A", other_members, edges)
    
    # Expected: B is its own representative.
    env.expect.that_int(len(groups)).equals(1)
    rep, members = groups[0]
    env.expect.that_str(rep).equals("B")
    env.expect.that_collection(members).contains_exactly(["B"])

def _test_direct_dep_guard(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_direct_dep_guard_impl)

# ── Test: Find Unconditional Deps (Purely Unconditional) ─────────────

def _test_find_unconditional_deps_pure_impl(env, _target):
    """Verifies that all reachable nodes in a purely unconditional cycle are found."""
    edges = {
        "A": [{"dep": "B"}],
        "B": [{"dep": "C"}],
        "C": [{"dep": "A"}],
    }
    other_members = ["B", "C"]
    
    deps = find_unconditional_deps("A", other_members, edges)
    
    env.expect.that_collection(deps).contains_exactly(["B", "C"])

def _test_find_unconditional_deps_pure(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_find_unconditional_deps_pure_impl)

# ── Test: Find Unconditional Deps (Mixed) ────────────────────────────

def _test_find_unconditional_deps_mixed_impl(env, _target):
    """Verifies that conditional edges block unconditional reachability."""
    edges = {
        "A": [{"dep": "B"}],
        "B": [{"dep": "C", "marker": "sys_platform == 'win32'"}],
        "C": [{"dep": "A"}],
    }
    other_members = ["B", "C"]
    
    deps = find_unconditional_deps("A", other_members, edges)
    
    # B is reachable unconditionally.
    # C is only reachable via B's conditional edge, so it should NOT be in the list.
    env.expect.that_collection(deps).contains_exactly(["B"])

def _test_find_unconditional_deps_mixed(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_find_unconditional_deps_mixed_impl)

# ── Test: Find Unconditional Deps (Multipath) ────────────────────────

def _test_find_unconditional_deps_multipath_impl(env, _target):
    """Verifies that if ANY path is unconditional, the node is unconditional."""
    edges = {
        "A": [{"dep": "B"}, {"dep": "C", "marker": "sys_platform == 'win32'"}],
        "B": [{"dep": "C"}],
        "C": [{"dep": "A"}],
    }
    other_members = ["B", "C"]
    
    deps = find_unconditional_deps("A", other_members, edges)
    
    # B is direct unconditional.
    # C is reachable conditionally (A->C) but ALSO unconditionally (A->B->C).
    # Unconditional wins.
    env.expect.that_collection(deps).contains_exactly(["B", "C"])

def _test_find_unconditional_deps_multipath(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_find_unconditional_deps_multipath_impl)


# ── Test Suite ───────────────────────────────────────────────────────

def cycle_member_marker_deps_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_linear_chain_collapsing,
            _test_multipath_guard,
            _test_direct_dep_guard,
            _test_find_unconditional_deps_pure,
            _test_find_unconditional_deps_mixed,
            _test_find_unconditional_deps_multipath,
        ],
    )

