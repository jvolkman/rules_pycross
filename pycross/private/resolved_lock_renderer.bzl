"""Pure Starlark implementation of the resolved_lock_renderer.

This module generates the BUILD.bazel content for the `_lock` repository.
It uses PEP 508 marker expressions for platform-conditional dependencies
and a wheel chooser for platform-specific wheel selection.

Naming conventions for generated targets:
  - `_raw_<pkg_key>`: The underlying `pycross_wheel_library` target.
  - `<pkg_key>`: For cycle members, this is a `pycross_library_proxy` (created by
    `pycross_cycle_member_marker_deps`) that wraps the raw target and adds conditional deps.
    For extras-only packages (e.g., `name[extra]@version`), this is a `pycross_library_proxy`
    with `actual` pointing to the base package and extra-specific deps in `deps`.
  - `<pkg_name>[_all_]@<version>`: A synthetic `pycross_library_proxy` that aggregates the
    base package and all of its parsed extras into a single target.
"""

load("@pypackaging.bzl", "pypackaging")
load(":util.bzl", "has_build_fallback", "is_platform_specific", "is_universal_py3_wheel", "marker_evaluator_name", "parse_package_key", "sanitize_name")

def _ind(text, tabs = 1):
    if not text:
        return ""
    return ("    " * tabs) + text

def _is_in_same_cycle(dep_key, pkg, packages):
    cycle_group = pkg.get("cycle_group")
    if not cycle_group:
        return False
    dep_pkg = packages.get(dep_key)
    if not dep_pkg:
        return False
    return dep_pkg.get("cycle_group") == cycle_group

def _wheel_target(file_ref, repo_map):
    return file_ref.get("label") or repo_map.get(file_ref.get("key"))

def _render_extras_aggregates(lines, packages):
    """Renders [_all_] pycross_library_proxy targets that aggregate a base package and all its extras."""
    base_packages_with_extras = {}
    for pkg_key in packages.keys():
        parts = parse_package_key(pkg_key)
        if not parts.extra:
            continue
        base_packages_with_extras.setdefault((parts.name, parts.version), []).append(pkg_key)

    for (base_name, version), extra_keys in sorted(base_packages_with_extras.items()):
        base_pkg_key = "{}@{}".format(base_name, version)
        lines.extend([
            _ind("pycross_library_proxy("),
            _ind('name = "{}[_all_]@{}",'.format(base_name, version), 2),
            _ind('actual = ":{}",'.format(base_pkg_key), 2),
            _ind("deps = [", 2),
        ])
        for extra_key in sorted(extra_keys):
            lines.append(_ind('":{}\",'.format(extra_key), 3))
        lines.extend([
            _ind("],", 2),
            _ind(")"),
            "",
        ])

def _collect_unique_markers(packages):
    """Collect all unique (marker, extra) pairs across packages.

    Returns a dict mapping (marker_string, extra_value) to True.
    The extra is derived from the package key (e.g. 'foo[test]@1.0' -> 'test').
    """
    markers = {}
    for pkg_key, pkg in packages.items():
        extra = parse_package_key(pkg_key).extra
        for md in pkg.get("marker_dependencies", []):
            marker = md.get("marker")
            if not marker:
                continue

            # Optimization: if "extra" is not in the marker string, it doesn't reference the extra variable.
            # We can share a single evaluator by setting extra to "".
            effective_extra = extra if "extra" in marker else ""
            markers[(marker, effective_extra)] = True

        # Availability markers come from root project dependency edges, which
        # never reference `extra`, so they share the extra-free evaluators.
        for marker in pkg.get("availability_markers", []):
            markers[(marker, "")] = True
    return markers.keys()

def _matching_variant_resolvers(markers, variant_resolvers):
    """Return the subset of variant_resolvers referenced by markers.

    Args:
        markers: Iterable of PEP 508 marker strings.
        variant_resolvers: Either a list of resolver target labels (all returned
            when any marker references `__variant_`) or a dict mapping
            resolver target label -> list of item qualified names.
    """
    if not variant_resolvers:
        return []
    variant_markers = [m for m in markers if m and "__variant_" in m]
    if not variant_markers:
        return []
    if type(variant_resolvers) != "dict":
        return variant_resolvers

    matched = []
    for label, qnames in sorted(variant_resolvers.items()):
        found = False
        for q in qnames:
            sq = "'__variant_{}'".format(q)
            dq = '"__variant_{}"'.format(q)
            for m in variant_markers:
                if sq in m or dq in m:
                    found = True
                    break
            if found:
                break
        if found:
            matched.append(label)
    return matched if matched else sorted(variant_resolvers.keys())

