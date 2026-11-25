"""Variant-reset planning and `_lock/reset.bzl` rendering.

A repo's transition sets pycross's variant settings (`//_lock:_state` and the
repos' `_variants` flags). A package whose install and
whole dependency closure don't depend on them is installed with those settings
reset (`pycross_reset_wheel_library`), so every repo shares one install.
Packages that may fall back to an sdist build only reset where a wheel
matches: the build's tools can depend on the variant. Packages with
post-install patches or a custom build target, or with variant-gated edges stay
in the caller's configuration, and so does everything that depends on them.
Cycle members' underlying `_raw_*` wheel libraries exclude intra-SCC edges and
reset independently when their own install and external closure are resettable;
callers outside the cycle reset across the cycle only when every member of the
SCC is resettable and no intra-SCC edge depends on variants.
"""

load("//pycross/private:build_text.bzl", "config_setting_group", "flag_setting")
load("//pycross/private:util.bzl", "base_package_key", "fold_variant_marker", "has_build_fallback", "is_universal_py3_wheel", "marker_evaluator_name", "parse_package_key", "sanitize_name", "variant_conflict_pairs")
load(":common.bzl", "is_in_same_cycle")
load(":wheels.bzl", "resolved_wheel_candidates", "wheel_match_condition")

def marker_depends_on_variants(marker, conflict_pairs):
    """Whether a marker's value can depend on the selected variants.

    Clauses that require two items of one conflict set (which uv emits, e.g.
    `extra == 'group-5-app-a-test' and extra == 'group-5-app-b-test'`) can never
    be true, so they don't count.

    Args:
        marker: PEP 508 marker expression string.
        conflict_pairs: `{(token, token): True}` of mutually exclusive variant tokens.

    Returns:
        True if the marker's result can vary with the selected variants.
    """
    return fold_variant_marker(marker, conflict_pairs = conflict_pairs) == "V"

def _is_extras_proxy(key, pkg):
    return not pkg.get("wheel_candidates") and bool(parse_package_key(key).extra)

