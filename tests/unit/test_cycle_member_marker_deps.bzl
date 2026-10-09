"""Tests for cycle reachability group computation."""

load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_dep_needed.bzl", "is_reachable")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:cycle_member_marker_deps.bzl",
    "compute_reachability_groups",
    "find_unconditional_deps",
    "plan_cycle_member_deps",
    "pycross_cycle_member_marker_deps",
    "select_canonical_source",
    "single_incoming_marker",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "marker_evaluator_name")

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

# ── Test: Find Unconditional Deps (All Conditional) ──────────────────

def _test_find_unconditional_deps_all_conditional_impl(env, _target):
    """Verifies that no unconditional deps are found when all edges have markers."""
    edges = {
        "A": [{"dep": "B", "marker": "sys_platform == 'linux'"}],
        "B": [{"dep": "C", "marker": "python_version >= '3.11'"}],
        "C": [{"dep": "A", "marker": "os_name == 'posix'"}],
    }
    other_members = ["B", "C"]

    deps = find_unconditional_deps("A", other_members, edges)

    # No unconditional edges exist, so the result should be empty.
    env.expect.that_collection(deps).contains_exactly([])

def _test_find_unconditional_deps_all_conditional(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_find_unconditional_deps_all_conditional_impl)

# ── Test: Unconditional Member Marked Edge Prevents False Collapse ────

def _test_unconditional_member_marked_edge_no_collapse_impl(env, _target):
    """Verifies that marked edges from stripped unconditional deps still count as inbound edges.

    Cycle:
      A -> B
      B -> C [m1]
      C -> D
      B -> D [m2]
      D -> A
    From A: B is unconditionally reachable and stripped before calling
    compute_reachability_groups("A", ["C", "D"], edges).
    D has two inbound edges in the cycle (C -> D and B -> D [m2]), so D must
    NOT be collapsed into C's group.
    """
    edges = {
        "A": [{"dep": "B"}],
        "B": [
            {"dep": "C", "marker": "sys_platform == 'linux'"},
            {"dep": "D", "marker": "sys_platform == 'darwin'"},
        ],
        "C": [{"dep": "D"}],
        "D": [{"dep": "A"}],
    }
    other_members = ["C", "D"]

    groups = compute_reachability_groups("A", other_members, edges)

    env.expect.that_int(len(groups)).equals(2)

    rep0, members0 = groups[0]
    env.expect.that_str(rep0).equals("C")
    env.expect.that_collection(members0).contains_exactly(["C"])

    rep1, members1 = groups[1]
    env.expect.that_str(rep1).equals("D")
    env.expect.that_collection(members1).contains_exactly(["D"])

def _test_unconditional_member_marked_edge_no_collapse(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_unconditional_member_marked_edge_no_collapse_impl,
    )

# ── Test: Select Canonical Source (Hub Pattern) ───────────────────────

def _test_select_canonical_source_hub_impl(env, _target):
    """Verifies that in a hub-linked cycle, both unconditional and conditional members pick the hub."""
    edges = {
        "__hub__": [
            {"dep": "pkg_a"},
            {"dep": "pkg_b"},
            {"dep": "cond_c", "marker": "sys_platform == 'linux'"},
            {"dep": "cond_d", "marker": "sys_platform == 'darwin'"},
        ],
        "pkg_a": [{"dep": "__hub__"}],
        "pkg_b": [{"dep": "__hub__"}],
        "cond_c": [{"dep": "__hub__"}],
        "cond_d": [{"dep": "__hub__"}],
    }
    all_members = sorted(edges.keys())

    for m in all_members:
        other = [x for x in all_members if x != m]
        uncond = find_unconditional_deps(m, other, edges)
        src = select_canonical_source(m, uncond, edges)
        env.expect.that_str(src).equals("__hub__")

def _test_select_canonical_source_hub(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_select_canonical_source_hub_impl)

# ── Test: Select Canonical Source (Multi-Frontier SCC) ────────────────