def _render_marker_evaluators(lines, unique_markers, variant_resolvers = None):
    """Render deduped pycross_pep508_evaluator and config_setting targets.

    Args:
        lines: Output lines list.
        unique_markers: Iterable of (marker_str, extra) tuples.
        variant_resolvers: Optional list of variant_resolver target labels, or
            dict mapping resolver label -> list of item qualified names.
    """
    for marker_str, extra in sorted(unique_markers):
        eval_name = marker_evaluator_name(marker_str, extra)
        resolvers = _matching_variant_resolvers([marker_str], variant_resolvers)

        # Evaluator rule — returns FeatureFlagInfo("true"/"false")
        lines.extend([
            _ind("pycross_pep508_evaluator("),
            _ind('name = "{}",'.format(eval_name), 2),
            _ind('expr = "{}",'.format(marker_str.replace('"', '\\"')), 2),
        ])
        if extra:
            lines.append(_ind('extra = "{}",'.format(extra), 2))
        if resolvers:
            lines.append(_ind("variants = [{}],".format(", ".join(['"{}"'.format(r) for r in resolvers])), 2))
        lines.extend([
            _ind(")"),
            "",
        ])

        # Config setting that matches when the evaluator says "true"
        lines.extend([
            _ind("native.config_setting("),
            _ind('name = "{}_match",'.format(eval_name), 2),
            _ind("flag_values = {", 2),
            _ind('":{eval}": "true",'.format(eval = eval_name), 3),
            _ind("},", 2),
            _ind(")"),
            "",
        ])

def _render_resolution_marker_evaluators(lines, resolution_marker_exprs, variant_resolvers = None):
    """Render pycross_pep508_evaluator + config_setting for resolution-marker forks.

    Entries in ``resolution_marker_exprs`` are either:
    - A string (simple fork): generates an evaluator + config_setting.
    - A dict with ``variant`` and ``marker`` keys (compound fork): generates a
      config_setting_group that matches both the variant and the marker.

    Args:
        lines: Output lines list.
        resolution_marker_exprs: Dict mapping constraint_name to either a
            PEP 508 marker expression string or a compound dict.
        variant_resolvers: Optional list of variant_resolver target labels, or
            dict mapping resolver label -> list of item qualified names.
    """
    for constraint_name, entry in sorted(resolution_marker_exprs.items()):
        if type(entry) == "dict":
            # Compound constraint: combine variant + marker config_settings.
            # Both is_<variant> and is_<marker> must already exist.
            lines.extend([
                _ind("selects.config_setting_group("),
                _ind('name = "is_{}",'.format(constraint_name), 2),
                _ind("match_all = [", 2),
                _ind('"is_{}",'.format(entry["variant"]), 3),
                _ind('"is_{}",'.format(entry["marker"]), 3),
                _ind("],", 2),
                _ind(")"),
                "",
            ])
        else:
            # Simple fork: evaluator + config_setting.
            eval_name = "_res_eval_{}".format(constraint_name)
            resolvers = _matching_variant_resolvers([entry], variant_resolvers)
            lines.extend([
                _ind("pycross_pep508_evaluator("),
                _ind('name = "{}",'.format(eval_name), 2),
                _ind('expr = "{}",'.format(entry.replace('"', '\\"')), 2),
            ])
            if resolvers:
                lines.append(_ind("variants = [{}],".format(", ".join(['"{}"'.format(r) for r in resolvers])), 2))
            lines.extend([
                _ind(")"),
                "",
            ])

            # Config setting matching when the evaluator says "true".
            lines.extend([
                _ind("native.config_setting("),
                _ind('name = "is_{}",'.format(constraint_name), 2),
                _ind("flag_values = {", 2),
                _ind('":{eval}": "true",'.format(eval = eval_name), 3),
                _ind("},", 2),
                _ind(")"),
                "",
            ])

def _build_cycle_edges_dict(scc, packages):
    """Builds the in-cycle edge map for marker mode.

    Returns a dict with format:
      {pkg: [{"dep": dep_key, "marker": "..."}, ...], ...}
    """
    scc_set = {k: True for k in scc}
    edges = {}
    for pkg_key in sorted(scc):
        pkg = packages.get(pkg_key, {})
        parts = parse_package_key(pkg_key)
        base_key = "{}@{}".format(parts.name, parts.version) if parts.extra else None
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

def _render_edges_dict(edges, base_indent = 1):
    """Renders an edges dict as pretty-printed Starlark dict literal lines.

    Args:
        edges: Dict of {node: [{dep, marker?}, ...], ...}.
        base_indent: Number of indent levels for the outer braces.

    Returns:
        A list of indented lines forming a valid Starlark dict literal.
    """
    lines = [_ind("{", base_indent)]
    for pkg_key in sorted(edges.keys()):
        edge_list = edges[pkg_key]
        if not edge_list:
            lines.append(_ind('"{}": [],'.format(pkg_key), base_indent + 1))
        else:
            lines.append(_ind('"{}": ['.format(pkg_key), base_indent + 1))
            for entry in edge_list:
                parts = ['"dep": {}'.format(repr(entry["dep"]))]
                if entry.get("marker"):
                    parts.append('"marker": {}'.format(repr(entry["marker"])))
                lines.append(_ind("{{{}}},".format(", ".join(parts)), base_indent + 2))
            lines.append(_ind("],", base_indent + 1))
    lines.append(_ind("}", base_indent))
    return lines

