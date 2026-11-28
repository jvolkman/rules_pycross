"""Lock graph construction, marker fork detection, local edge expansion, and finalization.

Used by PDM, Poetry, UV, and Pylock Starlark translators.
"""

load("@pypackaging.bzl", "pypackaging")
load(
    ":translator_util.bzl",
    "canonicalize_name",
    "combine_markers",
    "format_raw_lock",
    "record_edge_testonly",
    "record_root_marker",
)
load(
    ":util.bzl",
    "base_package_key",
    "format_package_key",
    "resolution_marker_constraint_name",
)

def find_package_marker_forks(packages, markers_by_pkg = None, allow_unmarked_fallback = False):
    """Find resolution-marker forks (same package name with multiple versions).

    Args:
        packages: Iterable of translated package dicts.
        markers_by_pkg: Optional `{name: {version: marker_expr}}` lookup overriding
            `pkg.get("markers", "")`.
        allow_unmarked_fallback: If True, keep one unmarked version under `""`
            (the default branch) when at least one sibling version has a marker.

    Returns:
        A `(resolution_marker_exprs, forks_by_name)` tuple where
        `resolution_marker_exprs` maps constraint names to PEP 508 marker
        expressions, and `forks_by_name` maps each forked package name to
        `{version: constraint_name}`.
    """
    fork_versions = {}  # {name: {version: marker_expr}}
    for pkg in packages:
        fname = pkg["name"]
        fver = pkg["version"]
        if markers_by_pkg != None:
            marker = markers_by_pkg.get(fname, {}).get(fver, "")
        else:
            marker = pkg.get("markers", "")
        if not marker and not allow_unmarked_fallback:
            continue
        fork_versions.setdefault(fname, {})[fver] = marker

    resolution_marker_exprs = {}
    forks_by_name = {}
    for fname, versions in fork_versions.items():
        if len(versions) <= 1 or not any(versions.values()):
            continue
        version_constraints = {}
        seen_unmarked = False
        for fversion, marker_expr in sorted(versions.items()):
            if not marker_expr:
                if seen_unmarked:
                    continue
                seen_unmarked = True
                version_constraints[fversion] = ""
                continue
            cname = resolution_marker_constraint_name(marker_expr)
            version_constraints[fversion] = cname
            resolution_marker_exprs[cname] = marker_expr
        forks_by_name[fname] = version_constraints

    return resolution_marker_exprs, forks_by_name

def fork_constraints_by_key(forks_by_name):
    """Flatten `{name: {version: constraint_name}}` into `{name@version: constraint_name}`.

    Args:
        forks_by_name: Mapping returned by `find_package_marker_forks`.

    Returns:
        Dict mapping base package key (`name@version`) to its non-empty
        resolution-marker constraint name.
    """
    result = {}
    for fname, ver_map in forks_by_name.items():
        for fver, cname in ver_map.items():
            if cname:
                result[format_package_key(fname, fver)] = cname
    return result

def apply_package_marker_forks(pins, forks_by_name, pin_value_fn = None):
    """Rewrite pins in place for packages that have resolution-marker forks.

    Args:
        pins: Dict of `pin_name -> value`, mutated in place for forked packages.
        forks_by_name: Dict `{package_name: {version: constraint_name}}` returned
            by `find_package_marker_forks`.
        pin_value_fn: Optional `fn(pin_name, version)` producing each conditional
            pin value; defaults to `lambda _pin_name, version: "===" + version`.
    """
    if not forks_by_name:
        return
    for pin_name in list(pins.keys()):
        base_name = pin_name.split("[")[0]
        version_constraints = forks_by_name.get(base_name)
        if not version_constraints:
            continue
        pins[pin_name] = {
            cname: pin_value_fn(pin_name, fversion) if pin_value_fn else "===" + fversion
            for fversion, cname in version_constraints.items()
        }

