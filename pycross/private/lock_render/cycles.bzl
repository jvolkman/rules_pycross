"""Cycle SCC edge-map building and repo-rule-time target rendering."""

load("//pycross/private:build_text.bzl", "alias", "deps_plus_selects", "flag_setting")
load("//pycross/private:lock_contract.bzl", "is_extras_proxy", "marker_match_target_name", "raw_target_name")
load("//pycross/private:util.bzl", "base_package_key", "marker_evaluator_name", "parse_package_key", "sanitize_name")
load(":common.bzl", "ind")
load(":cycle_plan.bzl", "plan_cycle_member_deps")
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
        if is_extras_proxy(pkg_key, pkg) and not has_unconditional_base:
            if base_key in scc_set:
                edge_list.append({"dep": base_key})
        edges[pkg_key] = edge_list
    return edges

def render_marker_cycle_member_deps(
        lines,
        cycle_groups,
        packages,
        variant_resolvers = None,
        available_eval_matches = None,
        unique_markers = None,
        loads = None):
    """Plans and renders cycle member proxies and fallback reachability evaluators.

    For each cycle SCC, computes unconditional deps and grouped conditional deps
    at repo-rule time via `plan_cycle_member_deps`. Groups gated by a single
    1-hop marker already present in `available_eval_matches` (or `unique_markers`)
    reuse the pre-rendered `_marker_eval_*_match` config_setting. Fallback
    `pycross_cycle_dep_needed` evaluators and `_{GROUP}_EDGES_JSON` are emitted
    only when a group actually needs multi-hop (or unrendered) reachability
    evaluation.

    Only cycle group members that appear in ``packages`` are rendered; groups
    whose members are entirely outside the resolved set are silently skipped.

    Args:
        lines: Output lines list.
        cycle_groups: Dict mapping cycle group name -> list of member package keys.
        packages: Lock packages dict.
        variant_resolvers: Optional list/dict of variant_resolver labels.
        available_eval_matches: Optional dict/set of pre-rendered `<eval_name>_match`
            target names. When `None`, derived from `unique_markers` if provided,
            otherwise `{}`.
        unique_markers: Optional iterable of `(marker_str, extra)` tuples used to
            derive `available_eval_matches` when `available_eval_matches` is `None`.
        loads: Optional dict tracking emitted helper loads (`"cycle_dep_needed"`).
    """
    if available_eval_matches == None:
        if unique_markers:
            available_eval_matches = {
                marker_match_target_name(marker_evaluator_name(m, e)): True
                for m, e in unique_markers
            }
        else:
            available_eval_matches = {}

    emitted_pairs = {}

    for group_name, scc in sorted(cycle_groups.items()):
        # Only render members that are part of the resolved package set.
        resolved_members = sorted([m for m in scc if m in packages])
        if not resolved_members:
            continue

        edges = build_cycle_edges_dict(scc, packages)
        if len(edges) <= 1:
            for pkg_key in resolved_members:
                lines.extend(alias(pkg_key, ":" + raw_target_name(pkg_key), indent = 1, use_native = True))
            continue

        plans = {pkg_key: plan_cycle_member_deps(pkg_key, edges) for pkg_key in resolved_members}

        # Collect deduplicated fallback evaluators needed for this group.
        new_evaluators = []
        for pkg_key in resolved_members:
            for cg in plans[pkg_key].conditional_groups:
                if cg.eval_match_name and cg.eval_match_name in available_eval_matches:
                    continue
                if cg.pair_name not in emitted_pairs:
                    emitted_pairs[cg.pair_name] = True
                    new_evaluators.append((cg.pair_name, cg.source, cg.representative))

        if new_evaluators:
            if loads != None:
                loads["cycle_dep_needed"] = True

            edge_markers = [
                entry.get("marker", "")
                for edge_list in edges.values()
                for entry in edge_list
                if entry.get("marker")
            ]
            resolvers = matching_variant_resolvers(edge_markers, variant_resolvers)

            sanitized_group_name = sanitize_name(group_name).upper()
            edges_var_name = "_{}_EDGES_JSON".format(sanitized_group_name)
            lines.append(ind("{} = {}".format(edges_var_name, json.encode(json.encode(edges)))))
            lines.append("")

            for pair_name, source, representative in new_evaluators:
                lines.extend([
                    ind("pycross_cycle_dep_needed("),
                    ind("name = {},".format(json.encode(pair_name)), 2),
                    ind("source = {},".format(json.encode(source)), 2),
                    ind("target = {},".format(json.encode(representative)), 2),
                    ind("edges = {},".format(edges_var_name), 2),
                ])
                if resolvers:
                    lines.append(ind(format_variants_attr(resolvers), 2))
                lines.extend([
                    ind(")"),
                    "",
                ])
                lines.extend(flag_setting(
                    marker_match_target_name(pair_name),
                    ":" + pair_name,
                    "true",
                    indent = 1,
                    use_native = True,
                ))

        for pkg_key in resolved_members:
            plan = plans[pkg_key]
            unconditional_deps = [":" + raw_target_name(u) for u in plan.unconditional_deps]
            conditional_by_cond = {}
            for cg in plan.conditional_groups:
                if cg.eval_match_name and cg.eval_match_name in available_eval_matches:
                    match_name = cg.eval_match_name
                else:
                    match_name = marker_match_target_name(cg.pair_name)
                cond_deps = conditional_by_cond.setdefault(":" + match_name, {})
                for m in cg.group_members:
                    cond_deps[":" + raw_target_name(m)] = True

            lines.extend([
                ind("pycross_library_proxy("),
                ind("name = {},".format(json.encode(pkg_key)), 2),
                ind("actual = {},".format(json.encode(":" + raw_target_name(pkg_key))), 2),
            ])
            lines.extend(deps_plus_selects(
                "deps",
                unconditional_deps,
                conditional_by_cond,
                indent = 2,
                inline_values = True,
                trailing_comma = True,
            ))
            lines.extend([
                ind(")"),
                "",
            ])