def _test_select_canonical_source_multi_frontier_scc_impl(env, _target):
    """Verifies that members of a strongly connected unconditional sub-cycle share frontier[0]."""
    edges = {
        "A": [
            {"dep": "B"},
            {"dep": "C", "marker": "sys_platform == 'linux'"},
        ],
        "B": [
            {"dep": "A"},
            {"dep": "D", "marker": "sys_platform == 'darwin'"},
        ],
        "C": [{"dep": "A"}],
        "D": [{"dep": "B"}],
    }
    all_members = sorted(edges.keys())

    for m in ["A", "B"]:
        other = [x for x in all_members if x != m]
        uncond = find_unconditional_deps(m, other, edges)
        src = select_canonical_source(m, uncond, edges)
        env.expect.that_str(src).equals("A")

    # For C: U(C) = {A, B, C}, so only B -> D exits U(C); frontier is ["B"].
    uncond_c = find_unconditional_deps("C", ["A", "B", "D"], edges)
    env.expect.that_str(select_canonical_source("C", uncond_c, edges)).equals("B")

    # For D: U(D) = {A, B, D}, so only A -> C exits U(D); frontier is ["A"].
    uncond_d = find_unconditional_deps("D", ["A", "B", "C"], edges)
    env.expect.that_str(select_canonical_source("D", uncond_d, edges)).equals("A")

def _test_select_canonical_source_multi_frontier_scc(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_select_canonical_source_multi_frontier_scc_impl,
    )

# ── Test: Select Canonical Source (Tree Root and Fallback) ────────────

def _test_select_canonical_source_tree_impl(env, _target):
    """Verifies tree root selection via sorted_unconditional[0] and fallback to member."""

    # Case 1: Root "A" (< "B", "C") reaches both frontier nodes "B" and "C".
    edges_root_first = {
        "A": [{"dep": "B"}, {"dep": "C"}],
        "B": [{"dep": "D", "marker": "sys_platform == 'linux'"}],
        "C": [{"dep": "E", "marker": "sys_platform == 'darwin'"}],
        "D": [{"dep": "A"}],
        "E": [{"dep": "A"}],
    }
    uncond_a = find_unconditional_deps("A", ["B", "C", "D", "E"], edges_root_first)
    env.expect.that_str(select_canonical_source("A", uncond_a, edges_root_first)).equals("A")

    # Case 2: Root "Z" (> "B", "C"): neither frontier[0] ("B") nor sorted_unconditional[0] ("B")
    # reaches "C", so it falls back to member "Z".
    edges_root_last = {
        "Z": [{"dep": "B"}, {"dep": "C"}],
        "B": [{"dep": "D", "marker": "sys_platform == 'linux'"}],
        "C": [{"dep": "E", "marker": "sys_platform == 'darwin'"}],
        "D": [{"dep": "Z"}],
        "E": [{"dep": "Z"}],
    }
    uncond_z = find_unconditional_deps("Z", ["B", "C", "D", "E"], edges_root_last)
    env.expect.that_str(select_canonical_source("Z", uncond_z, edges_root_last)).equals("Z")

def _test_select_canonical_source_tree(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_select_canonical_source_tree_impl)

# ── Test: Single Incoming Marker (1-Hop Shortcut vs Multi-Hop Fallback) ──

def _test_single_incoming_marker_impl(env, _target):
    """Verifies single_incoming_marker detects 1-hop marker gates and rejects multi-hop/multi-marker."""

    # Case 1: 1-hop edge from U(A) = {A, B} into group {C, D}.
    edges_one_hop = {
        "A@1.0": [{"dep": "B@1.0"}],
        "B@1.0": [{"dep": "C@1.0", "marker": "sys_platform == 'darwin'"}],
        "C@1.0": [{"dep": "D@1.0"}],
        "D@1.0": [{"dep": "A@1.0"}],
    }
    env.expect.that_bool(
        single_incoming_marker("A@1.0", ["B@1.0"], ["C@1.0", "D@1.0"], edges_one_hop) == ("sys_platform == 'darwin'", ""),
    ).equals(True)

    # Case 2: Multiple edges from U(A) = {A, B} with the SAME marker and effective extra.
    edges_same_marker = {
        "A@1.0": [{"dep": "B@1.0"}, {"dep": "C@1.0", "marker": "sys_platform == 'darwin'"}],
        "B@1.0": [{"dep": "C@1.0", "marker": "sys_platform == 'darwin'"}],
        "C@1.0": [{"dep": "A@1.0"}],
    }
    env.expect.that_bool(
        single_incoming_marker("A@1.0", ["B@1.0"], ["C@1.0"], edges_same_marker) == ("sys_platform == 'darwin'", ""),
    ).equals(True)

    # Case 3: Multiple edges from U(A) = {A, B} with DIFFERENT markers -> None.
    edges_diff_markers = {
        "A@1.0": [{"dep": "B@1.0"}, {"dep": "C@1.0", "marker": "sys_platform == 'linux'"}],
        "B@1.0": [{"dep": "C@1.0", "marker": "sys_platform == 'darwin'"}],
        "C@1.0": [{"dep": "A@1.0"}],
    }
    env.expect.that_bool(
        single_incoming_marker("A@1.0", ["B@1.0"], ["C@1.0"], edges_diff_markers) == None,
    ).equals(True)

    # Case 4: Same `extra == 'x'` marker from two sources with DIFFERENT extras -> None.
    edges_diff_extras = {
        "A[x]@1.0": [{"dep": "B@1.0"}, {"dep": "C@1.0", "marker": "extra == 'x'"}],
        "B@1.0": [{"dep": "C@1.0", "marker": "extra == 'x'"}],
        "C@1.0": [{"dep": "A[x]@1.0"}],
    }
    env.expect.that_bool(
        single_incoming_marker("A[x]@1.0", ["B@1.0"], ["C@1.0"], edges_diff_extras) == None,
    ).equals(True)

    # Case 5: Multi-hop conditional path (B is conditional, B -> C [m2]) -> None for C.
    edges_two_hop = {
        "A@1.0": [{"dep": "B@1.0", "marker": "sys_platform == 'linux'"}],
        "B@1.0": [{"dep": "C@1.0", "marker": "python_version < '3.13'"}],
        "C@1.0": [{"dep": "A@1.0"}],
    }
    env.expect.that_bool(
        single_incoming_marker("A@1.0", [], ["C@1.0"], edges_two_hop) == None,
    ).equals(True)