def detect_package_marker_forks(
        packages,
        pins,
        markers_by_pkg = None,
        pin_value_fn = None,
        allow_unmarked_fallback = False):
    """Detect resolution-marker forks (same package name with multiple versions) and update pins.

    Args:
        packages: Iterable of translated package dicts.
        pins: Dict of `pin_name -> value`, mutated in place for forked packages.
        markers_by_pkg: Optional `{name: {version: marker_expr}}` lookup overriding
            `pkg.get("markers", "")`.
        pin_value_fn: Optional `fn(pin_name, version)` producing each conditional
            pin value; defaults to `lambda _pin_name, version: "===" + version`.
        allow_unmarked_fallback: If True, keep one unmarked version under `""`
            (the default branch) when at least one sibling version has a marker.

    Returns:
        Dict of constraint_name -> PEP 508 marker expression string.
    """
    resolution_marker_exprs, forks_by_name = find_package_marker_forks(
        packages,
        markers_by_pkg = markers_by_pkg,
        allow_unmarked_fallback = allow_unmarked_fallback,
    )
    apply_package_marker_forks(pins, forks_by_name, pin_value_fn = pin_value_fn)
    return resolution_marker_exprs

def _parse_specifier_parts(specifier_str):
    """Pre-parse a specifier string (possibly with `||` unions) once for repeated checks.

    Returns None when the specifier matches any version, otherwise a list of
    `pypackaging.specifiers` SpecifierSet structs.
    """
    if not specifier_str or specifier_str == "*":
        return None
    parts = []
    for part in specifier_str.split("||"):
        part = part.strip()
        if not part or part == "*":
            return None
        parts.append(pypackaging.specifiers.parse_set(part))
    return parts

def _parsed_specifier_contains_version(parsed_parts, version_str):
    """Check whether `version_str` satisfies pre-parsed specifier parts."""
    if parsed_parts == None:
        return True
    for spec_set in parsed_parts:
        if pypackaging.specifiers.set_contains(spec_set, version_str):
            return True
    return False

def _version_key(version_str):
    """Parse a version string into a comparable key tuple."""
    return pypackaging.version.parse(version_str).key

def _cand_fork_marker(cand, fork_constraints, resolution_marker_exprs):
    """Return a candidate package's resolution marker expression, or empty string."""
    marker = cand.get("markers", "")
    if marker:
        return marker
    if not fork_constraints:
        return ""
    base_key = format_package_key(cand["name"].split("[")[0], cand["version"], tag = cand.get("tag", ""))
    cname = fork_constraints.get(base_key)
    if not cname:
        return ""
    expr = resolution_marker_exprs.get(cname)
    return expr if type(expr) == "string" else ""

def _resolve_candidates(
        candidates,
        parsed_spec,
        dep_marker,
        resolution_marker_exprs,
        fork_constraints = None,
        req_extra = "",
        cand_extras_by_key = None,
        break_on_first = True,
        dep_source_id = ""):
    """Return matching `(candidate, combined_marker)` pairs from `candidates`.

    For resolution-marker forked packages (multiple marked versions or sources
    without an unambiguous exact `===` pin), emits every matching candidate
    gated by its package-level marker instead of stopping at the newest version.
    """
    if not candidates:
        return []
    if dep_source_id:
        candidates = [c for c in candidates if c.get("source_id", "") == dep_source_id]
        if not candidates:
            return []
    marked_candidates = [
        True
        for c in candidates
        if _cand_fork_marker(c, fork_constraints, resolution_marker_exprs)
    ]
    is_exact_pin = (
        parsed_spec != None and
        len(parsed_spec) == 1 and
        len(parsed_spec[0].specs) == 1 and
        parsed_spec[0].specs[0].operator == "==="
    )
    matching_version_count = 0
    if is_exact_pin and not dep_source_id:
        for c in candidates:
            if _parsed_specifier_contains_version(parsed_spec, c["version"]):
                matching_version_count += 1
    is_forked = len(marked_candidates) > 1 and (not is_exact_pin or matching_version_count > 1)

    matches = []
    for cand in candidates:
        if req_extra:
            cand_key = format_package_key(cand["name"], cand["version"], tag = cand.get("tag", ""))
            if req_extra not in cand_extras_by_key.get(cand_key, {}):
                continue
        if not _parsed_specifier_contains_version(parsed_spec, cand["version"]):
            continue
        edge_marker = dep_marker
        if is_forked:
            cand_marker = _cand_fork_marker(cand, fork_constraints, resolution_marker_exprs)
            edge_marker = combine_markers(dep_marker, cand_marker)
        matches.append((cand, edge_marker))
        if break_on_first and not is_forked:
            break
    return matches

