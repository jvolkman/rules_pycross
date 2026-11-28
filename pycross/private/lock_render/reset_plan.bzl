"""Variant-reset planning and `@<ws>__state//:reset.bzl` rendering.

A repo's transition sets pycross's variant settings (`@<ws>__state//:_state` and
the repos' `_variants` flags). A package whose install and whole dependency
closure don't depend on them is installed with those settings reset
(`pycross_reset_wheel_library`), so every repo shares one install. Packages
that may fall back to an sdist build only reset where a wheel matches: the
build's tools can depend on the variant. Packages with post-install patches or
a custom build target, or with variant-gated edges stay in the caller's
configuration, and so does everything that depends on them.

Cycle members' underlying `_raw` wheel libraries exclude intra-SCC edges and
reset independently when their own install and external closure are resettable;
callers outside the cycle reset across the cycle only when every member of the
SCC is resettable and no intra-SCC edge depends on variants.
"""

load(
    "//pycross/private:lock_contract.bzl",
    "is_extras_proxy",
    "spoke_raw_reset_gate_target",
    "spoke_repo_name",
    "spoke_scc_reset_gate_target",
)
load("//pycross/private:util.bzl", "base_package_key", "has_build_fallback", "is_universal_py3_wheel", "parse_package_key")
load("//pycross/private:variant_util.bzl", "fold_variant_marker", "variant_conflict_pairs")

def _is_in_same_cycle(dep_key, pkg, packages):
    cycle_group = pkg.get("cycle_group")
    if not cycle_group:
        return False
    dep_pkg = packages.get(dep_key)
    if not dep_pkg:
        return False
    return dep_pkg.get("cycle_group") == cycle_group

def _resolved_wheel_candidates(pkg, repo_map):
    return [
        c
        for c in pkg.get("wheel_candidates", [])
        if (c.get("file_reference", {}).get("label") or repo_map.get(c.get("file_reference", {}).get("key")))
    ]

def marker_depends_on_variants(marker, conflict_pairs, cache = None, parse_cache = None):
    """Whether a marker's value can depend on the selected variants.

    Clauses that require two items of one conflict set (which uv emits, e.g.
    `extra == 'group-5-app-a-test' and extra == 'group-5-app-b-test'`) can never
    be true, so they don't count.

    Args:
        marker: PEP 508 marker expression string.
        conflict_pairs: `{(token, token): True}` of mutually exclusive variant tokens.
        cache: Optional dict memoizing `{marker: bool}` for this `conflict_pairs`.
        parse_cache: Optional dict memoizing `{marker: parsed_ast}` across folds.

    Returns:
        True if the marker's result can vary with the selected variants.
    """
    if cache != None:
        cached = cache.get(marker)
        if cached != None:
            return cached
    result = fold_variant_marker(marker, conflict_pairs = conflict_pairs, parse_cache = parse_cache) == "V"
    if cache != None:
        cache[marker] = result
    return result

conflict_pairs = variant_conflict_pairs

