"""Tests for cycle reachability group computation and repo-rule-time cycle rendering."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:cycle_dep_needed.bzl", "is_reachable")

# buildifier: disable=bzl-visibility
load("//pycross/private:repo_slots.bzl", "assign_fork_slots")

# buildifier: disable=bzl-visibility
load("//pycross/private:spoke_repo.bzl", "build_spoke_payloads", "render_spoke_build")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "hex_hash8", "marker_evaluator_name")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private/lock_render:cycle_plan.bzl",
    "compute_reachability_groups",
    "find_unconditional_deps",
    "plan_cycle_member_deps",
    "select_canonical_source",
    "single_incoming_marker",
)

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

# ── Test: Repo-Rule-Time Cycle Rendering Paths ────────────────────────

def _render_spokes(lock, repo_map):
    pkgs = lock["packages"]
    slots = assign_fork_slots(pkgs)
    spokes = build_spoke_payloads(
        "ws",
        "ws__state",
        pkgs,
        repo_map,
        {},
        slots,
        cycle_groups = lock.get("cycle_groups"),
    )
    return {name: render_spoke_build(s.payload) for name, s in spokes.items()}

def _test_repo_time_cycle_rendering_impl(env, _target):
    # 1. Hub graph with 1-hop markers -> 0 _cycle_needed_* targets,
    #    reuses local _marker_eval_*_match, 0 _EDGES_JSON, no cycle_dep_needed.bzl load,
    #    and combines sibling groups sharing the same 1-hop match into one select().
    hub_lock = {
        "cycle_groups": {
            "cycle_hub": ["hub@1.0", "a@1.0", "c1@1.0", "c2@1.0"],
        },
        "packages": {
            "hub@1.0": {
                "cycle_group": "cycle_hub",
                "wheel_candidates": [{"filename": "hub-1.0-py3-none-any.whl", "file_reference": {"key": "hub_w"}}],
                "marker_dependencies": [
                    {"key": "a@1.0"},
                    {"key": "c1@1.0", "marker": "sys_platform == 'linux'"},
                    {"key": "c2@1.0", "marker": "sys_platform == 'linux'"},
                ],
            },
            "a@1.0": {
                "cycle_group": "cycle_hub",
                "wheel_candidates": [{"filename": "a-1.0-py3-none-any.whl", "file_reference": {"key": "a_w"}}],
                "marker_dependencies": [{"key": "hub@1.0"}],
            },
            "c1@1.0": {
                "cycle_group": "cycle_hub",
                "wheel_candidates": [{"filename": "c1-1.0-py3-none-any.whl", "file_reference": {"key": "c1_w"}}],
                "marker_dependencies": [{"key": "hub@1.0"}],
            },
            "c2@1.0": {
                "cycle_group": "cycle_hub",
                "wheel_candidates": [{"filename": "c2-1.0-py3-none-any.whl", "file_reference": {"key": "c2_w"}}],
                "marker_dependencies": [{"key": "hub@1.0"}],
            },
        },
    }
    hub_spokes = _render_spokes(
        hub_lock,
        {"hub_w": "@r//hub:w", "a_w": "@r//a:w", "c1_w": "@r//c1:w", "c2_w": "@r//c2:w"},
    )
    hub_all = "\n".join(hub_spokes.values())
    linux_match = marker_evaluator_name("sys_platform == 'linux'") + "_match"
    env.expect.that_bool("_cycle_needed_" in hub_all).equals(False)
    env.expect.that_bool("_EDGES_JSON" in hub_all).equals(False)
    env.expect.that_bool("cycle_dep_needed.bzl" in hub_all).equals(False)
    env.expect.that_str(hub_spokes["hub"]).contains('":{}": ["@ws__pkg_c1//:_raw", "@ws__pkg_c2//:_raw"]'.format(linux_match))
    env.expect.that_str(hub_spokes["a"]).contains('":{}": ["@ws__pkg_c1//:_raw", "@ws__pkg_c2//:_raw"]'.format(linux_match))

    # 2. Multi-hop conditional cycle -> emits _CYCLE_EDGES_JSON and pycross_cycle_dep_needed
    #    with version-free node keys and cross-spoke raw labels.
    multihop_lock = {
        "cycle_groups": {
            "cycle_mh": ["a@1.0", "a_peer@1.0", "b@1.0", "c@1.0"],
        },
        "packages": {
            "a@1.0": {
                "cycle_group": "cycle_mh",
                "wheel_candidates": [{"filename": "a-1.0-py3-none-any.whl", "file_reference": {"key": "a_w"}}],
                "marker_dependencies": [
                    {"key": "a_peer@1.0"},
                    {"key": "b@1.0", "marker": "sys_platform == 'linux'"},
                ],
            },
            "a_peer@1.0": {
                "cycle_group": "cycle_mh",
                "wheel_candidates": [{"filename": "a_peer-1.0-py3-none-any.whl", "file_reference": {"key": "ap_w"}}],
                "marker_dependencies": [{"key": "a@1.0"}],
            },
            "b@1.0": {
                "cycle_group": "cycle_mh",
                "wheel_candidates": [{"filename": "b-1.0-py3-none-any.whl", "file_reference": {"key": "b_w"}}],
                "marker_dependencies": [
                    {"key": "c@1.0", "marker": "python_version < '3.13'"},
                ],
            },
            "c@1.0": {
                "cycle_group": "cycle_mh",
                "wheel_candidates": [{"filename": "c-1.0-py3-none-any.whl", "file_reference": {"key": "c_w"}}],
                "marker_dependencies": [{"key": "a@1.0"}],
            },
        },
    }
    mh_spokes = _render_spokes(
        multihop_lock,
        {"a_w": "@r//a:w", "ap_w": "@r//ap:w", "b_w": "@r//b:w", "c_w": "@r//c:w"},
    )
    a_build = mh_spokes["a"]
    env.expect.that_str(a_build).contains('load("@rules_pycross//pycross/private:cycle_dep_needed.bzl", "pycross_cycle_dep_needed")')
    env.expect.that_int(a_build.count("_CYCLE_EDGES_JSON = ")).equals(1)
    ac_pair = "_cycle_needed_a__c_{}".format(hex_hash8("a|c"))
    env.expect.that_str(a_build).contains('name = "{}",'.format(ac_pair))
    env.expect.that_str(a_build).contains('":{}_match": ["@ws__pkg_c//:_raw"]'.format(ac_pair))
    edges_rhs = a_build.split("_CYCLE_EDGES_JSON = ")[1].split("\n", 1)[0]
    decoded_edges = json.decode(json.decode(edges_rhs))
    env.expect.that_bool("a" in decoded_edges).equals(True)
    env.expect.that_collection([e["dep"] for e in decoded_edges["a"]]).contains_exactly(["a_peer", "b"])

    # 3. Pure unconditional cycle -> direct pycross_library_proxy with flat deps,
    #    0 _cycle_needed_*, 0 _EDGES_JSON, no cycle_dep_needed.bzl load.
    uncond_lock = {
        "cycle_groups": {
            "cycle_uncond": ["u1@1.0", "u2@1.0"],
        },
        "packages": {
            "u1@1.0": {
                "cycle_group": "cycle_uncond",
                "wheel_candidates": [{"filename": "u1-1.0-py3-none-any.whl", "file_reference": {"key": "u1_w"}}],
                "marker_dependencies": [{"key": "u2@1.0"}],
            },
            "u2@1.0": {
                "cycle_group": "cycle_uncond",
                "wheel_candidates": [{"filename": "u2-1.0-py3-none-any.whl", "file_reference": {"key": "u2_w"}}],
                "marker_dependencies": [{"key": "u1@1.0"}],
            },
        },
    }
    uncond_spokes = _render_spokes(uncond_lock, {"u1_w": "@r//u1:w", "u2_w": "@r//u2:w"})
    u1_build = uncond_spokes["u1"]
    env.expect.that_bool("_cycle_needed_" in u1_build).equals(False)
    env.expect.that_bool("_EDGES_JSON" in u1_build).equals(False)
    env.expect.that_bool("cycle_dep_needed.bzl" in u1_build).equals(False)
    env.expect.that_bool("select({" in u1_build).equals(False)
    env.expect.that_str(u1_build).contains(
        'pycross_library_proxy(\n    name = "pkg",\n    actual = ":_raw",\n    deps = [\n        "@ws__pkg_u2//:_raw",\n    ],\n)',
    )

def _test_repo_time_cycle_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_repo_time_cycle_rendering_impl,
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
            _test_repo_time_cycle_rendering,
            _test_cycle_extra_on_intermediate_node,
            _test_cycle_entry_extra_does_not_bleed,
        ],
    )