def _resolve_with_extra_fallback(
        packages_by_name,
        name,
        parsed_spec,
        marker,
        resolution_marker_exprs,
        fork_constraints = None,
        req_extra = "",
        cand_extras_by_key = None,
        break_on_first = True,
        dep_source_id = ""):
    """Resolve candidates for `name`, falling back from `base[extra]` to `base`.

    Precondition: a bracketed `name` (`base[extra]`) implies `req_extra` is empty or `None`.
    """
    candidates = packages_by_name.get(name, [])
    if candidates:
        matches = _resolve_candidates(
            candidates,
            parsed_spec,
            marker,
            resolution_marker_exprs,
            fork_constraints = fork_constraints,
            req_extra = req_extra,
            cand_extras_by_key = cand_extras_by_key,
            break_on_first = break_on_first,
            dep_source_id = dep_source_id,
        )
        if matches:
            return matches, name

    if "[" in name and not req_extra:
        base_name = name.split("[")[0]
        base_candidates = packages_by_name.get(base_name, [])
        if base_candidates:
            matches = _resolve_candidates(
                base_candidates,
                parsed_spec,
                marker,
                resolution_marker_exprs,
                fork_constraints = fork_constraints,
                break_on_first = break_on_first,
                dep_source_id = dep_source_id,
            )
            return matches, base_name
        return [], base_name

    return [], name