def _render_marker_cycle_member_deps(lines, cycle_groups, packages, variant_resolvers = None):
    """Renders pycross_cycle_member_marker_deps macro calls for each cycle member.

    Each macro call internally creates N reachability evaluators + config_settings
    and wraps them in a pycross_library_proxy with select() per dep.

    Only cycle group members that appear in ``packages`` are rendered; groups
    whose members are entirely outside the resolved set are silently skipped.
    """
    for group_name, scc in sorted(cycle_groups.items()):
        # Only render members that are part of the resolved package set.
        resolved_members = [m for m in scc if m in packages]
        if not resolved_members:
            continue

        edges = _build_cycle_edges_dict(scc, packages)
        edge_markers = [
            entry.get("marker", "")
            for edge_list in edges.values()
            for entry in edge_list
            if entry.get("marker")
        ]
        resolvers = _matching_variant_resolvers(edge_markers, variant_resolvers)

        sanitized_group_name = sanitize_name(group_name).upper()
        edges_var_name = "_{}_EDGES".format(sanitized_group_name)

        edges_lines = _render_edges_dict(edges, base_indent = 1)

        # Attach the variable assignment to the first line of the dict literal.
        edges_lines[0] = _ind("{} = ".format(edges_var_name)) + edges_lines[0].lstrip()
        lines.extend(edges_lines)
        lines.append("")

        for pkg_key in sorted(resolved_members):
            lines.append(_ind("pycross_cycle_member_marker_deps("))
            lines.append(_ind('name = "{}",'.format(pkg_key), 2))
            lines.append(_ind('raw_name = "_raw_{}",'.format(pkg_key), 2))
            lines.append(_ind('member = "{}",'.format(pkg_key), 2))
            lines.append(_ind("edges = {},".format(edges_var_name), 2))
            if resolvers:
                lines.append(_ind("variants = [{}],".format(", ".join(['"{}"'.format(r) for r in resolvers])), 2))
            lines.append(_ind(")"))
            lines.append("")

def _render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_target = None):
    """Render a wheel chooser target and per-wheel config_settings + alias.

    Returns True when a wheel-only availability target was emitted under the
    name _wheel_available_<pkg>; the caller must then expose _available_<pkg>
    via _render_marker_availability(wheel_gated = True).
    """
    candidates = pkg.get("wheel_candidates", [])
    if not candidates:
        return False

    # Resolve candidate targets first so a sole universal py3-none-any wheel can
    # bypass pycross_wheel_chooser, config_setting, and select() completely.
    resolved_candidates = []
    for candidate in candidates:
        target = _wheel_target(candidate.get("file_reference", {}), repo_map)
        if target:
            resolved_candidates.append((candidate, target))

    if (
        len(candidates) == 1 and
        len(resolved_candidates) == 1 and
        is_universal_py3_wheel(resolved_candidates[0][0]["filename"])
    ):
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_wheel_{}",'.format(pkg_key), 2),
            _ind('actual = "{}",'.format(resolved_candidates[0][1]), 2),
            _ind(")"),
            "",
        ])
        return False

    filenames = [c["filename"] for c in candidates]
    chooser_name = "_wheel_chooser_{}".format(pkg_key)

    lines.extend([
        _ind("pycross_wheel_chooser("),
        _ind('name = "{}",'.format(chooser_name), 2),
        _ind("candidates = {},".format(filenames), 2),
        _ind(")"),
        "",
    ])

    for candidate, _target in resolved_candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, sanitize_name(filename))
        lines.extend([
            _ind("native.config_setting("),
            _ind('name = "{}",'.format(cs_name), 2),
            _ind("flag_values = {", 2),
            _ind('":{chooser}": "{filename}",'.format(
                chooser = chooser_name,
                filename = filename,
            ), 3),
            _ind("},", 2),
            _ind(")"),
            "",
        ])

    # Wheel alias selecting over the config_settings
    lines.extend([
        _ind("native.alias("),
        _ind('name = "_wheel_{}",'.format(pkg_key), 2),
        _ind("actual = select({", 2),
    ])
    for candidate, target in resolved_candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, sanitize_name(filename))
        lines.append(_ind('":{}": "{}",'.format(cs_name, target), 3))
    no_match_target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
    lines.append(_ind('"//conditions:default": "{}",'.format(no_match_target), 3))
    lines.extend([
        _ind("}),", 2),
        _ind(")"),
        "",
    ])

    # Wheel-only availability config_setting: matches when any wheel matches.
    # Always emitted under _wheel_available_<pkg> so thin repos can compose it
    # with their own per-member availability_markers. When the package carries
    # no availability_markers in _lock, _render_marker_availability aliases
    # _available_<pkg> -> _wheel_available_<pkg> for direct consumers.
    has_universal = (
        len(resolved_candidates) == len(candidates) and
        any([is_universal_py3_wheel(c["filename"]) for c, _ in resolved_candidates])
    )
    if sdist_target or not resolved_candidates or has_universal:
        return False

    group_name = "_wheel_available_{}".format(pkg_key)
    cs_names = [
        ":_wheel_cs_{}_{}".format(pkg_key, sanitize_name(candidate["filename"]))
        for candidate, _target in resolved_candidates
    ]
    if len(cs_names) == 1:
        lines.extend([
            _ind("native.alias("),
            _ind('name = "{}",'.format(group_name), 2),
            _ind('actual = "{}",'.format(cs_names[0]), 2),
            _ind(")"),
            "",
        ])
    elif len(cs_names) >= 3 and len(resolved_candidates) == len(candidates):
        matched_name = "_wheel_matched_{}".format(pkg_key)
        lines.extend([
            _ind("pycross_wheel_matched("),
            _ind('name = "{}",'.format(matched_name), 2),
            _ind('chooser = ":{}",'.format(chooser_name), 2),
            _ind(")"),
            "",
            _ind("native.config_setting("),
            _ind('name = "{}",'.format(group_name), 2),
            _ind("flag_values = {", 2),
            _ind('":{}": "true",'.format(matched_name), 3),
            _ind("},", 2),
            _ind(")"),
            "",
        ])
    else:
        lines.extend([
            _ind("selects.config_setting_group("),
            _ind('name = "{}",'.format(group_name), 2),
            _ind("match_any = [", 2),
        ])
        for cs in cs_names:
            lines.append(_ind('"{}",'.format(cs), 3))
        lines.extend([
            _ind("],", 2),
            _ind(")"),
            "",
        ])
    return True

