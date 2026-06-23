"""Rule for per-member cycle dependency resolution.

At analysis time, this rule computes the transitive in-cycle dependencies
for a specific cycle member on the current platform, and forwards only the
necessary providers from those dependencies. This gives exact precision for
environment-gated cycle edges without introducing Bazel-level cycles.
"""

load(":util.bzl", "merge_py_providers")

def _pycross_cycle_member_deps_impl(ctx):
    env = ctx.attr.env
    member = ctx.attr.member
    edges = json.decode(ctx.attr.edges)

    # Build active adjacency for this environment.
    # edges format: {"pkg": {"common": ["dep", ...], "env_name": ["dep", ...]}}
    active_adj = {}
    for src, edge_map in edges.items():
        neighbors = list(edge_map.get("common", []))
        neighbors.extend(edge_map.get(env, []))
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

pycross_cycle_member_deps = rule(
    implementation = _pycross_cycle_member_deps_impl,
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
            doc = "JSON-encoded in-cycle edge map. Format: " +
                  '{\"pkg\": {\"common\": [\"dep\", ...], \"env_name\": [\"dep\", ...]}}',
        ),
        "env": attr.string(
            mandatory = True,
            doc = "The resolved environment name (passed via select).",
        ),
    },
    doc = "Computes per-member, per-environment transitive cycle dependencies at analysis time.",
)
