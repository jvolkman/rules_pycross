"""Cycle dependency reachability evaluator rule.

Determines whether a specific cycle member (`target`) is reachable from
another member (`source`) in the in-cycle dependency graph, given the
current platform's PEP 508 marker values.

Returns config_common.FeatureFlagInfo with value "true" if reachable,
"false" otherwise.

Edge format (JSON):
  {
    "alpha@1.0": [
      {"dep": "beta@2.0"},
      {"dep": "gamma@1.0", "marker_ast": {"op": "==", ...}}
    ],
    ...
  }

Each edge is either unconditional (no marker_ast) or conditional
(marker_ast is evaluated against the current platform).
"""

load("//pycross/private:pep508_evaluator.bzl", "evaluate_marker_expr")
load("//pycross/private:pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "marker_value_attrs")

# ---- BFS reachability -------------------------------------------------------

def _active_neighbors(edges, node, markers):
    """Returns the list of neighbor nodes reachable from `node` given marker values.

    Args:
        edges: Dict mapping node name -> list of edge dicts.
        node: The current node name.
        markers: Dict of PEP 508 marker values for the current platform.

    Returns:
        A list of neighbor node name strings.
    """
    node_edges = edges.get(node, [])
    result = []
    for edge in node_edges:
        marker_ast = edge.get("marker_ast")
        if marker_ast:
            if not evaluate_marker_expr(marker_ast, markers):
                continue
        result.append(edge["dep"])
    return result

def is_reachable(edges, source, target, markers):
    """BFS to determine if `target` is reachable from `source`.

    Args:
        edges: Dict mapping node -> list of {"dep": str, "marker_ast": optional dict}.
        source: Starting node name.
        target: Target node name to search for.
        markers: Dict of PEP 508 marker values for the current platform.

    Returns:
        True if target is reachable from source via active edges, False otherwise.
    """
    if source == target:
        return True

    visited = {source: True}
    queue = [source]

    # Iterative BFS (Starlark forbids recursion).
    # Use an index into the queue list as a dequeue pointer.
    head = 0
    for _ in range(len(edges) + 1):  # bounded by number of nodes in the graph
        if head >= len(queue):
            break
        current = queue[head]
        head += 1
        for neighbor in _active_neighbors(edges, current, markers):
            if neighbor == target:
                return True
            if neighbor not in visited:
                visited[neighbor] = True
                queue.append(neighbor)

    return False

# ---- rule -------------------------------------------------------------------

def _pycross_cycle_dep_needed_impl(ctx):
    edges = json.decode(ctx.attr.edges)
    markers = collect_markers(ctx)
    reachable = is_reachable(edges, ctx.attr.source, ctx.attr.target, markers)
    return [config_common.FeatureFlagInfo(value = "true" if reachable else "false")]

_pycross_cycle_dep_needed = rule(
    implementation = _pycross_cycle_dep_needed_impl,
    attrs = {
        "source": attr.string(
            mandatory = True,
            doc = "The cycle member to start BFS from.",
        ),
        "target": attr.string(
            mandatory = True,
            doc = "The cycle member to check reachability for.",
        ),
        "edges": attr.string(
            mandatory = True,
            doc = "JSON-encoded edge map: {node: [{dep, marker_ast?}, ...]}.",
        ),
    } | marker_value_attrs(),
    provides = [config_common.FeatureFlagInfo],
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
)

def pycross_cycle_dep_needed(name, **kwargs):
    """Public macro wrapping _pycross_cycle_dep_needed.

    Args:
        name: Target name.
        **kwargs: Forwarded to the underlying rule.
    """
    _pycross_cycle_dep_needed(name = name, **kwargs)