def _render_marker_package_deps(lines, pkg_key, pkg_key_san, pkg, packages):
    """Render deps using marker-based select() instead of environment-based."""
    marker_deps = pkg.get("marker_dependencies", [])
    extra = parse_package_key(pkg_key).extra

    unconditional = {}
    conditional = []
    for md in marker_deps:
        dep_key = md["key"]
        if _is_in_same_cycle(dep_key, pkg, packages):
            continue
        if md.get("marker"):
            conditional.append(md)
        else:
            unconditional[dep_key] = True

    # Collect per-dep unique evaluators, dropping any dep already unconditional.
    dep_evals = {}  # dep_key -> {eval_name: True}
    for md in conditional:
        dep_key = md["key"]
        if dep_key in unconditional:
            continue
        effective_extra = extra if "extra" in md["marker"] else ""
        eval_name = marker_evaluator_name(md["marker"], effective_extra)
        dep_evals.setdefault(dep_key, {})[eval_name] = True

    # Group single-evaluator deps by evaluator; deps reachable under multiple
    # distinct markers get a shared match_any config_setting_group so overlapping
    # markers never emit duplicate labels in `deps`.
    by_condition = {}  # condition_label -> {dep_key: True}
    multi_groups = {}  # tuple(sorted_evals) -> group_name
    for dep_key in sorted(dep_evals.keys()):
        evals = sorted(dep_evals[dep_key].keys())
        if len(evals) == 1:
            cond = ":{}_match".format(evals[0])
        else:
            evals_key = tuple(evals)
            if evals_key not in multi_groups:
                group_name = "_dep_any_%s_%x" % (
                    pkg_key_san,
                    hash("|".join(evals)) & 0xffffffff,
                )
                multi_groups[evals_key] = group_name
                lines.extend([
                    _ind("selects.config_setting_group("),
                    _ind('name = "{}",'.format(group_name), 2),
                    _ind("match_any = [", 2),
                ])
                for ev in evals:
                    lines.append(_ind('":{}_match",'.format(ev), 3))
                lines.extend([
                    _ind("],", 2),
                    _ind(")"),
                    "",
                ])
            cond = ":{}".format(multi_groups[evals_key])
        by_condition.setdefault(cond, {})[dep_key] = True

    lines.append(_ind("_{}_deps = [".format(pkg_key_san)))
    for dep_key in sorted(unconditional.keys()):
        lines.append(_ind('"{}",'.format(":" + dep_key), 2))
    lines.append(_ind("]"))

    for cond in sorted(by_condition.keys()):
        dep_list = ", ".join(['":{}"'.format(k) for k in sorted(by_condition[cond].keys())])
        lines[-1] = lines[-1] + " + select({"
        lines.append(_ind('"{}": [{}],'.format(cond, dep_list), 2))
        lines.append(_ind('"//conditions:default": [],', 2))
        lines.append(_ind("})", 1))

    lines.append("")

def _render_marker_availability(lines, pkg_key, pkg, wheel_gated = False, base_available = None):
    """Render an _available_<pkg> config_setting_group from availability markers.

    No-op unless the package carries availability_markers, wheel_gated, or
    base_available is given. With wheel_gated, the marker group is ANDed with
    the chooser's _wheel_available_<pkg> group (or aliased directly when no
    markers exist); with base_available (extras packages), it is ANDed with
    the base package's _available_ group; otherwise the markers alone gate the
    package.
    """
    markers = pkg.get("availability_markers", [])
    gate = None
    if wheel_gated:
        gate = "_wheel_available_{}".format(pkg_key)
    elif base_available:
        gate = base_available

    if not markers:
        if gate:
            lines.extend([
                _ind("native.alias("),
                _ind('name = "_available_{}",'.format(pkg_key), 2),
                _ind('actual = ":{}",'.format(gate), 2),
                _ind(")"),
                "",
            ])
        return
    marker_group = "_available_{}".format(pkg_key)
    if gate:
        marker_group = "_marker_available_{}".format(pkg_key)
    lines.extend([
        _ind("selects.config_setting_group("),
        _ind('name = "{}",'.format(marker_group), 2),
        _ind("match_any = [", 2),
    ])
    for marker in markers:
        eval_name = marker_evaluator_name(marker, "")
        lines.append(_ind('":{}_match",'.format(eval_name), 3))
    lines.extend([
        _ind("],", 2),
        _ind(")"),
        "",
    ])
    if gate:
        lines.extend([
            _ind("selects.config_setting_group("),
            _ind('name = "_available_{}",'.format(pkg_key), 2),
            _ind("match_all = [", 2),
            _ind('":{}",'.format(gate), 3),
            _ind('":{}",'.format(marker_group), 3),
            _ind("],", 2),
            _ind(")"),
            "",
        ])