def compute_workspace_reset_states(packages, repo_map, conflict_pairs, workspace_name, fork_slots):
    """Compute extension-phase tristate variant-reset status per package across spokes.

    Pure condensed-DAG analysis without emitting BUILD targets or threading
    downstream wheel filenames across package boundaries. Each package receives
    two tristates in `("never", "always", "gated")`:
      - `raw_status`: whether this package's own install resets never, always, or gated.
      - `caller_status`: what external callers observe (`== raw_status` outside cycles,
        `== scc_status` for cycle members).

    For gated cycle SCCs, also identifies the deterministic version-free SCC leader
    (sorted by `(spoke_repo, extra, slot)`) and the list of `(spoke, raw_gate_target)`
    entries for all gated members in the SCC.

    Args:
        packages: Merged workspace packages dict (`{pkg_key: pkg_dict}`).
        repo_map: Workspace file key -> repository label dict.
        conflict_pairs: `{(token, token): True}` from `variant_conflict_pairs`.
        workspace_name: Workspace name (used to derive spoke repo names).
        fork_slots: Dict mapping `pkg_key -> slot` from `assign_fork_slots`.

    Returns:
        `struct(raw_status, caller_status, scc_info)` where `raw_status` and
        `caller_status` map `pkg_key -> "never" | "always" | "gated"`, and
        `scc_info` maps `cycle_group -> struct(status, leader_key, leader_spoke,
        leader_gate_target, gated_member_gates)`.
    """
    raw_status = {}
    caller_status = {}
    scc_info = {}
    variant_marker_cache = {}

    cycle_members_by_group = {}
    total_edges = 0
    for pkg_key in sorted(packages.keys()):
        pkg = packages[pkg_key]
        cg = pkg.get("cycle_group")
        if cg:
            cycle_members_by_group.setdefault(cg, []).append(pkg_key)
        total_edges += len(pkg.get("marker_dependencies", []))
        if is_extras_proxy(pkg_key, pkg):
            total_edges += 1

    def compute_single_status(key, ignore_same_cycle = False):
        pkg = packages[key]
        resolved = _resolved_wheel_candidates(pkg, repo_map)
        extras_proxy = is_extras_proxy(key, pkg)
        if pkg.get("post_install_patches") or pkg.get("build_target"):
            return "never"

        base_status = None
        if extras_proxy:
            base_key = base_package_key(key)
            if ignore_same_cycle and _is_in_same_cycle(base_key, pkg, packages):
                base_status = raw_status.get(base_key, "never")
            else:
                base_status = caller_status.get(base_key, "never")
            if base_status == "never":
                return "never"
        elif not resolved:
            return "never"

        deps = [
            md
            for md in pkg.get("marker_dependencies", [])
            if not (ignore_same_cycle and _is_in_same_cycle(md["key"], pkg, packages))
        ]
        for md in deps:
            if md.get("marker") and marker_depends_on_variants(
                md["marker"],
                conflict_pairs,
                cache = variant_marker_cache,
            ):
                return "never"
            dep_st = caller_status.get(md["key"], "never")
            if dep_st == "never" and not md.get("marker"):
                return "never"

        if extras_proxy:
            if base_status == "gated":
                return "gated"
        elif pkg.get("sdist_file") and pkg["sdist_file"].get("key") and has_build_fallback(pkg):
            all_resolved = len(resolved) == len(pkg.get("wheel_candidates", []))
            if not (all_resolved and any([is_universal_py3_wheel(c["filename"]) for c in resolved])):
                return "gated"

        for md in deps:
            dep_st = caller_status.get(md["key"], "never")
            if dep_st != "always":
                return "gated"

        return "always"

    def compute_cycle_status(group_name):
        members = cycle_members_by_group[group_name]
        wheel_members = []
        extras_members = []
        for m in members:
            if is_extras_proxy(m, packages[m]):
                extras_members.append(m)
            else:
                wheel_members.append(m)

        for m in wheel_members + extras_members:
            raw_status[m] = compute_single_status(m, ignore_same_cycle = True)

        scc_st = "always"
        for m in members:
            if raw_status[m] == "never":
                scc_st = "never"
                break
            if raw_status[m] == "gated":
                scc_st = "gated"
            pkg = packages[m]
            for md in pkg.get("marker_dependencies", []):
                if _is_in_same_cycle(md["key"], pkg, packages) and md.get("marker"):
                    if marker_depends_on_variants(
                        md["marker"],
                        conflict_pairs,
                        cache = variant_marker_cache,
                    ):
                        scc_st = "never"
                        break
            if scc_st == "never":
                break

        for m in members:
            caller_status[m] = scc_st

        if scc_st == "gated":
            ordered_members = sorted(
                members,
                key = lambda m: (
                    spoke_repo_name(workspace_name, parse_package_key(m).name),
                    parse_package_key(m).extra,
                    fork_slots.get(m, ""),
                ),
            )
            leader_key = ordered_members[0]
            leader_parts = parse_package_key(leader_key)
            leader_spoke = spoke_repo_name(workspace_name, leader_parts.name)
            leader_gate_target = spoke_scc_reset_gate_target(
                fork_slots.get(leader_key, ""),
                leader_parts.extra,
            )
            gated_member_gates = []
            for m in ordered_members:
                if raw_status[m] != "gated":
                    continue
                mp = parse_package_key(m)
                gated_member_gates.append((
                    spoke_repo_name(workspace_name, mp.name),
                    spoke_raw_reset_gate_target(fork_slots.get(m, ""), mp.extra),
                ))
            scc_info[group_name] = struct(
                status = scc_st,
                leader_key = leader_key,
                leader_spoke = leader_spoke,
                leader_gate_target = leader_gate_target,
                gated_member_gates = gated_member_gates,
            )
        else:
            scc_info[group_name] = struct(
                status = scc_st,
                leader_key = "",
                leader_spoke = "",
                leader_gate_target = "",
                gated_member_gates = [],
            )

    def node_of(key):
        cg = packages[key].get("cycle_group")
        return ("cycle", cg) if cg else ("pkg", key)

    max_dfs_steps = len(packages) + total_edges + 2
    done_nodes = {}
    visiting_nodes = {}
    for root in sorted(packages.keys()):
        root_node = node_of(root)
        if root_node in done_nodes:
            continue
        stack = [(root_node, False)]
        for _ in range(max_dfs_steps):
            if not stack:
                break
            node, expanded = stack.pop()
            if node in done_nodes:
                continue
            kind, ident = node
            if expanded:
                if kind == "cycle":
                    compute_cycle_status(ident)
                else:
                    st = compute_single_status(ident, ignore_same_cycle = False)
                    raw_status[ident] = st
                    caller_status[ident] = st
                done_nodes[node] = True
                continue
            if node in visiting_nodes:
                continue
            visiting_nodes[node] = True
            stack.append((node, True))
            members = cycle_members_by_group[ident] if kind == "cycle" else [ident]
            for m in members:
                pkg = packages[m]
                if is_extras_proxy(m, pkg):
                    base_key = base_package_key(m)
                    if base_key in packages and not (kind == "cycle" and _is_in_same_cycle(base_key, pkg, packages)):
                        dep_node = node_of(base_key)
                        if dep_node not in done_nodes and dep_node not in visiting_nodes:
                            stack.append((dep_node, False))
                for md in pkg.get("marker_dependencies", []):
                    dep_key = md["key"]
                    if dep_key not in packages:
                        continue
                    if kind == "cycle" and _is_in_same_cycle(dep_key, pkg, packages):
                        continue
                    dep_node = node_of(dep_key)
                    if dep_node not in done_nodes and dep_node not in visiting_nodes:
                        stack.append((dep_node, False))
        if stack:
            fail("workspace reset_plan DFS exceeded step bound for root: " + root)

    return struct(
        raw_status = raw_status,
        caller_status = caller_status,
        scc_info = scc_info,
    )