def compute_reset_plan(packages, repo_map, conflict_pairs, gate_lines, loads = None):
    """Decides which packages install with reset variant settings, and their gates.

    For cycle members, `_raw_<pkg>` excludes intra-SCC edges, so each member's
    wheel install resets independently whenever its own install and external
    dependency closure are resettable (`raw_plan`, returned for `package.bzl`).
    Upstream callers outside the cycle (`plan`) reset across the cycle only when
    every member of the SCC is resettable and no intra-SCC edge depends on
    variants.

    Args:
        packages: The lock's packages.
        repo_map: File key -> label.
        conflict_pairs: {(token, token): True} (see `variant_conflict_pairs`).
        gate_lines: Output lines for the gate config_setting(_group)s.
        loads: Optional dict tracking emitted helper loads (`"selects"`, `"wheel_matched"`).

    Returns:
        `{pkg_key: struct(ok, gate)}` describing whether each package's wheel
        library (`_raw_<pkg_key>` for cycle members, `<pkg_key>` otherwise)
        resets. `gate` is a label that must match for the reset to apply
        (`None` means always). Caller-facing SCC eligibility is tracked
        internally.
    """
    no = struct(ok = False, gate = None)
    plan = {}  # pkg_key -> caller-facing struct(ok, gate)
    raw_plan = {}  # pkg_key -> target-facing struct(ok, gate)
    nomatch = {}  # marker evaluator names that need an `_nomatch` config_setting
    edge_gates = {}  # (eval_name, dep_key) -> label, shared across packages

    cycle_members_by_group = {}  # group_name -> sorted list of member pkg_keys
    total_edges = 0
    for pkg_key in sorted(packages.keys()):
        pkg = packages[pkg_key]
        cg = pkg.get("cycle_group")
        if cg:
            cycle_members_by_group.setdefault(cg, []).append(pkg_key)
        total_edges += len(pkg.get("marker_dependencies", []))
        if _is_extras_proxy(pkg_key, pkg):
            total_edges += 1

    def group(name, kind, labels):
        gate_lines.extend(config_setting_group(name, kind, labels, indent = 1))
        if loads != None:
            loads["selects"] = True
        return ":" + name

    def compute_single(key, ignore_same_cycle = False):
        pkg = packages[key]
        parts = parse_package_key(key)
        resolved = resolved_wheel_candidates(pkg, repo_map)
        is_extras_proxy = _is_extras_proxy(key, pkg)
        if pkg.get("post_install_patches") or pkg.get("build_target"):
            return no
        base = None
        if is_extras_proxy:
            base_key = base_package_key(key)
            if ignore_same_cycle and is_in_same_cycle(base_key, pkg, packages):
                base = raw_plan.get(base_key)
            else:
                base = plan.get(base_key)
            if not base or not base.ok:
                return no
        elif not resolved:
            return no

        deps = [
            md
            for md in pkg.get("marker_dependencies", [])
            if not (ignore_same_cycle and is_in_same_cycle(md["key"], pkg, packages))
        ]
        for md in deps:
            if md.get("marker") and marker_depends_on_variants(md["marker"], conflict_pairs):
                return no
            dep = plan.get(md["key"])
            if not dep or not dep.ok:
                if not md.get("marker"):
                    return no

        items = []
        if is_extras_proxy:
            if base.gate:
                items.append(base.gate)
        elif pkg.get("sdist_file") and pkg["sdist_file"].get("key") and has_build_fallback(pkg):
            all_resolved = len(resolved) == len(pkg.get("wheel_candidates", []))
            if not (all_resolved and any([is_universal_py3_wheel(c["filename"]) for c in resolved])):
                items.append(wheel_match_condition(
                    gate_lines,
                    key,
                    [c["filename"] for c in resolved],
                    all_resolved,
                    "_reset_wheel_" + key,
                    require_target = False,
                    loads = loads,
                ))

        for md in deps:
            dep = plan.get(md["key"])
            if not dep or not dep.ok:
                # Conditional non-variant edge to a non-resettable dep: safe to
                # reset whenever the marker does not match.
                eval_name = marker_evaluator_name(md["marker"], parts.extra)
                nomatch[eval_name] = True
                items.append(":{}_nomatch".format(eval_name))
                continue
            if not dep.gate:
                continue
            if not md.get("marker"):
                items.append(dep.gate)
                continue

            # A conditional edge only needs the dep's gate where the edge applies.
            eval_name = marker_evaluator_name(md["marker"], parts.extra)
            nomatch[eval_name] = True
            edge_key = (eval_name, md["key"])
            if edge_key not in edge_gates:
                edge_gates[edge_key] = group(
                    "_reset_edge_{}_{}".format(eval_name, md["key"]),
                    "match_any",
                    [":{}_nomatch".format(eval_name), dep.gate],
                )
            items.append(edge_gates[edge_key])

        items = {i: True for i in items}.keys()
        if not items:
            return struct(ok = True, gate = None)
        if len(items) == 1:
            return struct(ok = True, gate = items[0])
        return struct(ok = True, gate = group("_reset_ok_" + key, "match_all", items))

    def compute_cycle(group_name):
        members = cycle_members_by_group[group_name]

        # Compute base/wheel members before extras-only proxies so a same-cycle
        # extras proxy sees its base member's raw_plan result.
        wheel_members = []
        extras_members = []
        for m in members:
            if _is_extras_proxy(m, packages[m]):
                extras_members.append(m)
            else:
                wheel_members.append(m)

        for m in wheel_members + extras_members:
            raw_plan[m] = compute_single(m, ignore_same_cycle = True)

        # Callers outside the cycle can reset across it only when no intra-SCC
        # edge depends on variants and every member in the SCC is resettable.
        scc_ok = True
        scc_gates = []
        for m in members:
            m_raw = raw_plan[m]
            if not m_raw.ok:
                scc_ok = False
                break
            if m_raw.gate:
                scc_gates.append(m_raw.gate)
            pkg = packages[m]
            for md in pkg.get("marker_dependencies", []):
                if is_in_same_cycle(md["key"], pkg, packages) and md.get("marker"):
                    if marker_depends_on_variants(md["marker"], conflict_pairs):
                        scc_ok = False
                        break
            if not scc_ok:
                break

        if not scc_ok:
            scc_result = no
        else:
            scc_gates = sorted({g: True for g in scc_gates}.keys())
            if not scc_gates:
                scc_result = struct(ok = True, gate = None)
            elif len(scc_gates) == 1:
                scc_result = struct(ok = True, gate = scc_gates[0])
            else:
                scc_result = struct(
                    ok = True,
                    gate = group("_reset_cycle_" + sanitize_name(group_name), "match_all", scc_gates),
                )

        for m in members:
            plan[m] = scc_result

    def node_of(key):
        cg = packages[key].get("cycle_group")
        return ("cycle", cg) if cg else ("pkg", key)

    # Each condensed node is expanded at most once (pushing one post-order
    # frame) and each outgoing edge pushes at most one frame, plus the initial
    # root push and final empty-stack check.
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
                    compute_cycle(ident)
                else:
                    res = compute_single(ident, ignore_same_cycle = False)
                    plan[ident] = res
                    raw_plan[ident] = res
                done_nodes[node] = True
                continue
            if node in visiting_nodes:
                continue
            visiting_nodes[node] = True
            stack.append((node, True))
            members = cycle_members_by_group[ident] if kind == "cycle" else [ident]
            for m in members:
                pkg = packages[m]
                if _is_extras_proxy(m, pkg):
                    base_key = base_package_key(m)
                    if base_key in packages and not (kind == "cycle" and is_in_same_cycle(base_key, pkg, packages)):
                        dep_node = node_of(base_key)
                        if dep_node not in done_nodes and dep_node not in visiting_nodes:
                            stack.append((dep_node, False))
                for md in pkg.get("marker_dependencies", []):
                    dep_key = md["key"]
                    if dep_key not in packages:
                        continue
                    if kind == "cycle" and is_in_same_cycle(dep_key, pkg, packages):
                        continue
                    dep_node = node_of(dep_key)
                    if dep_node not in done_nodes and dep_node not in visiting_nodes:
                        stack.append((dep_node, False))
        if stack:
            fail("reset_plan DFS exceeded step bound for root: " + root)

    for eval_name in sorted(nomatch):
        gate_lines.extend(flag_setting("{}_nomatch".format(eval_name), ":" + eval_name, "false", indent = 1, use_native = True))
    return raw_plan

conflict_pairs = variant_conflict_pairs

def render_reset_bzl(flag_labels, string_flag_labels = None):
    """Renders `_lock/reset.bzl`: the variant-reset transition and rule.

    Args:
        flag_labels: Every member repo's `_variants` bool_flag labels.
        string_flag_labels: Optional list of member repos' `_variants` string_flag labels.

    Returns:
        The file content.
    """
    outputs = [(json.encode("//_lock:_state"), '""')]
    for label in sorted({label: True for label in flag_labels}.keys()):
        outputs.append((json.encode(label), "False"))
    for label in sorted({label: True for label in (string_flag_labels or [])}.keys()):
        outputs.append((json.encode(label), '""'))
    lines = [
        "# This file is generated by rules_pycross.",
        '"""Installs packages with pycross\'s variant settings reset (see resolved_lock_renderer.bzl)."""',
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