def _test_single_incoming_marker(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_single_incoming_marker_impl)

# ── Test: Property/Fuzz Reachability Equivalence ─────────────────────

_FUZZ_ATOMS = [
    "os_name == 'x'",
    "sys_platform == 'x'",
    "platform_machine == 'x'",
    "extra == 'x'",
]

_FUZZ_BASE_ENV = {
    "implementation_name": "cpython",
    "implementation_version": "3.12.0",
    "platform_python_implementation": "CPython",
    "platform_release": "",
    "platform_system": "Linux",
    "platform_version": "",
    "python_full_version": "3.12.0",
    "python_version": "3.12",
    "extra": "",
}

def _fuzz_envs():
    envs = []
    for bits in range(8):
        env = dict(_FUZZ_BASE_ENV)
        env["os_name"] = "x" if bits & 1 else "y"
        env["sys_platform"] = "x" if bits & 2 else "y"
        env["platform_machine"] = "x" if bits & 4 else "y"
        envs.append(env)
    return envs

def _lcg(state):
    return (state * 6364136223846793005 + 1442695040888963407) % (1 << 64)

def _fuzz_node_key(i):
    if i % 3 == 1:
        return "n{}[x]@1".format(i)
    if i % 3 == 2:
        return "n{}[y]@1".format(i)
    return "n{}@1".format(i)

def _gen_fuzz_graph(seed, n, mode):
    """Generates a deterministic strongly connected marker graph over n nodes (with extras)."""
    state = seed
    nodes = [_fuzz_node_key(i) for i in range(n)]
    edges = {node: {} for node in nodes}

    def pick_marker(r):
        k = r % 6
        if k <= 1:
            return ""
        return _FUZZ_ATOMS[k - 2]

    if mode == 1:
        for i in range(1, n):
            state = _lcg(state)
            edges[nodes[0]][nodes[i]] = pick_marker(state >> 33)
            edges[nodes[i]][nodes[0]] = ""
    else:
        for i in range(n):
            state = _lcg(state)
            edges[nodes[i]][nodes[(i + 1) % n]] = pick_marker(state >> 33)

    for _ in range(n * 2):
        state = _lcg(state)
        a = (state >> 20) % n
        state = _lcg(state)
        b = (state >> 20) % n
        state = _lcg(state)
        if a == b:
            continue
        edges[nodes[a]][nodes[b]] = pick_marker(state >> 33)

    out = {}
    for src in nodes:
        lst = []
        for dep in sorted(edges[src].keys()):
            m = edges[src][dep]
            e = {"dep": dep}
            if m:
                e["marker"] = m
            lst.append(e)
        out[src] = lst
    return out, state

