"""Per-package spoke repository rule (`@<ws>__pkg_<underscore_name>`).

Each spoke owns all locked versions, `~<8hex>` source forks, and `[extra]` keys
of one canonical Python package, exposing version-free target names via
deterministic fork slots (`""`, `"s0"`, `"s1"`, ...):
- `:pkg[_<slot>]` / `:[<extra>][_<slot>]` — public library / proxy target
- `:_raw[_<slot>]` / `:_raw_[<extra>][_<slot>]` — underlying wheel library (or alias when not in a cycle)
- `:wheel[_<slot>]` — `pycross_wheel_dir` wrapping wheel selection
- `:sdist[_<slot>]` — sdist archive alias (when present)
- `:dist_info[_<slot>]` — `pycross_dist_info` target
- `:_wheel_available[_<slot>]` — wheel-only platform availability `config_setting`
- `:_reset_gate[_<slot>]` / `:_raw_reset_gate[_<slot>]` / `:_scc_reset_gate[_<slot>]` — variant-reset gates
- `:_sdist_deps[_<slot>]` — sdist runtime deps proxy
- Optional `<subdir>/BUILD.bazel` + `_sdist/BUILD.bazel` shim when a spoke-scoped
  `PACKAGE_REPO_HOOK` matches this package.
"""

load("@pycross_backends//:package_repo_dispatch.bzl", "PACKAGE_REPO_HOOKS")
load("@pypackaging.bzl", "pypackaging")
load("//pycross/private/lock_render:cycle_plan.bzl", "plan_cycle_member_deps")
load(":build_text.bzl", "alias", "config_setting_group", "deps_plus_selects", "flag_setting", "select_expr")
load(
    ":lock_contract.bzl",
    "cycle_node_key",
    "is_extras_proxy",
    "marker_match_target_name",
    "spoke_dist_info_target",
    "spoke_hook_target",
    "spoke_pkg_target",
    "spoke_raw_reset_gate_target",
    "spoke_raw_target",
    "spoke_repo_name",
    "spoke_reset_gate_target",
    "spoke_sdist_deps_target",
    "spoke_sdist_target",
    "spoke_target_label",
    "spoke_wheel_available_target",
    "spoke_wheel_sel_target",
    "spoke_wheel_target",
    "state_reset_bzl_label",
    "state_variant_state_label",
    "whldir_name",
)
load(":state_repo.bzl", "is_spoke_hook_backend", "run_package_repo_hooks")
load(
    ":util.bzl",
    "base_package_key",
    "has_build_fallback",
    "hex_hash8",
    "is_universal_py3_wheel",
    "marker_evaluator_name",
    "marker_uses_extra",
    "parse_package_key",
    "sanitize_name",
)

def _entry_key_sfx(slot, extra):
    parts = []
    if extra:
        parts.append("e_" + sanitize_name(extra))
    if slot:
        parts.append(slot)
    return ("_" + "_".join(parts)) if parts else ""

def _spoke_wheel_cs_name(slot, extra, filename):
    return "_wheel_cs{}_{}".format(_entry_key_sfx(slot, extra), sanitize_name(filename))

def _render_str_list_attr(lines, attr_name, values):
    if values:
        lines.append("    {} = [".format(attr_name))
        for val in values:
            lines.append("        {},".format(json.encode(val)))
        lines.append("    ],")

def _render_wheel_match_condition(lines, slot, extra, resolved_filenames, all_resolved, target_name, require_target, loads):
    cs_labels = [":" + _spoke_wheel_cs_name(slot, extra, fn) for fn in resolved_filenames]
    if len(cs_labels) == 1:
        if require_target:
            lines.extend(alias(target_name, cs_labels[0]))
            return ":" + target_name
        return cs_labels[0]

    key_sfx = _entry_key_sfx(slot, extra)
    if len(cs_labels) >= 3 and all_resolved:
        matched_name = "_wheel_matched" + key_sfx
        emitted = loads.setdefault("emitted_wheel_matched", {})
        if matched_name in emitted:
            fail("internal: duplicate {} target emitted in spoke".format(matched_name))
        emitted[matched_name] = True
        loads["wheel_matched"] = True
        lines.extend([
            "pycross_wheel_matched(",
            "    name = {},".format(json.encode(matched_name)),
            "    chooser = {},".format(json.encode(":_wheel_chooser" + key_sfx)),
            ")",
            "",
        ])
        lines.extend(flag_setting(target_name, ":" + matched_name, "true"))
        return ":" + target_name

    lines.extend(config_setting_group(target_name, "match_any", cs_labels))
    loads["selects"] = True
    return ":" + target_name

