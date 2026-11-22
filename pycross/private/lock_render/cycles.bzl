"""Cycle SCC edge-map rendering and `pycross_cycle_member_marker_deps` emission."""

load("//pycross/private:util.bzl", "base_package_key", "parse_package_key", "sanitize_name")
load(":common.bzl", "ind")
load(":markers.bzl", "format_variants_attr", "matching_variant_resolvers")

def build_cycle_edges_dict(scc, packages):
    """Builds the in-cycle edge map for marker mode.

    Args:
        scc: List of package keys in the strongly connected component.
        packages: Lock packages dict.

    Returns:
        Dict with format `{pkg: [{"dep": dep_key, "marker": "..."}, ...], ...}`.
    """
    scc_set = {k: True for k in scc}
    edges = {}
    for pkg_key in sorted(scc):
        pkg = packages.get(pkg_key, {})
        parts = parse_package_key(pkg_key)
        base_key = base_package_key(pkg_key) if parts.extra else None
        edge_list = []
        has_unconditional_base = False
        for md in pkg.get("marker_dependencies", []):
            dep_key = md["key"]
            if dep_key not in scc_set:
                continue
            entry = {"dep": dep_key}
            if md.get("marker"):
                entry["marker"] = md["marker"]
            elif base_key and dep_key == base_key:
                has_unconditional_base = True
            edge_list.append(entry)
        if not pkg.get("wheel_candidates") and base_key and not has_unconditional_base:
            if base_key in scc_set:
                edge_list.append({"dep": base_key})
        edges[pkg_key] = edge_list
    return edges

def render_edges_dict(edges, base_indent = 1):
    """Renders an edges dict as pretty-printed Starlark dict literal lines.

    Args:
        edges: Dict of {node: [{dep, marker?}, ...], ...}.
        base_indent: Number of indent levels for the outer braces.

    Returns:
        A list of indented lines forming a valid Starlark dict literal.
    """
    lines = [ind("{", base_indent)]
    for pkg_key in sorted(edges.keys()):
        edge_list = edges[pkg_key]
        if not edge_list:
            lines.append(ind("{}: [],".format(json.encode(pkg_key)), base_indent + 1))
        else:
            lines.append(ind("{}: [".format(json.encode(pkg_key)), base_indent + 1))
            for entry in edge_list:
                parts = ['"dep": {}'.format(json.encode(entry["dep"]))]
                if entry.get("marker"):
                    parts.append('"marker": {}'.format(json.encode(entry["marker"])))
                lines.append(ind("{{{}}},".format(", ".join(parts)), base_indent + 2))
            lines.append(ind("],", base_indent + 1))
    lines.append(ind("}", base_indent))
    return lines

def render_marker_cycle_member_deps(lines, cycle_groups, packages, variant_resolvers = None):
    """Renders pycross_cycle_member_marker_deps macro calls for each cycle member.

    Each macro call internally creates N reachability evaluators + config_settings
    and wraps them in a pycross_library_proxy with select() per dep.

    Only cycle group members that appear in ``packages`` are rendered; groups
    whose members are entirely outside the resolved set are silently skipped.

    Args:
        lines: Output lines list.
        cycle_groups: Dict mapping cycle group name -> list of member package keys.
        packages: Lock packages dict.
        variant_resolvers: Optional list/dict of variant_resolver labels.
    """
    for group_name, scc in sorted(cycle_groups.items()):
        # Only render members that are part of the resolved package set.
        resolved_members = [m for m in scc if m in packages]
        if not resolved_members:
            continue

        edges = build_cycle_edges_dict(scc, packages)
        edge_markers = [
            entry.get("marker", "")
            for edge_list in edges.values()
            for entry in edge_list
            if entry.get("marker")
        ]
        resolvers = matching_variant_resolvers(edge_markers, variant_resolvers)

        sanitized_group_name = sanitize_name(group_name).upper()
        edges_var_name = "_{}_EDGES".format(sanitized_group_name)

        edges_lines = render_edges_dict(edges, base_indent = 1)

        # Attach the variable assignment to the first line of the dict literal.
        edges_lines[0] = ind("{} = ".format(edges_var_name)) + edges_lines[0].lstrip()
        lines.extend(edges_lines)
        lines.append("")

        for pkg_key in sorted(resolved_members):
            lines.append(ind("pycross_cycle_member_marker_deps("))
            lines.append(ind("name = {},".format(json.encode(pkg_key)), 2))
            lines.append(ind("raw_name = {},".format(json.encode("_raw_{}".format(pkg_key))), 2))
            lines.append(ind("member = {},".format(json.encode(pkg_key)), 2))
            lines.append(ind("edges = {},".format(edges_var_name), 2))
            if resolvers:
                lines.append(ind(format_variants_attr(resolvers), 2))
            lines.append(ind(")"))
            lines.append("")