def build_lock_graph(packages, resolution_marker_exprs = None, strict_dependencies = True, fork_constraints = None):
    """Deduplicate packages, index by name, resolve inter-package dependencies, and precompute raw lock packages.

    Args:
        packages: List of package dicts (`name`, `version`, `dependencies`,
            `files`, and optional `is_local`, `extras`, `markers`,
            `source_dir`, `tag`, `source_id`, `source`).
        resolution_marker_exprs: Optional dict mapping constraint names to PEP
            508 marker expressions (used for resolution-marker fork expansion).
        strict_dependencies: If True, fail when a dependency matches no package.
        fork_constraints: Optional dict mapping base package keys (`name@version[~tag]`)
            to their resolution-marker constraint names.

    Returns:
        Struct with `distinct_packages`, `packages_by_name`, `resolved_deps`,
        `resolution_marker_exprs`, `fork_constraints`, and `lock_packages`.
    """
    if resolution_marker_exprs == None:
        resolution_marker_exprs = {}
    if fork_constraints == None:
        fork_constraints = {}

    # Deduplicate: merge packages with same key.
    distinct_packages = {}
    for pkg in packages:
        pkg_key = format_package_key(pkg["name"], pkg["version"], tag = pkg.get("tag", ""))
        if pkg_key not in distinct_packages:
            distinct_packages[pkg_key] = pkg
            continue

        # Merge: combine deps, files, and extras.
        existing = distinct_packages[pkg_key]
        merged_deps = list(existing["dependencies"])
        existing_dep_keys = {
            (
                d["name"],
                d.get("specifier", ""),
                d.get("marker", ""),
                d.get("source_id", ""),
                tuple(sorted([e for e in (d.get("extras") or []) if e])),
            ): True
            for d in merged_deps
        }
        for d in pkg["dependencies"]:
            dk = (
                d["name"],
                d.get("specifier", ""),
                d.get("marker", ""),
                d.get("source_id", ""),
                tuple(sorted([e for e in (d.get("extras") or []) if e])),
            )
            if dk not in existing_dep_keys:
                merged_deps.append(d)
                existing_dep_keys[dk] = True
        merged_files = list(existing["files"])
        existing_file_names = {f["name"]: True for f in merged_files}
        for f in pkg["files"]:
            if f["name"] not in existing_file_names:
                merged_files.append(f)
                existing_file_names[f["name"]] = True
        merged_extras = list(existing.get("extras", []))
        for e in pkg.get("extras", []):
            if e not in merged_extras:
                merged_extras.append(e)
        distinct_packages[pkg_key] = dict(
            existing,
            dependencies = merged_deps,
            files = merged_files,
            extras = merged_extras,
            is_local = existing.get("is_local", False) or pkg.get("is_local", False),
        )

    all_packages = distinct_packages.values()

    # Group by canonical name and sort newest first.
    packages_by_name = {}
    for pkg in all_packages:
        packages_by_name.setdefault(pkg["name"], []).append(pkg)
    for name in list(packages_by_name.keys()):
        packages_by_name[name] = sorted(
            packages_by_name[name],
            key = lambda p: (_version_key(p["version"]), p.get("tag", "")),
            reverse = True,
        )

    # Precompute canonicalized extras sets per package key to avoid re-allocating in inner loops.
    cand_extras_by_key = {
        pkg_key: {canonicalize_name(e): True for e in pkg.get("extras", [])}
        for pkg_key, pkg in distinct_packages.items()
        if pkg.get("extras")
    }

    # Resolve inter-package dependencies.
    resolved_deps = {}  # pkg_key -> list of resolved dep dicts
    for pkg in all_packages:
        pkg_key = format_package_key(pkg["name"], pkg["version"], tag = pkg.get("tag", ""))
        pkg_resolved = []

        for dep in pkg["dependencies"]:
            dep_name = canonicalize_name(dep["name"])
            dep_specifier = dep.get("specifier", "")
            dep_marker = dep.get("marker", "")
            dep_source_id = dep.get("source_id", "")
            dep_extras = dep.get("extras", [None]) or [None]

            has_candidates = bool(packages_by_name.get(dep_name)) or (
                "[" in dep_name and bool(packages_by_name.get(dep_name.split("[")[0]))
            )
            parsed_spec = _parse_specifier_parts(dep_specifier) if has_candidates else None

            for req_extra in dep_extras:
                norm_req_extra = canonicalize_name(req_extra) if req_extra else ""
                matches, eff_dep_name = _resolve_with_extra_fallback(
                    packages_by_name,
                    dep_name,
                    parsed_spec,
                    dep_marker,
                    resolution_marker_exprs,
                    fork_constraints = fork_constraints,
                    req_extra = norm_req_extra,
                    cand_extras_by_key = cand_extras_by_key,
                    break_on_first = bool(dep_specifier),
                    dep_source_id = dep_source_id,
                )
                display_name = format_package_key(eff_dep_name, extra = norm_req_extra)
                for cand, edge_marker in matches:
                    entry = {
                        "name": display_name,
                        "version": cand["version"],
                        "marker": edge_marker,
                    }
                    if cand.get("tag"):
                        entry["key"] = format_package_key(display_name, cand["version"], tag = cand["tag"])
                    pkg_resolved.append(entry)
                if not matches and strict_dependencies:
                    fail("Found no packages to satisfy dependency (name={}, spec={})".format(dep_name, dep_specifier))

        resolved_deps[pkg_key] = pkg_resolved

    # Precompute non-local raw lock packages once so finalize_lock_graph reuses them across repos.
    lock_packages = {}
    for pkg in all_packages:
        if pkg.get("is_local", False):
            continue

        pkg_key = format_package_key(pkg["name"], pkg["version"], tag = pkg.get("tag", ""))
        deps = resolved_deps.get(pkg_key, [])
        deps_without_self = [
            d
            for d in deps
            if base_package_key(d.get("key") or format_package_key(d["name"], d["version"])) != pkg_key
        ]
        deps_sorted = sorted(deps_without_self, key = lambda d: (d["name"], d["version"], d.get("key", "")))
        files_sorted = sorted(pkg["files"], key = lambda f: f["name"])

        raw_package = {
            "name": pkg["name"],
            "version": pkg["version"],
            "dependencies": deps_sorted,
            "files": files_sorted,
        }
        if pkg.get("source_dir"):
            raw_package["source_dir"] = pkg["source_dir"]
        if pkg.get("tag") and pkg.get("source"):
            raw_package["source"] = pkg["source"]
        lock_packages[pkg_key] = raw_package

    return struct(
        distinct_packages = distinct_packages,
        packages_by_name = packages_by_name,
        resolved_deps = resolved_deps,
        resolution_marker_exprs = resolution_marker_exprs,
        fork_constraints = fork_constraints,
        lock_packages = lock_packages,
    )