def build_spoke_payloads(
        workspace_name,
        state_repo,
        merged_packages,
        merged_repo_map,
        sdist_repo_map,
        fork_slots,
        cycle_groups = None,
        has_variants = False,
        reset_states = None):
    """Partition a merged workspace lock into version-free, isolated per-spoke payloads.

    Every cross-package reference (deps, cycle SCC edges, cycle reset gates) is
    encoded using version-free `(spoke_repo, target)` identifiers so bumping an
    unrelated package version leaves this spoke's payload byte-identical.

    Args:
        workspace_name: Workspace name.
        state_repo: Apparent name of the workspace's `@<ws>__state` repo.
        merged_packages: Merged workspace packages dict (`{pkg_key: pkg_dict}`).
        merged_repo_map: Workspace file key -> repository label dict.
        sdist_repo_map: Dict mapping `pkg_key` -> `@<ws>__sdist_<pkg>[_<slot>]//:wheel`.
        fork_slots: Dict mapping `pkg_key -> slot` from `assign_fork_slots`.
        cycle_groups: Optional dict mapping `group_name -> [pkg_key, ...]`.
        has_variants: Whether the workspace defines variant sets in `@<ws>__state`.
        reset_states: Optional struct from `compute_workspace_reset_states`.

    Returns:
        Dict mapping `canonical_pkg_name -> struct(spoke_repo, payload)` sorted by
        canonical package name.
    """
    cycle_groups = cycle_groups or {}
    sdist_repo_map = sdist_repo_map or {}

    # Precompute version-free cycle edge maps and node -> (spoke, raw_target) tables once per SCC.
    scc_payloads = {}  # group_name -> {"edges": {...}, "node_targets": {...}}
    for group_name, scc in sorted(cycle_groups.items()):
        resolved_members = sorted([m for m in scc if m in merged_packages])
        if len(resolved_members) <= 1:
            continue
        scc_set = {m: True for m in resolved_members}
        edges = {}
        node_targets = {}
        for m in resolved_members:
            mp = parse_package_key(m)
            m_slot = fork_slots.get(m, "")
            m_node = cycle_node_key(m, m_slot)
            node_targets[m_node] = [
                spoke_repo_name(workspace_name, mp.name),
                spoke_raw_target(m_slot, mp.extra),
            ]
            pkg = merged_packages[m]
            bkey = base_package_key(m) if mp.extra else None
            edge_list = []
            has_unconditional_base = False
            for md in pkg.get("marker_dependencies", []):
                dep_key = md["key"]
                if dep_key not in scc_set:
                    continue
                dep_node = cycle_node_key(dep_key, fork_slots.get(dep_key, ""))
                entry = {"dep": dep_node}
                if md.get("marker"):
                    entry["marker"] = md["marker"]
                elif bkey and dep_key == bkey:
                    has_unconditional_base = True
                edge_list.append(entry)
            if is_extras_proxy(m, pkg) and not has_unconditional_base and bkey in scc_set:
                edge_list.append({"dep": cycle_node_key(bkey, fork_slots.get(bkey, ""))})
            edges[m_node] = edge_list
        scc_payloads[group_name] = {
            "edges": edges,
            "node_targets": node_targets,
        }

    # Group all keys in merged_packages by canonical package name.
    keys_by_name = {}
    for pkg_key in sorted(merged_packages.keys()):
        parts = parse_package_key(pkg_key)
        canon_name = pypackaging.utils.canonicalize_name(parts.name)
        keys_by_name.setdefault(canon_name, []).append(pkg_key)

    spokes = {}
    for canon_name in sorted(keys_by_name.keys()):
        spoke_repo = spoke_repo_name(workspace_name, canon_name)
        entries = []

        # Order entries deterministically by version-free (slot, extra) so
        # routine version bumps never reorder entries in the spoke payload.
        ordered_keys = sorted(
            keys_by_name[canon_name],
            key = lambda k: (fork_slots.get(k, ""), parse_package_key(k).extra, k),
        )
        for pkg_key in ordered_keys:
            pkg = merged_packages[pkg_key]
            parts = parse_package_key(pkg_key)
            slot = fork_slots.get(pkg_key, "")
            extras_proxy = is_extras_proxy(pkg_key, pkg)
            cg = pkg.get("cycle_group")
            in_cycle = bool(cg and cg in scc_payloads)

            # Resolve wheel candidates for this package.
            wheel_candidates = []
            all_wheels_resolved = True
            for cand in pkg.get("wheel_candidates", []):
                file_ref = cand.get("file_reference", {})
                target = file_ref.get("label") or merged_repo_map.get(file_ref.get("key"))
                if target:
                    wheel_candidates.append({
                        "filename": cand["filename"],
                        "target": target,
                    })
                else:
                    all_wheels_resolved = False
                    wheel_candidates.append({
                        "filename": cand["filename"],
                    })

            sdist_file = pkg.get("sdist_file")
            sdist_label = None
            if sdist_file:
                sdist_label = sdist_file.get("label") or merged_repo_map.get(sdist_file.get("key"))
            sdist_build_target = None
            has_sdist_repo = False
            if not extras_proxy:
                if pkg.get("build_target"):
                    sdist_build_target = pkg["build_target"]
                elif sdist_file and sdist_file.get("key") and has_build_fallback(pkg):
                    sdist_build_target = sdist_repo_map.get(pkg_key)
                    has_sdist_repo = bool(sdist_build_target)

            # Encode direct outgoing deps using version-free spoke + target references.
            deps = []
            for md in pkg.get("marker_dependencies", []):
                dep_key = md["key"]
                dp = parse_package_key(dep_key)
                dep_slot = fork_slots.get(dep_key, "")
                dep_pkg = merged_packages.get(dep_key, {})
                same_cycle = bool(cg and dep_pkg.get("cycle_group") == cg)
                dep_entry = {
                    "spoke": spoke_repo_name(workspace_name, dp.name),
                    "target": spoke_pkg_target(dep_slot, dp.extra),
                }
                if md.get("marker"):
                    dep_entry["marker"] = md["marker"]
                if same_cycle:
                    dep_entry["in_same_cycle"] = True
                if reset_states != None:
                    dep_caller_st = reset_states.caller_status.get(dep_key, "never")
                    if dep_caller_st != "always":
                        dep_entry["reset_status"] = dep_caller_st
                        if dep_caller_st == "gated":
                            dep_entry["reset_gate_target"] = spoke_reset_gate_target(dep_slot, dp.extra)
                deps.append(dep_entry)

            entry = {
                "pkg_key": pkg_key,
                "name": parts.name,
                "version": parts.version,
                "extra": parts.extra,
                "slot": slot,
            }
            if extras_proxy:
                entry["is_extras_proxy"] = True
                bkey = base_package_key(pkg_key)
                base_pkg = merged_packages.get(bkey, {})
                base_same_cycle = bool(cg and base_pkg.get("cycle_group") == cg)
                if base_same_cycle:
                    entry["base_in_same_cycle"] = True
                if reset_states != None:
                    base_st = (
                        reset_states.raw_status.get(bkey, "never") if (in_cycle and base_same_cycle) else reset_states.caller_status.get(bkey, "never")
                    )
                    if base_st != "always":
                        entry["base_reset_status"] = base_st
            if in_cycle:
                entry["in_cycle"] = True
                entry["cycle"] = {
                    "node": cycle_node_key(pkg_key, slot),
                    "edges": scc_payloads[cg]["edges"],
                    "node_targets": scc_payloads[cg]["node_targets"],
                }
            if wheel_candidates:
                entry["wheel_candidates"] = wheel_candidates
                if not all_wheels_resolved:
                    entry["partial_wheels"] = True
            if sdist_label:
                entry["sdist_label"] = sdist_label
            if sdist_build_target:
                entry["sdist_build_target"] = sdist_build_target
            if has_sdist_repo:
                entry["has_sdist_repo"] = True
            if deps:
                entry["deps"] = deps

            if reset_states != None:
                raw_st = reset_states.raw_status.get(pkg_key, "never")
                caller_st = reset_states.caller_status.get(pkg_key, "never")
                if raw_st != "never" or caller_st != "never":
                    reset_entry = {
                        "raw_status": raw_st,
                        "caller_status": caller_st,
                    }
                    if in_cycle and caller_st == "gated":
                        info = reset_states.scc_info[cg]
                        reset_entry["scc_leader_spoke"] = info.leader_spoke
                        reset_entry["scc_leader_gate_target"] = info.leader_gate_target
                        if info.leader_key == pkg_key:
                            reset_entry["is_scc_leader"] = True
                            reset_entry["scc_gated_member_gates"] = [
                                [ms, mt]
                                for ms, mt in info.gated_member_gates
                            ]
                    entry["reset"] = reset_entry

            for field in (
                "site_paths",
                "bin_paths",
                "data_paths",
                "include_paths",
                "install_exclude_globs",
                "post_install_patches",
                "wheel_library_tags",
                "precompile",
            ):
                val = pkg.get(field)
                if val:
                    entry[field] = val

            entries.append(entry)

        payload = {
            "name": canon_name,
            "spoke_repo": spoke_repo,
            "state_repo": state_repo,
            "entries": entries,
        }
        if has_variants:
            payload["has_variants"] = True
        spokes[canon_name] = struct(
            spoke_repo = spoke_repo,
            payload = payload,
        )

    return spokes

