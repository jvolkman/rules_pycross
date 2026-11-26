"""Pure reachability planning for cycle SCC members with PEP 508 markers.

Computes unconditional in-cycle dependencies and grouped conditional reachability
checks at repo-rule time (used by `//pycross/private/lock_render:cycles.bzl`).

Optimization: members that form unconditional linear chains are grouped together
and share a single reachability check.  For example, in a cycle where
A→B(marker)→C→D→A, nodes C and D are only reachable through B's marker gate.
Since C has one inbound edge (from B, unconditional) and D has one inbound edge
(from C, unconditional), they are collapsed into B's reachability group.  This
reduces the number of evaluator targets from N×(N-1) towards N×G where G is
the number of reachability groups (G ≤ N-1).
"""

load("//pycross/private:util.bzl", "marker_evaluator_name", "marker_uses_extra", "parse_package_key", "sanitize_name")

def find_unconditional_deps(member, other_members, edges):
    """Finds all members unconditionally reachable from member within the cycle.

    Uses a simple BFS traversal following only unconditional edges (no markers).

    Args:
        member: The starting cycle member.
        other_members: List of other member keys in the cycle.
        edges: Parsed edge dict: {node: [{dep, marker?}, ...], ...}.

    Returns:
        A list of package keys that are unconditionally reachable from `member`.
    """
    cycle_members = {m: True for m in other_members}
    cycle_members[member] = True

    unconditional = {}
    queue = [member]
    visited = {member: True}

    # Bounded BFS — each node is enqueued at most once (guarded by `visited`),
    # so the queue length never exceeds len(cycle_members).
    for _ in range(len(other_members) + 1):
        if not queue:
            break

        # Starlark lacks list.pop(0); slice instead (queue is small).
        curr = queue[0]
        queue = queue[1:]

        curr_edges = edges.get(curr, [])
        for edge in curr_edges:
            dep = edge["dep"]
            if dep not in cycle_members:
                continue
            if edge.get("marker") or dep in visited:
                continue
            visited[dep] = True
            if dep != member:
                unconditional[dep] = True
            queue.append(dep)

    return sorted(unconditional.keys())

def compute_reachability_groups(member, other_members, edges):
    """Compute groups of cycle members that share identical reachability.

    Uses the conservative single-inbound-edge rule: a node is collapsed into
    its predecessor's group only if it has exactly one inbound edge within
    the cycle and that edge is unconditional (no marker).

    Args:
        member: The current cycle member (source for reachability).
        other_members: List of other member keys in the cycle.
        edges: Parsed edge dict: {node: [{dep, marker?}, ...], ...}.

    Returns:
        A list of (representative, group_members) tuples, where
        `representative` is the member to check reachability for
        and `group_members` is a list of all members gated behind it
        (including the representative itself).
    """
    members_set = {m: True for m in other_members}
    members_set[member] = True

    # Step 1: compute inbound edges for each member in members_set from all cycle nodes.
    inbound = {}  # node -> list of (source, has_marker)
    for src, edge_list in edges.items():
        for edge in edge_list:
            dep = edge["dep"]
            if dep not in members_set:
                continue
            has_marker = bool(edge.get("marker"))
            if dep not in inbound:
                inbound[dep] = []
            inbound[dep].append((src, has_marker))

    # Step 2: identify which nodes can be collapsed into their predecessor.
    # A node can be collapsed if:
    #   - It has exactly one inbound edge within the cycle
    #   - That edge is unconditional (no marker)
    #   - The predecessor is in other_members (not `member` itself and not an
    #     excluded unconditional member)
    collapsible = {}  # node -> predecessor
    for node in other_members:
        node_inbound = inbound.get(node, [])
        if len(node_inbound) != 1:
            continue
        pred, has_marker = node_inbound[0]
        if not has_marker and pred != member and pred in members_set:
            collapsible[node] = pred

    # Step 3: resolve chains.  If C -> B -> A in the collapsible map, C's
    # representative is A (the first non-collapsible ancestor).
    #
    # A cycle in the collapsible chain occurs when every node in a sub-cycle
    # has exactly one unconditional inbound edge from another collapsible node.
    # For example, with member M and cycle M → A → B → C → A:
    #
    #   collapsible = {A: C, B: A, C: B}
    #        A ← C
    #        ↓   ↑
    #        B → ·
    #
    # Following the chain A → C → B → A loops forever without cycle detection.
    def _find_representative(node):
        visited = {}
        current = node
        for _ in range(len(other_members) + 1):  # safety bound
            if current not in collapsible:
                return current
            if current in visited:
                # Cycle in the collapsible chain — break it.
                return current
            visited[current] = True
            current = collapsible[current]
        return current

    # Step 4: build groups keyed by representative.
    groups = {}  # representative -> list of members
    for m in other_members:
        rep = _find_representative(m)
        if rep not in groups:
            groups[rep] = []
        groups[rep].append(m)

    # Return as sorted list of (representative, group_members).
    return [(rep, sorted(group_members)) for rep, group_members in sorted(groups.items())]