def _local_pkg_key(distinct_packages, pin_name, pkg_key):
    """Return the `distinct_packages` key of `pkg_key` (or its base) if local, else None."""
    if distinct_packages.get(pkg_key, {}).get("is_local", False):
        return pkg_key
    if "[" in pin_name:
        base_key = base_package_key(pkg_key)
        if distinct_packages.get(base_key, {}).get("is_local", False):
            return base_key
    return None

def expand_root_edges(graph, root_edges, strict_dependencies = True, fold_pin_marker = None):
    """Resolve root edges and expand local packages into non-local edges.

    Args:
        graph: Struct returned by `build_lock_graph`.
        root_edges: List of structs with `pin_name`, `specifier`, `constraint`,
            `is_testonly`, `marker`, and optional `source_id`.
        strict_dependencies: If True, fail when a root edge matches no package.
        fold_pin_marker: Optional `fn(constraint, marker)` returning a folded
            marker string or `None` to prune an unsatisfiable edge.

    Returns:
        List of non-local edge structs with `pin_name`, `pkg_key`, `constraint`,
        `is_testonly`, `pin_marker`, `avail_marker`, and `from_local`.
    """
    distinct_packages = graph.distinct_packages
    packages_by_name = graph.packages_by_name
    resolved_deps = graph.resolved_deps
    resolution_marker_exprs = graph.resolution_marker_exprs

    # Queue entries: (pin_name, pkg_key, constraint, is_testonly, pin_marker, avail_marker, from_local, path)
    queue = []
    for edge in root_edges:
        pin_name = edge.pin_name
        specifier = edge.specifier
        constraint = edge.constraint
        is_testonly = edge.is_testonly
        marker = edge.marker
        source_id = getattr(edge, "source_id", "")

        has_candidates = bool(packages_by_name.get(pin_name)) or (
            "[" in pin_name and bool(packages_by_name.get(pin_name.split("[")[0]))
        )
        parsed_spec = _parse_specifier_parts(specifier) if has_candidates else None
        matches, _ = _resolve_with_extra_fallback(
            packages_by_name,
            pin_name,
            parsed_spec,
            marker,
            resolution_marker_exprs,
            fork_constraints = graph.fork_constraints,
            break_on_first = True,
            dep_source_id = source_id,
        )
        if not matches and strict_dependencies:
            fail("Found no packages to satisfy pin (name={}, spec={})".format(pin_name, specifier))
        for cand, edge_marker in matches:
            pin_marker = edge_marker
            if fold_pin_marker != None:
                pin_marker = fold_pin_marker(constraint, pin_marker)
                if pin_marker == None:
                    continue

            # Keep `pin_name` even on base fallback so lock_resolver synthesizes
            # `name[extra]` when no separate extra package exists.
            pkg_key = format_package_key(pin_name, cand["version"], tag = cand.get("tag", ""))
            queue.append((pin_name, pkg_key, constraint, is_testonly, pin_marker, edge_marker, False, ()))

    expanded = []
    expanded_local = {}  # (local_key, constraint, pin_marker, avail_marker) -> is_testonly
    max_steps = max(10000, 20 * len(distinct_packages) + len(queue) + 1)
    head = 0
    for _ in range(max_steps):
        if head >= len(queue):
            break
        pin_name, pkg_key, constraint, is_testonly, pin_marker, avail_marker, from_local, path = queue[head]
        head += 1

        local_key = _local_pkg_key(distinct_packages, pin_name, pkg_key)
        if local_key == None:
            expanded.append(struct(
                pin_name = pin_name,
                pkg_key = pkg_key,
                constraint = constraint,
                is_testonly = is_testonly,
                pin_marker = pin_marker,
                avail_marker = avail_marker,
                from_local = from_local,
            ))
            continue

        if local_key in path:
            continue
        visit_key = (local_key, constraint, pin_marker, avail_marker)
        if visit_key in expanded_local and (is_testonly or not expanded_local[visit_key]):
            continue
        expanded_local[visit_key] = is_testonly
        next_path = path + (local_key,)

        for dep in resolved_deps.get(local_key, []):
            dep_base_name = dep["name"].split("[")[0]
            dep_pin_name = dep["name"]
            dep_key = dep.get("key") or format_package_key(dep_pin_name, dep["version"])
            if dep_key not in distinct_packages:
                dep_pin_name = dep_base_name
                dep_key = base_package_key(dep_key)
            combined_avail = combine_markers(avail_marker, dep["marker"])
            combined_pin = combine_markers(pin_marker, dep["marker"])
            if fold_pin_marker != None:
                combined_pin = fold_pin_marker(constraint, combined_pin)
                if combined_pin == None:
                    continue
            queue.append((dep_pin_name, dep_key, constraint, is_testonly, combined_pin, combined_avail, True, next_path))

    if head < len(queue):
        fail("Local package expansion exceeded step bound")
    return expanded