def render_spoke_build(payload):
    """Render the root `BUILD.bazel` content for a single package spoke repository.

    Args:
        payload: Decoded per-spoke payload dict produced by `build_spoke_payloads`.

    Returns:
        Generated `BUILD.bazel` file content string.
    """
    spoke_repo = payload["spoke_repo"]
    state_repo = payload["state_repo"]
    has_variants = payload.get("has_variants", False)
    entries = payload.get("entries", [])
    variant_state_lbl = state_variant_state_label(state_repo) if has_variants else ""

    pycross_loads = {}
    loads = {}
    marker_extra_cache = {}
    nomatch_evals = {}  # eval_name -> True
    body_lines = []

    # Pre-plan all cycle members in this spoke so we collect 1-hop cycle markers
    # into the spoke's local marker evaluators alongside direct dependency markers.
    cycle_plans = {}  # idx -> plan_cycle_member_deps result
    unique_markers = {}  # (marker_str, effective_extra) -> True

    for idx, entry in enumerate(entries):
        extra = entry.get("extra", "")
        for dep in entry.get("deps", []):
            marker = dep.get("marker")
            if not marker:
                continue
            eff_extra = extra if (extra and marker_uses_extra(marker, cache = marker_extra_cache)) else ""
            unique_markers[(marker, eff_extra)] = True

        cycle = entry.get("cycle")
        if cycle:
            plan = plan_cycle_member_deps(
                cycle["node"],
                cycle["edges"],
                marker_extra_cache = marker_extra_cache,
            )
            cycle_plans[idx] = plan
            for cg in plan.conditional_groups:
                if cg.single_marker:
                    unique_markers[(cg.single_marker, cg.single_extra)] = True

    # 1. Local PEP 508 marker evaluators (deduped across all versions/extras in this spoke).
    if unique_markers:
        pycross_loads.setdefault("pep508_evaluator.bzl", {})["pycross_pep508_evaluator"] = True
        for marker_str, extra in sorted(unique_markers.keys()):
            eval_name = marker_evaluator_name(marker_str, extra, extra_cache = marker_extra_cache)
            body_lines.extend([
                "pycross_pep508_evaluator(",
                "    name = {},".format(json.encode(eval_name)),
                "    expr = {},".format(json.encode(marker_str)),
            ])
            if extra:
                body_lines.append("    extra = {},".format(json.encode(extra)))
            if has_variants and "__variant_" in marker_str:
                body_lines.append("    variants = [{}],".format(json.encode(variant_state_lbl)))
            body_lines.extend([")", ""])
            body_lines.extend(flag_setting(marker_match_target_name(eval_name), ":" + eval_name, "true"))

    available_eval_matches = {
        marker_match_target_name(marker_evaluator_name(m, e, extra_cache = marker_extra_cache)): True
        for m, e in unique_markers.keys()
    }

    # Track emitted multi-hop cycle evaluators and _EDGES_JSON variables within this spoke.
    emitted_cycle_edges = {}  # edges_json -> var_name
    emitted_cycle_pairs = {}  # pair_name -> True
    emitted_edge_gates = {}  # (eval_name, dep_gate_label) -> gate_label

    def _emit_reset_gate_for_entry(entry, resolved_filenames, all_resolved):
        reset = entry.get("reset")
        if not reset:
            return None
        raw_st = reset.get("raw_status", "never")
        caller_st = reset.get("caller_status", "never")
        slot = entry.get("slot", "")
        extra = entry.get("extra", "")
        in_cycle = entry.get("in_cycle", False)
        extras_proxy = entry.get("is_extras_proxy", False)
        key_sfx = _entry_key_sfx(slot, extra)

        raw_gate_label = None
        if raw_st == "gated":
            items = []
            if extras_proxy:
                if entry.get("base_reset_status") == "gated":
                    base_target = (
                        spoke_raw_reset_gate_target(slot) if (in_cycle and entry.get("base_in_same_cycle")) else spoke_reset_gate_target(slot)
                    )
                    items.append(":" + base_target)
            elif entry.get("has_sdist_repo"):
                if not (all_resolved and any([is_universal_py3_wheel(fn) for fn in resolved_filenames])):
                    items.append(_render_wheel_match_condition(
                        body_lines,
                        slot,
                        extra,
                        resolved_filenames,
                        all_resolved,
                        "_reset_wheel" + key_sfx,
                        require_target = False,
                        loads = loads,
                    ))

            for dep in entry.get("deps", []):
                if in_cycle and dep.get("in_same_cycle"):
                    continue
                dep_st = dep.get("reset_status", "always")
                if dep_st == "always":
                    continue
                marker = dep.get("marker", "")
                if dep_st == "never":
                    eval_name = marker_evaluator_name(marker, extra, extra_cache = marker_extra_cache)
                    nomatch_evals[eval_name] = True
                    items.append(":{}_nomatch".format(eval_name))
                    continue

                dep_gate_lbl = spoke_target_label(dep["spoke"], dep["reset_gate_target"], current_spoke = spoke_repo)
                if not marker:
                    items.append(dep_gate_lbl)
                    continue

                eval_name = marker_evaluator_name(marker, extra, extra_cache = marker_extra_cache)
                nomatch_evals[eval_name] = True
                nomatch_label = ":{}_nomatch".format(eval_name)
                if dep_gate_lbl == nomatch_label:
                    items.append(nomatch_label)
                    continue
                edge_key = (eval_name, dep_gate_lbl)
                if edge_key not in emitted_edge_gates:
                    gate_name = "_reset_edge_{}_{}".format(eval_name, hex_hash8(dep_gate_lbl))
                    body_lines.extend(config_setting_group(gate_name, "match_any", [nomatch_label, dep_gate_lbl]))
                    loads["selects"] = True
                    emitted_edge_gates[edge_key] = ":" + gate_name
                items.append(emitted_edge_gates[edge_key])

            items = sorted({i: True for i in items}.keys())
            gate_target = spoke_raw_reset_gate_target(slot, extra) if in_cycle else spoke_reset_gate_target(slot, extra)
            if len(items) == 1:
                body_lines.extend(alias(gate_target, items[0]))
            else:
                body_lines.extend(config_setting_group(gate_target, "match_all", items))
                loads["selects"] = True
            raw_gate_label = ":" + gate_target

        # For gated cycle SCCs: emit _scc_reset_gate on the leader and alias _reset_gate on every member.
        if in_cycle and caller_st == "gated":
            leader_spoke = reset["scc_leader_spoke"]
            leader_gate_target = reset["scc_leader_gate_target"]
            if reset.get("is_scc_leader"):
                member_gates = [
                    spoke_target_label(ms, mt, current_spoke = spoke_repo)
                    for ms, mt in reset.get("scc_gated_member_gates", [])
                ]
                if len(member_gates) == 1:
                    body_lines.extend(alias(leader_gate_target, member_gates[0]))
                else:
                    body_lines.extend(config_setting_group(leader_gate_target, "match_all", member_gates))
                    loads["selects"] = True
            body_lines.extend(alias(
                spoke_reset_gate_target(slot, extra),
                spoke_target_label(leader_spoke, leader_gate_target, current_spoke = spoke_repo),
            ))

        return raw_gate_label

    # 2. Emit each package entry in this spoke.
    for idx, entry in enumerate(entries):
        pkg_key = entry["pkg_key"]
        slot = entry.get("slot", "")
        extra = entry.get("extra", "")
        in_cycle = entry.get("in_cycle", False)
        extras_proxy = entry.get("is_extras_proxy", False)
        key_sfx = _entry_key_sfx(slot, extra)
        deps_var = "_deps" + key_sfx
        has_deps = bool(entry.get("deps"))

        # 2a. Runtime deps variable
        if has_deps:
            unconditional = {}
            dep_evals = {}
            for dep in entry["deps"]:
                if in_cycle and dep.get("in_same_cycle"):
                    continue
                dep_lbl = spoke_target_label(dep["spoke"], dep["target"], current_spoke = spoke_repo)
                marker = dep.get("marker")
                if not marker:
                    unconditional[dep_lbl] = True
                else:
                    eval_name = marker_evaluator_name(marker, extra, extra_cache = marker_extra_cache)
                    dep_evals.setdefault(dep_lbl, {})[eval_name] = True

            by_condition = {}
            multi_groups = {}
            for dep_lbl in sorted(dep_evals.keys()):
                if dep_lbl in unconditional:
                    continue
                evals = sorted(dep_evals[dep_lbl].keys())
                if len(evals) == 1:
                    cond = ":" + marker_match_target_name(evals[0])
                else:
                    evals_key = tuple(evals)
                    if evals_key not in multi_groups:
                        group_name = "_dep_any{}_{}".format(key_sfx, hex_hash8("|".join(evals)))
                        multi_groups[evals_key] = group_name
                        body_lines.extend(config_setting_group(
                            group_name,
                            "match_any",
                            [":" + marker_match_target_name(ev) for ev in evals],
                        ))
                        loads["selects"] = True
                    cond = ":" + multi_groups[evals_key]
                by_condition.setdefault(cond, {})[dep_lbl] = True

            body_lines.extend(deps_plus_selects(
                deps_var,
                sorted(unconditional.keys()),
                by_condition,
                indent = 0,
                inline_values = True,
                trailing_comma = False,
            ))
            body_lines.append("")

        # 2b. Extras-only proxy
        if extras_proxy:
            _emit_reset_gate_for_entry(entry, [], True)
            base_actual = spoke_raw_target(slot) if entry.get("base_in_same_cycle") else spoke_pkg_target(slot)
            proxy_name = spoke_raw_target(slot, extra) if in_cycle else spoke_pkg_target(slot, extra)
            pycross_loads.setdefault("proxy.bzl", {})["pycross_library_proxy"] = True
            body_lines.extend([
                "pycross_library_proxy(",
                "    name = {},".format(json.encode(proxy_name)),
                "    actual = {},".format(json.encode(":" + base_actual)),
                "    deps = {},".format(deps_var) if has_deps else "    deps = [],",
                ")",
                "",
            ])
            if not in_cycle:
                body_lines.extend(alias(spoke_raw_target(slot, extra), ":" + proxy_name))
            continue

        # 2c. Sdist archive alias
        sdist_label = entry.get("sdist_label")
        if sdist_label:
            body_lines.extend(alias(spoke_sdist_target(slot, extra), sdist_label))

        # 2d. Wheel selector & availability
        wheel_sel_name = spoke_wheel_sel_target(slot, extra)
        sdist_target = entry.get("sdist_build_target")
        candidates = entry.get("wheel_candidates", [])
        resolved_candidates = [c for c in candidates if c.get("target")]
        resolved_filenames = [c["filename"] for c in resolved_candidates]
        all_resolved = not entry.get("partial_wheels", False) and len(resolved_candidates) == len(candidates)

        if candidates:
            if (
                len(candidates) == 1 and
                len(resolved_candidates) == 1 and
                is_universal_py3_wheel(resolved_candidates[0]["filename"])
            ):
                body_lines.extend(alias(wheel_sel_name, resolved_candidates[0]["target"]))
            else:
                chooser_name = "_wheel_chooser" + key_sfx
                pycross_loads.setdefault("wheel_chooser.bzl", {})["pycross_wheel_chooser"] = True
                body_lines.extend([
                    "pycross_wheel_chooser(",
                    "    name = {},".format(json.encode(chooser_name)),
                    "    candidates = [{}],".format(", ".join([json.encode(c["filename"]) for c in candidates])),
                    ")",
                    "",
                ])
                for cand in resolved_candidates:
                    fn = cand["filename"]
                    body_lines.extend(flag_setting(_spoke_wheel_cs_name(slot, extra, fn), ":" + chooser_name, fn))
                branches = [
                    (":" + _spoke_wheel_cs_name(slot, extra, cand["filename"]), cand["target"])
                    for cand in resolved_candidates
                ]
                no_match_target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
                body_lines.extend(alias(
                    wheel_sel_name,
                    select_expr(branches, default = no_match_target, indent = 1),
                    actual_is_expr = True,
                ))
                has_universal = all_resolved and any([is_universal_py3_wheel(fn) for fn in resolved_filenames])
                if not sdist_target and resolved_candidates and not has_universal:
                    _render_wheel_match_condition(
                        body_lines,
                        slot,
                        extra,
                        resolved_filenames,
                        all_resolved,
                        spoke_wheel_available_target(slot, extra),
                        require_target = True,
                        loads = loads,
                    )
        else:
            target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
            body_lines.extend(alias(wheel_sel_name, target))

        # 2e. Public pycross_wheel_dir target for base packages
        if not extra:
            pycross_loads.setdefault("wheel_dir.bzl", {})["pycross_wheel_dir"] = True
            body_lines.extend([
                "pycross_wheel_dir(",
                "    name = {},".format(json.encode(spoke_wheel_target(slot))),
                "    src = {},".format(json.encode(":" + wheel_sel_name)),
                "    whldir_name = {},".format(json.encode(whldir_name(pkg_key))),
                "    package = {},".format(json.encode(pkg_key)),
                ")",
                "",
            ])

        # 2f. Variant-reset gate & wheel library
        raw_gate_label = _emit_reset_gate_for_entry(entry, resolved_filenames, all_resolved)
        reset = entry.get("reset")
        raw_st = reset.get("raw_status", "never") if reset else "never"
        lib_name = spoke_raw_target(slot, extra) if in_cycle else spoke_pkg_target(slot, extra)

        if raw_st != "never":
            loads["reset"] = True
            body_lines.extend([
                "pycross_resettable_wheel_library(",
                "    name = {},".format(json.encode(lib_name)),
                "    reset_gate = {},".format(json.encode(raw_gate_label) if raw_gate_label else "None"),
            ])
        else:
            pycross_loads.setdefault("wheel_library.bzl", {})["pycross_wheel_library"] = True
            body_lines.extend([
                "pycross_wheel_library(",
                "    name = {},".format(json.encode(lib_name)),
            ])

        body_lines.extend([
            "    package_name = {},".format(json.encode(entry["name"])),
            "    package_version = {},".format(json.encode(entry["version"])),
            "    wheel = {},".format(json.encode(":" + wheel_sel_name)),
        ])
        for attr_name in ("site_paths", "bin_paths", "data_paths", "include_paths"):
            _render_str_list_attr(body_lines, attr_name, entry.get(attr_name))
        if has_deps:
            body_lines.append("    deps = {},".format(deps_var))
        for field, attr_name in (
            ("install_exclude_globs", "install_exclude_globs"),
            ("post_install_patches", "post_install_patches"),
            ("wheel_library_tags", "tags"),
        ):
            _render_str_list_attr(body_lines, attr_name, entry.get(field))
        if entry.get("precompile"):
            body_lines.append("    precompile = {},".format(json.encode(entry["precompile"])))
        body_lines.extend([")", ""])

        if not in_cycle:
            body_lines.extend(alias(spoke_raw_target(slot, extra), ":" + lib_name))

        # 2g. dist_info (points at underlying wheel library lib_name)
        pycross_loads.setdefault("dist_info.bzl", {})["pycross_dist_info"] = True
        body_lines.extend([
            "pycross_dist_info(",
            "    name = {},".format(json.encode(spoke_dist_info_target(slot, extra))),
            "    pkg = {},".format(json.encode(":" + lib_name)),
            ")",
            "",
        ])

        # 2h. Sdist build runtime deps proxy
        if entry.get("has_sdist_repo") and has_deps:
            pycross_loads.setdefault("proxy.bzl", {})["pycross_library_proxy"] = True
            body_lines.extend([
                "pycross_library_proxy(",
                "    name = {},".format(json.encode(spoke_sdist_deps_target(slot, extra))),
                "    deps = {},".format(deps_var),
                ")",
                "",
            ])

    # 3. Emit cycle proxies (and any multi-hop cycle reachability evaluators) for cycle members.
    for idx, entry in enumerate(entries):
        if idx not in cycle_plans:
            continue
        cycle = entry["cycle"]
        plan = cycle_plans[idx]
        slot = entry.get("slot", "")
        extra = entry.get("extra", "")
        node_targets = cycle["node_targets"]

        new_evaluators = []
        for cg in plan.conditional_groups:
            if cg.eval_match_name and cg.eval_match_name in available_eval_matches:
                continue
            if cg.pair_name not in emitted_cycle_pairs:
                emitted_cycle_pairs[cg.pair_name] = True
                new_evaluators.append((cg.pair_name, cg.source, cg.representative))

        if new_evaluators:
            pycross_loads.setdefault("cycle_dep_needed.bzl", {})["pycross_cycle_dep_needed"] = True
            edges = cycle["edges"]
            edges_json = json.encode(edges)
            if edges_json not in emitted_cycle_edges:
                edges_var = "_CYCLE_EDGES_JSON" + _entry_key_sfx(slot, extra).upper()
                emitted_cycle_edges[edges_json] = edges_var
                body_lines.append("{} = {}".format(edges_var, json.encode(edges_json)))
                body_lines.append("")
            edges_var = emitted_cycle_edges[edges_json]

            needs_variants = has_variants and any([
                "__variant_" in (e.get("marker") or "")
                for edge_list in edges.values()
                for e in edge_list
            ])
            for pair_name, source, representative in new_evaluators:
                body_lines.extend([
                    "pycross_cycle_dep_needed(",
                    "    name = {},".format(json.encode(pair_name)),
                    "    source = {},".format(json.encode(source)),
                    "    target = {},".format(json.encode(representative)),
                    "    edges = {},".format(edges_var),
                ])
                if needs_variants:
                    body_lines.append("    variants = [{}],".format(json.encode(variant_state_lbl)))
                body_lines.extend([")", ""])
                body_lines.extend(flag_setting(marker_match_target_name(pair_name), ":" + pair_name, "true"))

        def _member_raw_label(node):
            ms, mt = node_targets[node]
            return spoke_target_label(ms, mt, current_spoke = spoke_repo)

        unconditional_deps = [_member_raw_label(u) for u in plan.unconditional_deps]
        conditional_by_cond = {}
        for cg in plan.conditional_groups:
            if cg.eval_match_name and cg.eval_match_name in available_eval_matches:
                match_name = cg.eval_match_name
            else:
                match_name = marker_match_target_name(cg.pair_name)
            cond_deps = conditional_by_cond.setdefault(":" + match_name, {})
            for m in cg.group_members:
                cond_deps[_member_raw_label(m)] = True

        pycross_loads.setdefault("proxy.bzl", {})["pycross_library_proxy"] = True
        body_lines.extend([
            "pycross_library_proxy(",
            "    name = {},".format(json.encode(spoke_pkg_target(slot, extra))),
            "    actual = {},".format(json.encode(":" + spoke_raw_target(slot, extra))),
        ])
        body_lines.extend(deps_plus_selects(
            "deps",
            unconditional_deps,
            conditional_by_cond,
            indent = 1,
            inline_values = True,
            trailing_comma = True,
        ))
        body_lines.extend([")", ""])

    # 4. Emit _nomatch config_settings needed by reset gates.
    for eval_name in sorted(nomatch_evals.keys()):
        body_lines.extend(flag_setting("{}_nomatch".format(eval_name), ":" + eval_name, "false"))

    if loads.get("wheel_matched"):
        pycross_loads.setdefault("wheel_chooser.bzl", {})["pycross_wheel_matched"] = True

    header = [
        "# This file is generated by rules_pycross.",
        "# It is not intended for manual editing.",
        "",
    ]
    if loads.get("selects"):
        header.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    for bzl, syms in sorted(pycross_loads.items()):
        header.append("load({}, {})".format(
            json.encode("@rules_pycross//pycross/private:" + bzl),
            ", ".join([json.encode(s) for s in sorted(syms.keys())]),
        ))
    if loads.get("reset"):
        header.append('load({}, "pycross_resettable_wheel_library")'.format(
            json.encode(state_reset_bzl_label(state_repo)),
        ))
    header.extend([
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])

    return "\n".join(header + body_lines) + "\n"