def _included_from_plan(plan, edges, env, use_single_marker, member):
    result = {member: True}
    for u in plan.unconditional_deps:
        result[u] = True
    for cg in plan.conditional_groups:
        if use_single_marker and cg.single_marker:
            src_node = "a[{}]@1".format(cg.single_extra) if cg.single_extra else "a@1"
            gate = is_reachable({src_node: [{"dep": "b@1", "marker": cg.single_marker}]}, src_node, "b@1", env)
        else:
            gate = is_reachable(edges, cg.source, cg.representative, env)
        if gate:
            for g in cg.group_members:
                result[g] = True
    return sorted(result.keys())

def _truth_reachable(member, edges, env):
    return sorted([t for t in edges.keys() if is_reachable(edges, member, t, env)])

def _test_fuzz_reachability_equivalence_impl(env, _target):
    """Compares plan_cycle_member_deps against ground-truth BFS across 100 random SCC/hub graphs."""
    envs = _fuzz_envs()
    seed = 12345
    mismatches = []

    for it in range(100):
        n = 3 + (it % 5)
        gmode = 1 if it % 4 == 3 else 0
        edges, seed = _gen_fuzz_graph(seed, n, gmode)
        for member in sorted(edges.keys()):
            plan = plan_cycle_member_deps(member, edges)
            for m_env in envs:
                want = _truth_reachable(member, edges, m_env)
                got_shortcut = _included_from_plan(plan, edges, m_env, True, member)
                got_fallback = _included_from_plan(plan, edges, m_env, False, member)
                if got_shortcut != want or got_fallback != want:
                    mismatches.append("iter={} member={} got_shortcut={} got_fallback={} want={}".format(
                        it,
                        member,
                        got_shortcut,
                        got_fallback,
                        want,
                    ))

    env.expect.that_collection(mismatches).contains_exactly([])

def _test_fuzz_reachability_equivalence(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_fuzz_reachability_equivalence_impl,
    )

# ── Test: Macro Expansion (native.existing_rule paths) ────────────────

def _stub_py_library_impl(_ctx):
    return [PyInfo(transitive_sources = depset())]

_stub_py_library = rule(
    implementation = _stub_py_library_impl,
    provides = [PyInfo],
)

_CheckRuleNamesInfo = provider(
    "Holds snapshotted rule names for macro expansion testing.",
    fields = ["m1_evaluators", "m2_evaluators"],
)

def _rule_CheckRuleNames_impl(ctx):
    return [
        DefaultInfo(),
        _CheckRuleNamesInfo(
            m1_evaluators = ctx.attr.m1_evaluators,
            m2_evaluators = ctx.attr.m2_evaluators,
        ),
    ]

_check_rule_names_holder = rule(
    implementation = _rule_CheckRuleNames_impl,
    attrs = {
        "m1_evaluators": attr.string_list(),
        "m2_evaluators": attr.string_list(),
    },
)

def _test_macro_existing_rule_paths_impl(env, target):
    info = target[_CheckRuleNamesInfo]
    env.expect.that_collection(info.m1_evaluators).contains_exactly([])
    env.expect.that_collection(info.m2_evaluators).contains_exactly([
        "_cycle_needed_m2_hub_1_0_m2_c_1_0",
    ])

def _test_macro_existing_rule_paths(name):
    # 1. Hub graph WITH pre-created _marker_eval_*_match target -> 0 _cycle_needed_* rules.
    m1_edges = {
        "m1_hub@1.0": [
            {"dep": "m1_a@1.0"},
            {"dep": "m1_c@1.0", "marker": "sys_platform == 'm1_linux'"},
        ],
        "m1_a@1.0": [{"dep": "m1_hub@1.0"}],
        "m1_c@1.0": [{"dep": "m1_hub@1.0"}],
    }
    native.config_setting(
        name = marker_evaluator_name("sys_platform == 'm1_linux'") + "_match",
        values = {"compilation_mode": "opt"},
    )
    for m in m1_edges.keys():
        _stub_py_library(name = "_raw_" + m, tags = ["manual"])
        pycross_cycle_member_marker_deps(
            name = m,
            raw_name = "_raw_" + m,
            member = m,
            edges = m1_edges,
        )

    # 2. Hub graph WITHOUT pre-created _marker_eval_*_match target -> deduplicated
    #    _cycle_needed_* per (canonical_source, rep).
    m2_edges = {
        "m2_hub@1.0": [
            {"dep": "m2_a@1.0"},
            {"dep": "m2_a[dev]@1.0"},
            {"dep": "m2_c@1.0", "marker": "sys_platform == 'm2_linux'"},
        ],
        "m2_a@1.0": [{"dep": "m2_hub@1.0"}],
        "m2_a[dev]@1.0": [{"dep": "m2_hub@1.0"}],
        "m2_c@1.0": [{"dep": "m2_hub@1.0"}],
    }
    for m in m2_edges.keys():
        _stub_py_library(name = "_raw_" + m, tags = ["manual"])
        pycross_cycle_member_marker_deps(
            name = m,
            raw_name = "_raw_" + m,
            member = m,
            edges = m2_edges,
        )

    existing = native.existing_rules().keys()
    m1_evaluators = sorted([
        r
        for r in existing
        if r.startswith("_cycle_needed_m1_") and not r.endswith("_match")
    ])
    m2_evaluators = sorted([
        r
        for r in existing
        if r.startswith("_cycle_needed_m2_") and not r.endswith("_match")
    ])

    util.helper_target(
        _check_rule_names_holder,
        name = name + "_subject",
        m1_evaluators = m1_evaluators,
        m2_evaluators = m2_evaluators,
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_macro_existing_rule_paths_impl,
    )

