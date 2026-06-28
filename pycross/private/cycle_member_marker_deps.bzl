"""Macro for per-member cycle dependency resolution with PEP 508 markers.

Generates reachability-gated cycle member deps using pycross_cycle_dep_needed
evaluators and config_settings, wrapped in a py_library with select() per dep.

Optimization: members that form unconditional linear chains are grouped together
and share a single reachability check.  For example, in a cycle where
A→B(marker)→C→D→A, nodes C and D are only reachable through B's marker gate.
Since C has one inbound edge (from B, unconditional) and D has one inbound edge
(from C, unconditional), they are collapsed into B's reachability group.  This
reduces the number of evaluator targets from N×(N-1) towards N×G where G is
the number of reachability groups (G ≤ N-1).

Usage in generated lock.bzl:
    pycross_cycle_member_marker_deps(
        name = "pkg@1.0",
        raw_name = "_raw_pkg@1.0",
        member = "pkg@1.0",
        members = ["pkg@1.0", "other@2.0", ...],
        edges = '{...}',  # JSON edge map
        sys_platform = select(SYS_PLATFORM_VALUES),
        ...
    )
"""

load("@rules_python//python:defs.bzl", "py_library")
load("//pycross/private:cycle_dep_needed.bzl", "pycross_cycle_dep_needed")

def _sanitize(name):
    """Sanitize a package key for use in target names."""
    return name.replace("@", "_").replace(".", "_").replace("-", "_").replace("[", "_").replace("]", "_")

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

    # Bounded BFS
    for _ in range(len(other_members) + 1):
        if not queue:
            break

        # Starlark doesn't have pop(0), simulate it or use a pointer if list grows big.
        # But here queue is small (cycle members).
        curr = queue[0]
        queue = queue[1:]

        curr_edges = edges.get(curr, [])
        for edge in curr_edges:
            dep = edge["dep"]
            if dep not in cycle_members:
                continue
            has_marker = bool(edge.get("marker"))
            if not has_marker and dep not in visited:
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

    # Step 1: compute inbound edges for each member (only from cycle members).
    inbound = {}  # node -> list of (source, has_marker)
    for src, edge_list in edges.items():
        if src not in members_set:
            continue
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
    #   - The predecessor is NOT the member itself (we always include `member`)
    collapsible = {}  # node -> predecessor
    for node in other_members:
        node_inbound = inbound.get(node, [])
        if len(node_inbound) == 1:
            pred, has_marker = node_inbound[0]
            if not has_marker and pred != member:
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

def pycross_cycle_member_marker_deps(
        name,
        raw_name,
        member,
        members,
        edges,
        **kwargs):
    """Creates select()-gated cycle member deps with grouped reachability checks.

    For each reachability group (set of members with identical reachability
    from this member), creates a single pycross_cycle_dep_needed rule and
    config_setting, then gates all members of the group behind that check.

    Args:
        name: The final target name (e.g. "pkg@1.0").
        raw_name: The raw package target name (e.g. "_raw_pkg@1.0").
        member: The package key of this cycle member.
        members: List of all package keys in the cycle group.
        edges: JSON-encoded edge map: {node: [{dep, marker?}, ...], ...}.
        **kwargs: Marker value attrs (sys_platform, os_name, etc.) passed
                  through to pycross_cycle_dep_needed.
    """
    other_members = [m for m in sorted(members) if m != member]

    if not other_members:
        # Single-member cycle (shouldn't happen, but handle gracefully).
        native.alias(
            name = name,
            actual = ":" + raw_name,
        )
        return

    parsed_edges = json.decode(edges)

    # 1. Find unconditionally reachable deps
    unconditional_deps = find_unconditional_deps(member, other_members, parsed_edges)

    # 2. Add them to unconditional deps list directly
    deps = [":" + raw_name]
    for u_dep in unconditional_deps:
        deps.append(":_raw_" + u_dep)

    # 3. Filter other_members to only include those NOT unconditionally reachable
    unconditional_set = {u: True for u in unconditional_deps}
    conditional_members = [m for m in other_members if m not in unconditional_set]

    # 4. Compute groups for conditional members only
    groups = compute_reachability_groups(member, conditional_members, parsed_edges)

    for representative, group_members in groups:
        pair_name = "_cycle_needed_{}_{}".format(
            _sanitize(member),
            _sanitize(representative),
        )

        # Reachability evaluator: returns FeatureFlagInfo("true"/"false")
        pycross_cycle_dep_needed(
            name = pair_name,
            source = member,
            target = representative,
            edges = edges,
            **kwargs
        )

        # Config setting matching reachable == "true"
        native.config_setting(
            name = pair_name + "_match",
            flag_values = {
                ":" + pair_name: "true",
            },
        )

        # Gate ALL members of this group behind the representative's check
        group_deps = [":_raw_" + m for m in group_members]
        deps = deps + select({
            ":" + pair_name + "_match": group_deps,
            "//conditions:default": [],
        })

    py_library(
        name = name,
        deps = deps,
    )