def finalize_lock_graph(
        graph,
        pinned_keys,
        variants = None,
        resolution_marker_exprs = None,
        testonly_pins = None,
        expanded_testonly_pins = None,
        non_testonly_pins = None,
        root_dependency_markers = None):
    """Compute final testonly pins and serialize a resolved lock graph to raw_lock format.

    Args:
        graph: Struct returned by `build_lock_graph`.
        pinned_keys: Dict mapping pin name -> `{constraint: pkg_key}`.
        variants: Optional list of variant set dicts.
        resolution_marker_exprs: Optional dict mapping constraint names to marker
            expressions or compound dicts.
        testonly_pins: Optional iterable of explicitly testonly pin names.
        expanded_testonly_pins: Optional iterable of pin base names reached as
            testonly only via expanded local packages (cleared if reachable at
            runtime from a non-testonly pin).
        non_testonly_pins: Optional iterable of pin base names reached from
            non-testonly groups.
        root_dependency_markers: Optional dict mapping pin names to list of
            environment marker strings (or None for unconditional).

    Returns:
        A dict in raw_lock.json format.
    """
    distinct_packages = graph.distinct_packages
    resolved_deps = graph.resolved_deps

    testonly_set = {name: True for name in (testonly_pins or [])}
    expanded_testonly = {name: True for name in (expanded_testonly_pins or [])}
    if non_testonly_pins != None:
        non_testonly_set = {name: True for name in non_testonly_pins}
    else:
        non_testonly_set = {}
        for name in pinned_keys.keys():
            base = name.split("[")[0]
            if name not in testonly_set and base not in testonly_set and name not in expanded_testonly and base not in expanded_testonly:
                non_testonly_set[base] = True

    # Packages reachable at runtime from non-testonly pins through third-party
    # dependency edges must not be marked testonly solely because a testonly
    # local member also depends on them. Explicitly listed testonly_pins entries
    # in `testonly_set` are left untouched.
    runtime_reachable = {}
    if expanded_testonly:
        queue = []
        visited = {}
        for pin_name, constraints in pinned_keys.items():
            pin_base = pin_name.split("[")[0]
            if pin_base in non_testonly_set:
                for key in constraints.values():
                    if key not in visited:
                        visited[key] = True
                        queue.append(key)
        head = 0
        for _ in range(len(distinct_packages) + len(queue) + 1):
            if head >= len(queue):
                break
            cur = queue[head]
            head += 1
            for dep in resolved_deps.get(cur, []):
                dep_base = dep["name"].split("[")[0]
                runtime_reachable[dep_base] = True
                raw_dep_key = dep.get("key") or format_package_key(dep["name"], dep["version"])
                for dep_key in (raw_dep_key, base_package_key(raw_dep_key)):
                    if dep_key in distinct_packages and dep_key not in visited:
                        visited[dep_key] = True
                        queue.append(dep_key)

    for name in sorted(expanded_testonly.keys()):
        if name not in non_testonly_set and name not in runtime_reachable and name not in testonly_set:
            testonly_set[name] = True
    final_testonly_pins = sorted([
        name
        for name in testonly_set.keys()
        if (
            name not in non_testonly_set and
            name.split("[")[0] not in non_testonly_set and
            (name in pinned_keys or any([p.split("[")[0] == name for p in pinned_keys.keys()]))
        )
    ])

    return format_raw_lock(
        graph.lock_packages,
        pinned_keys,
        testonly_pins = final_testonly_pins,
        variants = variants,
        resolution_marker_exprs = resolution_marker_exprs,
        root_dependency_markers = root_dependency_markers,
        fork_constraints = graph.fork_constraints,
    )