# ── Test: Extra on Intermediate Cycle Node Is Evaluated per Source Node ──

def _test_cycle_extra_on_intermediate_node_impl(env, _target):
    """Entering via A@1.0: A@1.0 -> B[x]@1.0 -> C@1.0 [extra == 'x'] -> A@1.0 must reach C@1.0."""
    edges = {
        "A@1.0": [{"dep": "B[x]@1.0"}],
        "B[x]@1.0": [{"dep": "C@1.0", "marker": "extra == 'x'"}],
        "C@1.0": [{"dep": "A@1.0"}],
    }
    base_env = dict(_FUZZ_BASE_ENV)
    base_env["extra"] = ""

    # 1. BFS ground truth (is_reachable) must activate B[x]@1.0 -> C@1.0 using B[x]@1.0's extra.
    env.expect.that_bool(is_reachable(edges, "A@1.0", "C@1.0", base_env)).equals(True)

    # 2. single_incoming_marker and plan_cycle_member_deps must carry B[x]@1.0's extra ("x").
    plan = plan_cycle_member_deps("A@1.0", edges)
    env.expect.that_int(len(plan.conditional_groups)).equals(1)
    cg = plan.conditional_groups[0]
    env.expect.that_str(cg.eval_match_name).equals(
        marker_evaluator_name("extra == 'x'", "x") + "_match",
    )

def _test_cycle_extra_on_intermediate_node(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_cycle_extra_on_intermediate_node_impl,
    )

# ── Test: Entry Extra Does Not Bleed Into Base Package Edges ──────────

def _test_cycle_entry_extra_does_not_bleed_impl(env, _target):
    """Entering via A[test]@1.0: A[test]@1.0 -> B@1.0 -> C@1.0 [extra == 'test'] must NOT reach C@1.0."""
    edges = {
        "A[test]@1.0": [{"dep": "B@1.0"}],
        "B@1.0": [{"dep": "C@1.0", "marker": "extra == 'test'"}],
        "C@1.0": [{"dep": "A[test]@1.0"}],
    }
    test_env = dict(_FUZZ_BASE_ENV)
    test_env["extra"] = "test"

    # 1. Even if caller passes extra = "test" in env, B@1.0 is a base package (extra = "")
    #    so its extra == 'test' edge must NOT fire.
    env.expect.that_bool(is_reachable(edges, "A[test]@1.0", "C@1.0", test_env)).equals(False)

    # 2. plan_cycle_member_deps for A[test]@1.0 must key the 1-hop evaluator on B@1.0's extra (""),
    #    not A[test]@1.0's extra ("test").
    plan = plan_cycle_member_deps("A[test]@1.0", edges)
    env.expect.that_int(len(plan.conditional_groups)).equals(1)
    cg = plan.conditional_groups[0]
    env.expect.that_str(cg.eval_match_name).equals(
        marker_evaluator_name("extra == 'test'", "") + "_match",
    )

def _test_cycle_entry_extra_does_not_bleed(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_cycle_entry_extra_does_not_bleed_impl,
    )

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
            _test_find_unconditional_deps_all_conditional,
            _test_unconditional_member_marked_edge_no_collapse,
            _test_select_canonical_source_hub,
            _test_select_canonical_source_multi_frontier_scc,
            _test_select_canonical_source_tree,
            _test_single_incoming_marker,
            _test_fuzz_reachability_equivalence,
            _test_macro_existing_rule_paths,
            _test_cycle_extra_on_intermediate_node,
            _test_cycle_entry_extra_does_not_bleed,
        ],
    )
