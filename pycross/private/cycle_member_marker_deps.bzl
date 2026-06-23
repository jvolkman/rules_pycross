"""Rule for per-member cycle dependency resolution with PEP 508 marker support.

Marker-aware variant of pycross_cycle_member_deps.  Instead of selecting
edges by environment name, this rule evaluates PEP 508 marker expressions
on each edge to determine whether a dependency is active on the current
platform.

Edge format (JSON):
  {
    "alpha@1.0": [
      {"dep": "beta@2.0"},
      {"dep": "gamma@1.0", "marker_ast": {"op": "==", ...}}
    ],
    ...
  }
"""

load(":pep508_evaluator.bzl", "evaluate_marker_expr")
load(":pep508_marker_values.bzl", "collect_markers", "marker_value_attrs")
load(":util.bzl", "merge_py_providers")

def _pycross_cycle_member_marker_deps_impl(ctx):
    member = ctx.attr.member
    edges = json.decode(ctx.attr.edges)
    markers = collect_markers(ctx)

    # Build active adjacency: for each node, the list of deps whose
    # markers evaluate to true (or that are unconditional).
    active_adj = {}
    for src, edge_list in edges.items():
        neighbors = []
        for edge in edge_list:
            marker_ast = edge.get("marker_ast")
            if marker_ast:
                if not evaluate_marker_expr(marker_ast, markers):
                    continue
            neighbors.append(edge["dep"])
        if neighbors:
            active_adj[src] = neighbors

    # BFS from this member to find its transitive in-cycle deps.
    needed = {}
    frontier = list(active_adj.get(member, []))
    for _ in range(len(edges)):
        next_frontier = []
        for node in frontier:
            if node not in needed:
                needed[node] = True
                next_frontier.extend(active_adj.get(node, []))
        frontier = next_frontier
        if not frontier:
            break

    # Filter to needed targets.
    selected = [
        target
        for target, key in ctx.attr.raw_members.items()
        if key in needed
    ]

    merged = merge_py_providers(selected)
    return [merged.default_info, merged.py_info]

pycross_cycle_member_marker_deps = rule(
    implementation = _pycross_cycle_member_marker_deps_impl,
    attrs = {
        "member": attr.string(
            mandatory = True,
            doc = "The package key of the cycle member this target resolves deps for.",
        ),
        "raw_members": attr.label_keyed_string_dict(
            doc = "Map from _raw_<pkg> target labels to their package keys. " +
                  "Platform-specific members should be gated with select().",
        ),
        "edges": attr.string(
            mandatory = True,
            doc = "JSON-encoded in-cycle edge map with marker ASTs. Format: " +
                  '{"pkg": [{"dep": "...", "marker_ast": {...}}, ...]}',
        ),
    } | marker_value_attrs(),
    doc = "Computes per-member transitive cycle dependencies using PEP 508 markers at analysis time.",
)
