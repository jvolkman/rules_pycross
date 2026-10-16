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
      {"dep": "gamma@1.0", "marker": "sys_platform == 'linux'"}
    ],
    ...
  }

Each edge is either unconditional (no marker) or conditional
(marker is evaluated against the current platform).
"""

load("//pycross/private:pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "evaluate_marker", "marker_value_attrs")
load("//pycross/private:providers.bzl", "PycrossConflictStateInfo")
load("//pycross/private:util.bzl", "parse_package_key")

# ---- BFS reachability -------------------------------------------------------

def _active_neighbors(edges, node, markers_env, active_tokens = None):
    """Returns the list of neighbor nodes reachable from `node` given marker values.

    Args:
        edges: Dict mapping node name -> list of edge dicts.
        node: The current node name.
        markers_env: Dict of PEP 508 marker values for the current platform.
        active_tokens: Optional dict or list of active uv conflict tokens.

    Returns:
        A list of neighbor node name strings.
    """
    node_edges = edges.get(node, [])
    node_extra = parse_package_key(node).extra
    node_env = None
    result = []
    for edge in node_edges:
        marker_str = edge.get("marker")
        if marker_str:
            if node_env == None:
                if markers_env.get("extra", "") == node_extra:
                    node_env = markers_env
                else:
                    node_env = dict(markers_env)
                    node_env["extra"] = node_extra
            if not evaluate_marker(marker_str, node_env, active_tokens = active_tokens):
                continue
        result.append(edge["dep"])
    return result

def is_reachable(edges, source, target, markers, active_tokens = None):
    """BFS to determine if `target` is reachable from `source`.

    Args:
        edges: Dict mapping node -> list of {"dep": str, "marker": optional str}.
        source: Starting node name.
        target: Target node name to search for.
        markers: Dict of PEP 508 marker values for the current platform.
        active_tokens: Optional dict or list of active uv conflict tokens.

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
        for neighbor in _active_neighbors(edges, current, markers, active_tokens = active_tokens):
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
    active_tokens = None
    if ctx.attr.conflict_state != None:
        active_tokens = ctx.attr.conflict_state[PycrossConflictStateInfo].active_tokens
    reachable = is_reachable(edges, ctx.attr.source, ctx.attr.target, markers, active_tokens = active_tokens)
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
            doc = "JSON-encoded edge map: {node: [{dep, marker?}, ...]}.",
        ),
        "conflict_state": attr.label(
            providers = [PycrossConflictStateInfo],
            doc = "Optional conflict_state target providing active uv conflict tokens.",
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