def select_canonical_source(member, unconditional_deps, edges):
    """Selects a canonical source node in U(member) with identical conditional reachability.

    Let U(member) = {member} | set(unconditional_deps). Any active path from
    `member` to a conditional node outside U(member) must exit U(member) via a
    marked edge from some frontier node in:
        F(member) = {u in U(member) | exists (u -> v) in edges with v not in U(member)}
    Any node `s` in U(member) satisfies U(s) <= U(member), so if `s`
    unconditionally reaches every node in F(member), then `s` and `member` have
    identical reachability to all conditional nodes outside U(member).

    Args:
        member: The current cycle member key.
        unconditional_deps: List of member keys unconditionally reachable from `member`.
        edges: Dict edge map: {node: [{"dep": key, "marker": expr}, ...], ...}.

    Returns:
        A canonical source member key in U(member).
    """
    unconditional_set = {member: True}
    for u in unconditional_deps:
        unconditional_set[u] = True

    sorted_unconditional = sorted(unconditional_set.keys())
    frontier = [
        u
        for u in sorted_unconditional
        if any([e["dep"] not in unconditional_set for e in edges.get(u, [])])
    ]
    if not frontier:
        return member
    if len(frontier) == 1:
        return frontier[0]

    candidates = [frontier[0]]
    if sorted_unconditional[0] != frontier[0]:
        candidates.append(sorted_unconditional[0])

    for cand in candidates:
        cand_other = [u for u in sorted_unconditional if u != cand]
        cand_reach = {cand: True}
        for u in find_unconditional_deps(cand, cand_other, edges):
            cand_reach[u] = True
        if all([f in cand_reach for f in frontier]):
            return cand

    return member

def single_incoming_marker(member, unconditional_deps, group_members, edges):
    """Returns the single (marker, effective_extra) gating `group_members` from U(member), or None.

    Let U(member) = {member} | set(unconditional_deps) and G = set(group_members).
    If every edge (u -> v) in `edges` entering G from outside G (u not in G, v in G)
    satisfies:
      1. u in U(member), and
      2. edge.get("marker") is a non-empty string `m` and `(m, effective_extra(u, m))`
         is identical across all such edges,
    and at least one such edge exists, then reachability from `member` to any node
    in G is equivalent to evaluating `m` with `extra = effective_extra(u, m)`.
    Otherwise returns None.

    Args:
        member: The current cycle member key.
        unconditional_deps: List of member keys unconditionally reachable from `member`.
        group_members: List of member keys in the reachability group.
        edges: Dict edge map: {node: [{"dep": key, "marker": expr}, ...], ...}.

    Returns:
        A 2-tuple `(marker_str, effective_extra)`, or None if reachability cannot be
        reduced to a single 1-hop marker from U(member).
    """
    unconditional_set = {member: True}
    for u in unconditional_deps:
        unconditional_set[u] = True
    group_set = {g: True for g in group_members}

    gate = None
    for src, edge_list in edges.items():
        if src in group_set:
            continue
        for edge in edge_list:
            if edge["dep"] not in group_set:
                continue
            if src not in unconditional_set:
                return None
            m = edge.get("marker")
            if not m:
                return None
            src_extra = parse_package_key(src).extra
            src_extra = src_extra if (src_extra and marker_uses_extra(m)) else ""
            edge_gate = (m, src_extra)
            if gate == None:
                gate = edge_gate
            elif gate != edge_gate:
                return None

    return gate

def plan_cycle_member_deps(member, edges):
    """Computes the unconditional deps and conditional group plan for `member`.

    Args:
        member: The package key of this cycle member.
        edges: Dict edge map: {node: [{"dep": key, "marker": expr}, ...], ...}.

    Returns:
        A struct with:
          - unconditional_deps: sorted list of unconditionally reachable member keys.
          - conditional_groups: list of structs for each reachability group:
              - representative: group representative key
              - group_members: sorted list of member keys in the group
              - single_marker: 1-hop marker string from U(member), or None
              - single_extra: effective extra of the 1-hop source node, or ""
              - eval_match_name: pre-rendered _marker_eval_*_match target name, or None
              - source: canonical source key in U(member)
              - pair_name: deduplicated _cycle_needed_* evaluator target name
    """
    other_members = [m for m in sorted(edges.keys()) if m != member]
    if not other_members:
        return struct(
            unconditional_deps = [],
            conditional_groups = [],
        )

    # 1. Find unconditionally reachable deps
    unconditional_deps = find_unconditional_deps(member, other_members, edges)

    # 2. Filter other_members to only include those NOT unconditionally reachable.
    # compute_reachability_groups still inspects inbound edges from all nodes in
    # `edges` (including unconditional members) so that marked edges from
    # unconditional members into conditional members are counted and prevent
    # false single-inbound collapses.
    unconditional_set = {u: True for u in unconditional_deps}
    conditional_members = [m for m in other_members if m not in unconditional_set]

    # 3. Compute groups for conditional members only
    groups = compute_reachability_groups(member, conditional_members, edges)
    if not groups:
        return struct(
            unconditional_deps = unconditional_deps,
            conditional_groups = [],
        )

    source = select_canonical_source(member, unconditional_deps, edges)

    conditional_groups = []
    for representative, group_members in groups:
        single_gate = single_incoming_marker(
            member,
            unconditional_deps,
            group_members,
            edges,
        )
        single_marker = single_gate[0] if single_gate else None
        single_extra = single_gate[1] if single_gate else ""
        eval_match_name = (
            marker_evaluator_name(single_marker, single_extra) + "_match" if single_gate else None
        )
        pair_name = "_cycle_needed_{}_{}".format(
            sanitize_name(source),
            sanitize_name(representative),
        )
        conditional_groups.append(struct(
            representative = representative,
            group_members = group_members,
            single_marker = single_marker,
            single_extra = single_extra,
            eval_match_name = eval_match_name,
            source = source,
            pair_name = pair_name,
        ))

    return struct(
        unconditional_deps = unconditional_deps,
        conditional_groups = conditional_groups,
    )