def _render_str_list_attr(lines, attr_name, values):
    if values:
        lines.append(_ind("{} = [".format(attr_name), 2))
        for val in values:
            lines.append(_ind('"{}",'.format(val), 3))
        lines.append(_ind("],", 2))

def _render_marker_package(lines, pkg_key, pkg, packages, repo_map, rctx_name, reset_plan = None):
    """Renders all targets for a single package using marker-based deps and wheel selection."""
    pkg_key_san = sanitize_name(pkg_key)
    parts = parse_package_key(pkg_key)
    package_name = parts.name
    package_version = parts.version
    extra = parts.extra

    has_marker_deps = bool(pkg.get("marker_dependencies"))
    has_wheel_candidates = bool(pkg.get("wheel_candidates"))

    sdist_file = pkg.get("sdist_file")
    sdist_label = _wheel_target(sdist_file, repo_map) if sdist_file else None

    # Runtime deps
    if has_marker_deps:
        _render_marker_package_deps(lines, pkg_key, pkg_key_san, pkg, packages)

    if not has_wheel_candidates and extra:
        # Extras packages wrap the base package plus their own deps, so they
        # are only available where the base package is.
        base_pkg_key = "{}@{}".format(package_name, package_version)
        base_available = None
        if is_platform_specific(packages.get(base_pkg_key, {})):
            base_available = "_available_{}".format(base_pkg_key)
        _render_marker_availability(lines, pkg_key, pkg, base_available = base_available)

        proxy_name = "_raw_{}".format(pkg_key) if pkg.get("cycle_group") else pkg_key
        base_actual = "_raw_{}".format(base_pkg_key) if _is_in_same_cycle(base_pkg_key, pkg, packages) else base_pkg_key

        lines.extend([
            _ind("pycross_library_proxy("),
            _ind('name = "{}",'.format(proxy_name), 2),
            _ind('actual = ":{}",'.format(base_actual), 2),
            _ind("deps = _{}_deps,".format(pkg_key_san) if has_marker_deps else "deps = [],", 2),
            _ind(")"),
            "",
        ])
        return

    # Sdist alias
    if sdist_label:
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_sdist_{}",'.format(pkg_key), 2),
            _ind('actual = "{}",'.format(sdist_label), 2),
            _ind(")"),
            "",
        ])

    # Compute the sdist build target (if available) for fallback when no wheel matches.
    sdist_target = None
    has_sdist_repo = False
    if pkg.get("build_target"):
        sdist_target = pkg["build_target"]
    elif sdist_file and has_build_fallback(pkg):
        sdist_file_key = sdist_file.get("key")
        if sdist_file_key:
            sdist_repo_name = "{}_sdist_{}".format(rctx_name, sanitize_name(pkg_key))
            sdist_target = "@@{}//:wheel".format(sdist_repo_name)
            has_sdist_repo = True

    # Wheel chooser
    wheel_gated = False
    if has_wheel_candidates:
        wheel_gated = _render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_target = sdist_target)
    else:
        # No wheel candidates, alias directly to sdist_target or no_match_error
        target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_wheel_{}",'.format(pkg_key), 2),
            _ind('actual = "{}",'.format(target), 2),
            _ind(")"),
            "",
        ])

    if not wheel_gated and pkg.get("emit_unconditional_wheel_available"):
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_wheel_available_{}",'.format(pkg_key), 2),
            _ind('actual = "@rules_pycross//pycross/private:always_true",', 2),
            _ind(")"),
            "",
        ])

    _render_marker_availability(lines, pkg_key, pkg, wheel_gated = wheel_gated)

    # Library
    lib_name = pkg_key
    if pkg.get("cycle_group"):
        lib_name = "_raw_{}".format(pkg_key)

    reset = reset_plan.get(pkg_key) if reset_plan else None
    if reset and reset.ok:
        lines.extend([
            _ind("pycross_resettable_wheel_library("),
            _ind('name = "{}",'.format(lib_name), 2),
            _ind("reset_gate = {},".format('"{}"'.format(reset.gate) if reset.gate else "None"), 2),
        ])
    else:
        lines.extend([
            _ind("pycross_wheel_library("),
            _ind('name = "{}",'.format(lib_name), 2),
        ])
    lines.extend([
        _ind('package_name = "{}",'.format(package_name), 2),
        _ind('package_version = "{}",'.format(package_version), 2),
        _ind('wheel = ":_wheel_{}",'.format(pkg_key), 2),
    ])

    for attr_name in ("site_paths", "bin_paths", "data_paths", "include_paths"):
        _render_str_list_attr(lines, attr_name, pkg.get(attr_name))

    if has_marker_deps:
        lines.append(_ind("deps = _{}_deps,".format(pkg_key_san), 2))

    for field, attr_name in (
        ("install_exclude_globs", "install_exclude_globs"),
        ("post_install_patches", "post_install_patches"),
        ("wheel_library_tags", "tags"),
    ):
        _render_str_list_attr(lines, attr_name, pkg.get(field))

    if pkg.get("precompile"):
        lines.append(_ind('precompile = "{}",'.format(pkg["precompile"]), 2))

    lines.extend([
        _ind(")"),
        "",
    ])

    # Note: if this package is in a cycle group, the public target is created
    # by the pycross_cycle_member_marker_deps macro call (rendered separately).
    # The pycross_wheel_library above is named _raw_<pkg_key> in that case.

    # dist_info (point directly at _raw_<pkg> for cycle members so console script
    # exec analysis doesn't pull in the entire cycle SCC and reachability evaluators)
    lines.extend([
        _ind("pycross_dist_info("),
        _ind('name = "_dist_info_{}",'.format(pkg_key), 2),
        _ind('pkg = ":{lib}",'.format(lib = lib_name), 2),
        _ind(")"),
        "",
    ])

    # Sdist build runtime deps proxy: evaluated under wheel_build.deps's exec
    # platform transition so PEP 508 markers match the host platform, same-cycle
    # deps are excluded, and edges merged across workspace members are included.
    if has_sdist_repo and has_marker_deps:
        lines.extend([
            _ind("pycross_library_proxy("),
            _ind('name = "_sdist_deps_{}",'.format(pkg_key), 2),
            _ind("deps = _{}_deps,".format(pkg_key_san), 2),
            _ind(")"),
            "",
        ])