def render_state_reset_bzl(flag_labels, string_flag_labels = None):
    """Renders `@<ws>__state//:reset.bzl` for cross-spoke variant resetting.

    Uses `str(Label(...))` evaluated inside `@<ws>__state` so the transition
    outputs resolve to canonical build-setting labels regardless of which
    spoke repository loads `reset.bzl`.

    Args:
        flag_labels: Every member repo's `_variants` bool_flag labels.
        string_flag_labels: Optional list of member repos' `_variants` string_flag labels.

    Returns:
        The file content string.
    """
    outputs = [('str(Label("//:_state"))', '""')]
    for label in sorted({label: True for label in flag_labels}.keys()):
        outputs.append(("str(Label({}))".format(json.encode(label)), "False"))
    for label in sorted({label: True for label in (string_flag_labels or [])}.keys()):
        outputs.append(("str(Label({}))".format(json.encode(label)), '""'))
    lines = [
        "# This file is generated by rules_pycross.",
        '"""Installs packages with pycross\'s variant settings reset across spokes."""',
        "",
        'load("@rules_pycross//pycross/private:wheel_library.bzl", "make_wheel_library_rule", "pycross_wheel_library")',
        "",
        "_RESET = {",
    ] + ["    {}: {},".format(k, v) for k, v in outputs] + [
        "}",
        "",
        "def _reset_variants_impl(_settings, _attr):",
        "    return _RESET",
        "",
        "_reset_variants = transition(",
        "    implementation = _reset_variants_impl,",
        "    inputs = [],",
        "    outputs = _RESET.keys(),",
        ")",
        "",
        "pycross_reset_wheel_library = make_wheel_library_rule(cfg = _reset_variants)",
        "",
        "def pycross_resettable_wheel_library(name, reset_gate, **kwargs):",
        '    """A wheel library that installs with variant settings reset where `reset_gate` matches."""',
        "    if not reset_gate:",
        "        pycross_reset_wheel_library(name = name, **kwargs)",
        "        return",
        '    pycross_reset_wheel_library(name = "_reset_" + name, **kwargs)',
        '    pycross_wheel_library(name = "_unreset_" + name, **kwargs)',
        "    native.alias(",
        "        name = name,",
        "        actual = select({",
        '            reset_gate: ":_reset_" + name,',
        '            "//conditions:default": ":_unreset_" + name,',
        "        }),",
        "    )",
        "",
    ]
    return "\n".join(lines)