def render_spoke_hook_files(payload, hooks, override_configs):
    """Run spoke-scoped `PACKAGE_REPO_HOOKS` and emit `_sdist/` shim + version-free aliases.

    Args:
        payload: Decoded spoke payload dict.
        hooks: Dict of spoke-scoped `{backend_name: hook_fn}`.
        override_configs: Dict of pkg_spec -> `{backend_name: backend_attrs}` for this spoke.

    Returns:
        Dict of relative output path -> file content string (empty if no hook generated output).
    """
    if not hooks or not override_configs:
        return {}

    canon_name = payload["name"]
    base_entries = [e for e in payload.get("entries", []) if not e.get("extra")]
    if not base_entries:
        return {}

    packages_info = {
        canon_name: {
            "versions": [
                struct(
                    version = e["version"],
                    package_key = e["pkg_key"],
                    has_sdist = bool(e.get("sdist_label")),
                )
                for e in base_entries
            ],
        },
    }
    raw_files = run_package_repo_hooks(hooks, packages_info, override_configs)
    if not raw_files:
        return {}

    files = {}
    for path, content in raw_files.items():
        if path.endswith("/BUILD.bazel"):
            alias_lines = []
            for e in base_entries:
                pkg_key = e["pkg_key"]
                if 'name = "{}"'.format(pkg_key) in content or "name = '{}'".format(pkg_key) in content:
                    alias_lines.extend(alias(spoke_hook_target(e.get("slot", "")), ":" + pkg_key))
            if alias_lines:
                content = content.rstrip("\n") + "\n\n" + "\n".join(alias_lines)
        files[path] = content

    # Emit _sdist/BUILD.bazel shim so published hooks referencing "//_sdist:<package_key>"
    # resolve directly to this spoke's //:sdist[_<slot>].
    sdist_lines = ['package(default_visibility = ["//visibility:public"])', ""]
    for e in base_entries:
        if e.get("sdist_label"):
            sdist_lines.extend(alias(e["pkg_key"], "//:" + spoke_sdist_target(e.get("slot", ""))))
    files["_sdist/BUILD.bazel"] = "\n".join(sdist_lines) + "\n"
    return files

def _spoke_repo_impl(rctx):
    payload = json.decode(rctx.attr.spoke_data)
    rctx.file("REPO.bazel", "")
    rctx.file("BUILD.bazel", render_spoke_build(payload))

    if PACKAGE_REPO_HOOKS and rctx.attr.override_configs:
        spoke_hooks = {
            b: fn
            for b, fn in PACKAGE_REPO_HOOKS.items()
            if is_spoke_hook_backend(b)
        }
        override_configs = json.decode(rctx.attr.override_configs)
        for path, content in render_spoke_hook_files(payload, spoke_hooks, override_configs).items():
            rctx.file(path, content)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

spoke_repo = repository_rule(
    implementation = _spoke_repo_impl,
    attrs = {
        "spoke_data": attr.string(
            doc = "JSON-encoded per-package spoke payload from build_spoke_payloads().",
            mandatory = True,
        ),
        "override_configs": attr.string(
            doc = "Optional JSON-encoded override configs matching this package for spoke-scoped hooks.",
        ),
    },
)