# ---- Variant reset -----------------------------------------------------------
#
# A repo's transition sets pycross's variant settings (`_pin_*`, `_default_*`,
# `_usable_*` and the repos' `_variants` flags). A package whose install and
# whole dependency closure don't depend on them is installed with those settings
# reset (`pycross_reset_wheel_library`), so every repo shares one install.
# Packages that may fall back to an sdist build only reset where a wheel
# matches: the build's tools can depend on the variant. Packages in cycles, with
# post-install patches or a custom build target, or with variant-gated edges stay
# in the caller's configuration, and so does everything that depends on them.

_VARIANT_TOKEN_PREFIX = "-variant-"  # `__variant_<qname>` after PEP 685 normalization

def _variant_token(item):
    """The variant token an `extra == / != '__variant_...'` item tests, as (token, positive)."""
    lhs, op, rhs = item
    if op not in ("==", "!="):
        return None
    if lhs.type == "variable" and lhs.value == "extra" and rhs.type == "string":
        value = rhs.value
    elif rhs.type == "variable" and rhs.value == "extra" and lhs.type == "string":
        value = lhs.value
    else:
        return None
    if not value.startswith(_VARIANT_TOKEN_PREFIX):
        return None
    return (value, op == "==")

def _fold_marker(elements, conflict_pairs):
    """Folds one parenthesized level of a parsed marker.

    Args:
        elements: Items (tuples), "and"/"or", and folded child results.
        conflict_pairs: {(token, token): True} of variant tokens that are never
            active together.

    Returns:
        "T" (always true), "F" (never true), "V" (depends on a variant) or
        "N" (doesn't depend on a variant).
    """
    groups = [[]]
    for e in elements:
        if e == "or":
            groups.append([])
        elif e != "and":
            groups[-1].append(e)

    results = []
    for group in groups:
        positive = {}
        negative = {}
        result = "T"
        for e in group:
            if e in ("T", "F", "V", "N"):
                if e == "F":
                    result = "F"
                    break
                if e == "V" or (e == "N" and result == "T"):
                    result = e
                continue
            token = _variant_token(e)
            if token:
                (positive if token[1] else negative)[token[0]] = True
                result = "V"
            elif result == "T":
                result = "N"
        if result != "F":
            for token in positive:
                if token in negative:
                    result = "F"
                    break
                for other in positive:
                    if (token, other) in conflict_pairs:
                        result = "F"
                        break
                if result == "F":
                    break
        results.append(result)

    if "T" in results:
        return "T"
    kept = [r for r in results if r != "F"]
    if not kept:
        return "F"
    return "V" if "V" in kept else "N"

def _marker_depends_on_variants(marker, conflict_pairs):
    """Whether a marker's value can depend on the selected variants.

    Clauses that require two items of one conflict set (which uv emits, e.g.
    `extra == 'group-5-app-a-test' and extra == 'group-5-app-b-test'`) can never
    be true, so they don't count.
    """
    if "__variant_" not in marker:
        return False
    tree = pypackaging.markers.parse(marker)
    stack = [[tree, 0, []]]
    for _ in range(1 << 20):
        frame = stack[-1]
        node = frame[0]
        if frame[1] < len(node):
            element = node[frame[1]]
            frame[1] += 1
            if type(element) == "list":
                stack.append([element, 0, []])
            else:
                frame[2].append(element)
            continue
        stack.pop()
        folded = _fold_marker(frame[2], conflict_pairs) if frame[2] else "T"
        if not stack:
            return folded == "V"
        stack[-1][2].append(folded)
    fail("marker too deeply nested: " + marker)