def resolve_lock_graph(
        packages,
        pinned_package_specs,
        strict_dependencies = True,
        resolution_marker_exprs = None,
        testonly_pins = None,
        root_dependency_markers = None,
        graph = None):
    """Resolve a dependency graph of packages into raw lock data.

    Each package in `packages` should be a dict with `name`, `version`,
    `dependencies`, `files`, and optional `is_local` and `extras`. Each
    `pinned_package_specs` entry maps a dependency name to a dict of
    `{constraint_label: specifier_str}`.

    Args:
        packages: List of package dicts (ignored when `graph` is provided).
        pinned_package_specs: Dict mapping pin name to `{constraint: specifier}`.
        strict_dependencies: If True, fail on unresolved deps.
        resolution_marker_exprs: Optional dict mapping constraint names to PEP 508
            marker expressions for resolution-marker forks. When `graph` is provided
            and this argument is `None`, defaults to `graph.resolution_marker_exprs`;
            if passed explicitly alongside `graph`, it should match
            `graph.resolution_marker_exprs`.
        testonly_pins: Optional list of pin names exclusively reachable from testonly groups.
        root_dependency_markers: Optional dict mapping root pin names (including
            extras) to the list of PEP 508 environment markers on the root
            projects' dependency edges to them.
        graph: Optional precomputed graph struct from `build_lock_graph`. When
            provided, `packages` is ignored.

    Returns:
        A dict in raw_lock.json format.
    """
    if resolution_marker_exprs == None:
        resolution_marker_exprs = graph.resolution_marker_exprs if graph != None else {}
    if graph == None:
        graph = build_lock_graph(
            packages,
            resolution_marker_exprs = resolution_marker_exprs,
            strict_dependencies = strict_dependencies,
        )

    testonly_set = {name: True for name in (testonly_pins or [])}
    input_markers = {
        name: markers
        for name, markers in (root_dependency_markers or {}).items()
        if markers != None
    }
    root_edges = []
    for pin_name, pin_specs in pinned_package_specs.items():
        base = pin_name.split("[")[0]
        is_testonly = pin_name in testonly_set or base in testonly_set
        edge_markers = input_markers.get(pin_name) or [""]
        for constraint, specifier in pin_specs.items():
            for marker in edge_markers:
                root_edges.append(struct(
                    pin_name = pin_name,
                    specifier = specifier,
                    constraint = constraint,
                    is_testonly = is_testonly,
                    marker = marker,
                ))

    expanded_edges = expand_root_edges(
        graph,
        root_edges,
        strict_dependencies = strict_dependencies,
    )

    pinned_keys = {}
    final_root_markers = {}
    direct_testonly = {}
    expanded_testonly = {}
    non_testonly = {}
    for edge in expanded_edges:
        base = edge.pin_name.split("[")[0]
        constraint = edge.constraint
        if edge.from_local and not constraint:
            base_key = base_package_key(edge.pkg_key)
            cname = graph.fork_constraints.get(base_key)
            if not cname:
                marker = graph.distinct_packages.get(base_key, {}).get("markers", "")
                if marker:
                    cname = resolution_marker_constraint_name(marker)
            if cname and cname in resolution_marker_exprs:
                constraint = cname
        pinned_keys.setdefault(edge.pin_name, {})[constraint] = edge.pkg_key

        record_root_marker(final_root_markers, edge.pin_name, edge.avail_marker)
        if edge.from_local and edge.pin_name != base:
            record_root_marker(final_root_markers, base, edge.avail_marker)

        record_edge_testonly(
            edge,
            direct_testonly,
            expanded_testonly,
            non_testonly,
            direct_pin_testonly_set = testonly_set,
        )

    return finalize_lock_graph(
        graph,
        pinned_keys,
        resolution_marker_exprs = resolution_marker_exprs,
        testonly_pins = direct_testonly.keys(),
        expanded_testonly_pins = expanded_testonly.keys(),
        non_testonly_pins = non_testonly.keys(),
        root_dependency_markers = final_root_markers,
    )