def _resolved_wheel_candidates(pkg, repo_map):
    return [
        c
        for c in pkg.get("wheel_candidates", [])
        if _wheel_target(c.get("file_reference", {}), repo_map)
    ]

def _compute_reset_plan(packages, repo_map, conflict_pairs, gate_lines):
    """Decides which packages install with reset variant settings, and their gates.

    Args:
        packages: The lock's packages.
        repo_map: File key -> label.
        conflict_pairs: {(token, token): True} (see _fold_marker).
        gate_lines: Output lines for the gate config_setting(_group)s.

    Returns:
        {pkg_key: struct(ok, gate)}. `gate` is a label that must match for the
        reset to apply (None means always).
    """
    plan = {}
    nomatch = {}  # marker evaluator names that need an `_nomatch` config_setting
    edge_gates = {}  # (eval_name, dep_key) -> label, shared across packages

    def group(name, kind, labels):
        gate_lines.extend([
            _ind("selects.config_setting_group("),
            _ind('name = "{}",'.format(name), 2),
            _ind("{} = [".format(kind), 2),
        ] + [_ind('"{}",'.format(label), 3) for label in labels] + [
            _ind("],", 2),
            _ind(")"),
            "",
        ])
        return ":" + name

    def compute(key):
        no = struct(ok = False, gate = None)
        pkg = packages[key]
        parts = parse_package_key(key)
        resolved = _resolved_wheel_candidates(pkg, repo_map)
        is_extras_proxy = not pkg.get("wheel_candidates") and parts.extra
        if pkg.get("cycle_group") or pkg.get("post_install_patches") or pkg.get("build_target"):
            return no
        base = None
        if is_extras_proxy:
            base = plan.get("{}@{}".format(parts.name, parts.version))
            if not base or not base.ok:
                return no
        elif not resolved:
            return no

        deps = pkg.get("marker_dependencies", [])
        for md in deps:
            if md.get("marker") and _marker_depends_on_variants(md["marker"], conflict_pairs):
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
                if len(resolved) >= 3 and all_resolved:
                    matched_name = "_wheel_matched_{}".format(key)
                    gate_name = "_reset_wheel_{}".format(key)
                    gate_lines.extend([
                        _ind("pycross_wheel_matched("),
                        _ind('name = "{}",'.format(matched_name), 2),
                        _ind('chooser = ":_wheel_chooser_{}",'.format(key), 2),
                        _ind(")"),
                        "",
                        _ind("native.config_setting("),
                        _ind('name = "{}",'.format(gate_name), 2),
                        _ind("flag_values = {", 2),
                        _ind('":{}": "true",'.format(matched_name), 3),
                        _ind("},", 2),
                        _ind(")"),
                        "",
                    ])
                    items.append(":" + gate_name)
                else:
                    cs_names = [":_wheel_cs_{}_{}".format(key, sanitize_name(c["filename"])) for c in resolved]
                    items.append(cs_names[0] if len(cs_names) == 1 else group("_reset_wheel_" + key, "match_any", cs_names))

        for md in deps:
            dep = plan.get(md["key"])
            if not dep or not dep.ok:
                # Conditional non-variant edge to a non-resettable dep: safe to
                # reset whenever the marker does not match.
                effective_extra = parts.extra if "extra" in md["marker"] else ""
                eval_name = marker_evaluator_name(md["marker"], effective_extra)
                nomatch[eval_name] = True
                items.append(":{}_nomatch".format(eval_name))
                continue
            if not dep.gate:
                continue
            if not md.get("marker"):
                items.append(dep.gate)
                continue

            # A conditional edge only needs the dep's gate where the edge applies.
            effective_extra = parts.extra if "extra" in md["marker"] else ""
            eval_name = marker_evaluator_name(md["marker"], effective_extra)
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

    for root in sorted(packages.keys()):
        if root in plan:
            continue
        stack = [(root, False)]
        visiting = {}
        for _ in range(1 << 20):
            if not stack:
                break
            key, expanded = stack.pop()
            if key in plan:
                continue
            if key not in packages:
                plan[key] = struct(ok = False, gate = None)
                continue
            if expanded:
                plan[key] = compute(key)
                continue
            if key in visiting:
                continue
            visiting[key] = True
            stack.append((key, True))
            parts = parse_package_key(key)
            if not packages[key].get("wheel_candidates") and parts.extra:
                stack.append(("{}@{}".format(parts.name, parts.version), False))
            for md in packages[key].get("marker_dependencies", []):
                if md["key"] not in plan and md["key"] not in visiting:
                    stack.append((md["key"], False))

    for eval_name in sorted(nomatch):
        gate_lines.extend([
            _ind("native.config_setting("),
            _ind('name = "{}_nomatch",'.format(eval_name), 2),
            _ind("flag_values = {", 2),
            _ind('":{}": "false",'.format(eval_name), 3),
            _ind("},", 2),
            _ind(")"),
            "",
        ])
    return plan

def _conflict_pairs(conflict_sets):
    tokens = [
        [pypackaging.utils.canonicalize_name("__variant_" + qname) for qname in qnames]
        for qnames in conflict_sets
    ]
    pairs = {}
    for set_tokens in tokens:
        for a in set_tokens:
            for b in set_tokens:
                if a != b:
                    pairs[(a, b)] = True
    return pairs

def render_reset_bzl(set_suffixes, flag_labels, string_flag_labels = None):
    """Renders `_lock/reset.bzl`: the variant-reset transition and rule.

    Args:
        set_suffixes: The workspace's conflict set suffixes.
        flag_labels: Every member repo's `_variants` bool_flag labels.
        string_flag_labels: Optional list of member repos' `_variants` string_flag labels.

    Returns:
        The file content.
    """
    outputs = []
    for suffix in sorted(set_suffixes):
        outputs.append(('"//_lock:_pin_{}"'.format(suffix), '""'))
        outputs.append(('"//_lock:_default_{}"'.format(suffix), '""'))
        outputs.append(('"//_lock:_usable_{}"'.format(suffix), '"*"'))
    for label in sorted({label: True for label in flag_labels}.keys()):
        outputs.append(('"{}"'.format(label), "False"))
    for label in sorted({label: True for label in (string_flag_labels or [])}.keys()):
        outputs.append(('"{}"'.format(label), '""'))
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

# ---- Main render function ---------------------------------------------------

def render_lock_bzl(lock, repo_map, rctx_name = "", variant_resolvers = None, reset_conflict_sets = None):
    """Renders a lock.bzl file from a resolved lock structure.

    Args:
        lock: The parsed lock.json dict.
        repo_map: A dict mapping file keys to repo labels.
        rctx_name: The name of the package repository.
        variant_resolvers: Optional list of variant_resolver target labels, or
            dict mapping resolver label -> list of item qualified names.
        reset_conflict_sets: The workspace's conflict sets (lists of qualified
            names). When given, packages that don't depend on the variant
            settings install with them reset (see render_reset_bzl).

    Returns:
        A string containing the rendered lock.bzl file.
    """
    packages = lock.get("packages", {})
    cycle_groups = lock.get("cycle_groups", {})

    # Generated code loads from //pycross/private so these rules don't have to be public API.
    pycross_loads = {
        "dist_info.bzl": ["pycross_dist_info"],
        "pep508_evaluator.bzl": ["pycross_pep508_evaluator"],
        "proxy.bzl": ["pycross_library_proxy"],
        "wheel_chooser.bzl": ["pycross_wheel_chooser"],
        "wheel_library.bzl": ["pycross_wheel_library"],
    }
    if cycle_groups:
        pycross_loads["cycle_member_marker_deps.bzl"] = ["pycross_cycle_member_marker_deps"]

    reset_plan = None
    gate_lines = []
    if reset_conflict_sets:
        reset_plan = _compute_reset_plan(packages, repo_map, _conflict_pairs(reset_conflict_sets), gate_lines)
        if not [p for p in reset_plan.values() if p.ok]:
            reset_plan = None
            gate_lines = []

    body_lines = []

    # 1. Marker evaluators for dependency markers (deduped)
    unique_markers = _collect_unique_markers(packages)
    _render_marker_evaluators(body_lines, unique_markers, variant_resolvers = variant_resolvers)

    # 1b. Resolution-marker evaluators for pin forks
    resolution_marker_exprs = lock.get("resolution_marker_exprs", {})
    _render_resolution_marker_evaluators(body_lines, resolution_marker_exprs, variant_resolvers = variant_resolvers)

    # 2. Per-member cycle deps (marker-aware)
    _render_marker_cycle_member_deps(body_lines, cycle_groups, packages, variant_resolvers = variant_resolvers)

    # 2b. Variant reset gates
    body_lines.extend(gate_lines)

    # 3. Packages
    for pkg_key, pkg in sorted(packages.items()):
        _render_marker_package(body_lines, pkg_key, pkg, packages, repo_map, rctx_name, reset_plan = reset_plan)

    # 4. Extras aggregates ([_all_] targets)
    _render_extras_aggregates(body_lines, packages)

    needs_selects = False
    needs_wheel_matched = False
    for line in body_lines:
        if "selects.config_setting_group(" in line:
            needs_selects = True
        elif "pycross_wheel_matched(" in line:
            needs_wheel_matched = True
        if needs_selects and needs_wheel_matched:
            break

    if needs_wheel_matched:
        pycross_loads["wheel_chooser.bzl"].append("pycross_wheel_matched")

    lines = [
        "# This file is generated by rules_pycross.",
        "# It is not intended for manual editing.",
        '"""Pycross-generated dependency targets."""',
        "",
    ] + [
        'load("@rules_pycross//pycross/private:{}", {})'.format(
            bzl,
            ", ".join(['"{}"'.format(sym) for sym in symbols]),
        )
        for bzl, symbols in sorted(pycross_loads.items())
    ]

    if reset_plan:
        lines.append('load(":reset.bzl", "pycross_resettable_wheel_library")')
    if needs_selects:
        lines.append('load("@bazel_skylib//lib:selects.bzl", "selects")')

    lines.extend([
        "",
        "# buildifier: disable=unnamed-macro",
        "def targets():",
        _ind('"""Generated package targets."""'),
        "",
    ])
    lines.extend(body_lines)

    return "\n".join(lines) + "\n"
