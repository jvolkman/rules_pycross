"""Shared Starlark utilities for lock file translators.

Ports resolve_lock_graph and related logic from translator_utils.py.
Used by PDM, Poetry, UV, and Pylock translators.
"""

load("@pypackaging.bzl", "pypackaging")
load(":lock_common.bzl", "read_toml_cached", "sibling_project_file")
load(":util.bzl", "base_package_key", "parse_package_key")

def canonicalize_name(name):
    """Canonicalize a Python package name per PEP 503."""
    return pypackaging.utils.canonicalize_name(name)

def archive_extension(url):
    """Filename suffix for an sdist synthesized from a direct URL.

    The build tooling picks the extractor by suffix, so a .zip archive must keep it.

    Args:
        url: The archive URL.

    Returns:
        ".zip" or ".tar.gz".
    """
    path = url.split("#")[0].split("?")[0]
    return ".zip" if path.lower().endswith(".zip") else ".tar.gz"

def record_root_marker(root_dependency_markers, name, marker):
    """Accumulate the environment markers on a root project dependency.

    A name maps to its root edges' markers, or to None once any unmarked
    (i.e. unconditional) edge is seen.

    Args:
        root_dependency_markers: Dict mapping pin names to list of marker strings or None.
        name: Canonicalized package or extra pin name.
        marker: PEP 508 environment marker string.
    """
    if name in root_dependency_markers and root_dependency_markers[name] == None:
        return
    if not marker:
        root_dependency_markers[name] = None
        return
    existing = root_dependency_markers.get(name, [])
    if marker not in existing:
        root_dependency_markers[name] = existing + [marker]

def resolution_marker_constraint_name(name, version, tag = ""):
    """Generate a deterministic constraint name for a resolution-marker fork.

    Used by both uv and poetry translators when a package has multiple
    versions (or sources at the same version) resolved for different
    environments.

    Args:
        name: Canonical package name.
        version: Package version string.
        tag: Optional disambiguating source tag (omitted when empty).

    Returns:
        A constraint name like "res_numpy_2_3_4" or "res_torch_2_9_1_a1b2c3d4".
    """
    ver = "{}_{}".format(version, tag) if tag else version
    sanitized = (name + "_" + ver).replace("-", "_").replace(".", "_").replace("+", "_").replace("~", "_")
    return "res_{}".format(sanitized)

def sha256_from_string(s):
    """Generate a deterministic hex string from a string input.

    This is a simplistic hash for creating stable cache keys from
    git commit hashes. Not cryptographically secure, but deterministic
    and sufficient for cache keying purposes.

    Args:
        s: The input string.

    Returns:
        A 64-character hex string.
    """

    # Starlark doesn't have hashlib. We use a simple deterministic
    # encoding of the commit as a "hash". Since the commit is already
    # a hex SHA, we can use it directly padded to 64 chars.
    if len(s) >= 64:
        return s[:64]

    # Pad with repeated content
    result = s
    for _ in range(10):
        if len(result) >= 64:
            break
        result = result + s
    return result[:64]

def expand_pep735_group(dev_deps, group_name):
    """Expand a PEP 735 dependency group transitively, resolving `{include-group = ...}` entries.

    Preserves declaration order, allows diamond include DAGs, and fails on
    unknown or cyclic `include-group` references per PEP 735.

    Args:
        dev_deps: Dict mapping group name -> list of PEP 508 strings or `{include-group = ...}` dicts.
        group_name: Name of the group to expand.

    Returns:
        List of PEP 508 requirement strings in declaration order.
    """
    norm_groups = {canonicalize_name(k): v for k, v in dev_deps.items()}
    total_entries = 0
    for entries in norm_groups.values():
        total_entries += len(entries)
    max_iters = 2 * len(norm_groups) + total_entries + 2

    deps = []
    visiting = {}
    visited = {}
    stack = [("enter", canonicalize_name(group_name))]
    for _ in range(max_iters):
        if not stack:
            break
        kind, payload = stack.pop()
        if kind == "dep":
            deps.append(payload)
            continue
        if kind == "exit":
            visiting.pop(payload)
            visited[payload] = True
            continue
        if payload in visiting:
            fail("Circular include-group detected involving dependency group '{}'".format(payload))
        if payload in visited:
            continue
        visiting[payload] = True
        stack.append(("exit", payload))
        entries = norm_groups.get(payload, [])
        for entry in reversed(entries):
            if type(entry) == "string":
                stack.append(("dep", entry))
            elif type(entry) == "dict" and "include-group" in entry:
                inc = canonicalize_name(entry["include-group"])
                if inc not in norm_groups:
                    fail("Dependency group '{}' includes unknown group '{}'".format(payload, entry["include-group"]))
                stack.append(("enter", inc))
    if stack:
        fail("expand_pep735_group exceeded max iterations for group '{}'; this is a bug in pycross".format(group_name))
    return deps

def _read_project_dicts(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Select and decode all matching pyproject.toml files as a list of dicts."""
    sibling_label = sibling_project_file(lock_file)
    if not extra_project_files:
        return [read_toml_cached(rctx, sibling_label, toml_cache) or {}]

    projects = getattr(lock_model, "projects", [])
    if not projects or "*" in projects:
        # Order root/sibling file first (for requires-python and workspace metadata),
        # followed by all other member pyproject.toml files.
        ordered = []
        seen = {}
        if sibling_label in extra_project_files:
            ordered.append(sibling_label)
            seen[sibling_label] = True
        for f in extra_project_files:
            if f not in seen:
                ordered.append(f)
                seen[f] = True
        dicts = []
        for f in ordered:
            p_dict = read_toml_cached(rctx, f, toml_cache)
            if p_dict != None:
                dicts.append(p_dict)
        return dicts or [{}]

    target_names = {canonicalize_name(p): True for p in projects}
    matched = []
    matched_names = {}
    for f in extra_project_files:
        p_dict = read_toml_cached(rctx, f, toml_cache)
        if p_dict == None:
            continue
        p_name = p_dict.get("project", {}).get("name")
        if p_name and canonicalize_name(p_name) in target_names:
            matched.append(p_dict)
            matched_names[canonicalize_name(p_name)] = True
    if matched:
        missing = [p for p in projects if canonicalize_name(p) not in matched_names]
        if missing:
            fail("Project(s) {} not found in workspace pyproject.toml files".format(missing))
        return matched

    project_file = sibling_label if sibling_label in extra_project_files else extra_project_files[0]
    return [read_toml_cached(rctx, project_file, toml_cache) or {}]

def _read_project_dict(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Select and decode the relevant pyproject.toml as a dict.

    A single-project repo reads its member's pyproject.toml; multi-project and
    wildcard repos read the root/sibling pyproject.toml (used e.g. by uv for
    workspace-level `default-groups`).
    """
    sibling_label = sibling_project_file(lock_file)
    if not extra_project_files:
        return read_toml_cached(rctx, sibling_label, toml_cache) or {}

    projects = getattr(lock_model, "projects", [])
    if len(projects) == 1 and projects[0] != "*":
        target_name = canonicalize_name(projects[0])
        for f in extra_project_files:
            p_dict = read_toml_cached(rctx, f, toml_cache)
            if p_dict == None:
                continue
            p_name = p_dict.get("project", {}).get("name")
            if p_name and canonicalize_name(p_name) == target_name:
                return p_dict

    project_file = sibling_label if sibling_label in extra_project_files else extra_project_files[0]
    return read_toml_cached(rctx, project_file, toml_cache) or {}

def _read_lock_dict(rctx, lock_file, lock_label_hint, toml_cache = None):
    lock_dict = read_toml_cached(rctx, lock_file, toml_cache)
    if lock_dict == None:
        fail("Lock file not found: {}. Ensure {} exists at the expected location.".format(lock_file, lock_label_hint))
    return lock_dict

def read_projects_and_lock(rctx, extra_project_files, lock_file, lock_model, lock_label_hint, toml_cache = None):
    """Select and decode all matching pyproject.toml files and the lock file.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of pyproject.toml labels.
        lock_file: The lock file label.
        lock_model: Struct with lock model attributes (including optional `projects`).
        lock_label_hint: Human-readable lock file name for error messages (e.g. "pdm.lock").
        toml_cache: Optional dict caching decoded TOML files by label.

    Returns:
        A tuple of (project_dicts, lock_dict).
    """
    project_dicts = _read_project_dicts(rctx, extra_project_files, lock_file, lock_model, toml_cache)
    return project_dicts, _read_lock_dict(rctx, lock_file, lock_label_hint, toml_cache)

def read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, lock_label_hint, toml_cache = None):
    """Select and decode pyproject.toml and the lock file.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of pyproject.toml labels.
        lock_file: The lock file label.
        lock_model: Struct with lock model attributes (including optional `projects`).
        lock_label_hint: Human-readable lock file name for error messages (e.g. "uv.lock").
        toml_cache: Optional dict caching decoded TOML files by label.

    Returns:
        A tuple of (project_dict, lock_dict).
    """
    project_dict = _read_project_dict(rctx, extra_project_files, lock_file, lock_model, toml_cache)
    return project_dict, _read_lock_dict(rctx, lock_file, lock_label_hint, toml_cache)

def detect_package_marker_forks(packages, pinned_package_specs):
    """Detect resolution-marker forks (same package name with multiple marked versions) and update pins.

    Args:
        packages: List of translated package dicts.
        pinned_package_specs: Dict of pin_name -> specifier, mutated in place for forked packages.

    Returns:
        Dict of constraint_name -> PEP 508 marker expression string.
    """
    resolution_marker_exprs = {}
    fork_versions = {}  # {name: {version: marker_expr}}
    for pkg in packages:
        marker = pkg.get("markers", "")
        if not marker:
            continue
        fork_versions.setdefault(pkg["name"], {})[pkg["version"]] = marker

    for fname, versions in fork_versions.items():
        if len(versions) <= 1:
            continue
        conditional_pins = {}
        for fversion, marker_expr in versions.items():
            cname = resolution_marker_constraint_name(fname, fversion)
            conditional_pins[cname] = "===" + fversion
            resolution_marker_exprs[cname] = marker_expr
        for pin_name in list(pinned_package_specs.keys()):
            if pin_name == fname or pin_name.startswith(fname + "["):
                pinned_package_specs[pin_name] = conditional_pins

    return resolution_marker_exprs

def parse_pep508_requirement(req_str):
    """Parses a PEP 508 requirement string into components.

    Handles formats like:
        "requests>=2.23.0,<3.0.0"
        "requests (>=2.23.0,<3.0.0)"
        "requests[security]>=2.0; python_version >= '3.6'"
        "urllib3<3,>=1.21.1"

    Args:
        req_str: The PEP 508 requirement string.

    Returns:
        A struct with name, extras (list), specifier (string), marker (string).
    """
    req_str = req_str.strip()

    # Strip editable markers (PDM legacy)
    if req_str.startswith("-e "):
        req_str = req_str[3:].strip()

    parsed = pypackaging.requirements.parse(req_str)

    # Reconstruct specifier string
    specifier_str = ""
    if parsed.specifier and parsed.specifier.specs:
        specifier_str = ",".join(["{}{}".format(s.operator, s.version) for s in parsed.specifier.specs])

    return struct(
        name = parsed.name,
        extras = parsed.extras,
        specifier = specifier_str,
        marker = parsed.marker_str or "",
    )

def _dependency_name_str(name, extra = ""):
    """Format a dependency name with optional extra."""
    if extra:
        return "{}[{}]".format(name, extra)
    return name

def _package_key_str(name, version, tag = ""):
    """Format a package key string (with optional `~tag` source qualifier)."""
    if tag:
        return "{}@{}~{}".format(name, version, tag)
    return "{}@{}".format(name, version)

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
    """Check whether version_str satisfies pre-parsed specifier parts."""
    if parsed_parts == None:
        return True
    for spec_set in parsed_parts:
        if pypackaging.specifiers.set_contains(spec_set, version_str):
            return True
    return False

def _version_key(version_str):
    """Parse a version string into a comparable key tuple."""
    return pypackaging.version.parse(version_str).key

def combine_markers(parent_marker, dep_marker):
    """AND two PEP 508 marker strings, simplifying empty or identical sides.

    Args:
        parent_marker: Outer marker string (may be `""`).
        dep_marker: Inner dependency marker string (may be `""`).

    Returns:
        Combined PEP 508 marker string.
    """
    if not parent_marker:
        return dep_marker
    if not dep_marker or parent_marker == dep_marker:
        return parent_marker
    return "({}) and ({})".format(parent_marker, dep_marker)

def _resolve_candidates(
        candidates,
        parsed_spec,
        dep_marker,
        resolution_marker_exprs,
        req_extra = "",
        cand_extras_by_key = None,
        break_on_first = True,
        dep_source_id = ""):
    """Return matching `(candidate, combined_marker)` pairs from `candidates`.

    For resolution-marker forked packages (multiple marked versions/sources and
    not an unambiguous exact `===` pin), emits every matching candidate gated by
    its package-level marker instead of stopping at the newest version.
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
        if c.get("markers") or resolution_marker_constraint_name(c["name"].split("[")[0], c["version"], c.get("tag", "")) in resolution_marker_exprs
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
            cand_key = _package_key_str(cand["name"], cand["version"], cand.get("tag", ""))
            if req_extra not in cand_extras_by_key.get(cand_key, {}):
                continue
        if not _parsed_specifier_contains_version(parsed_spec, cand["version"]):
            continue
        edge_marker = dep_marker
        if is_forked:
            cand_marker = cand.get("markers", "")
            if not cand_marker:
                cname = resolution_marker_constraint_name(cand["name"].split("[")[0], cand["version"], cand.get("tag", ""))
                expr = resolution_marker_exprs.get(cname)
                if type(expr) == "string":
                    cand_marker = expr
            edge_marker = combine_markers(dep_marker, cand_marker)
        matches.append((cand, edge_marker))
        if break_on_first and not is_forked:
            break
    return matches

def build_lock_graph(packages, resolution_marker_exprs = None, strict_dependencies = True):
    """Deduplicate packages, index by name, and resolve inter-package dependencies.

    Args:
        packages: List of package dicts (`name`, `version`, `dependencies`,
            `files`, `python_versions`, optional `is_local`, `extras`, `markers`,
            `source_dir`, `tag`, `source_id`, `source`).
        resolution_marker_exprs: Optional dict mapping constraint names to PEP
            508 marker expressions (used for resolution-marker fork expansion).
        strict_dependencies: If True, fail when a dependency matches no package.

    Returns:
        Struct with `distinct_packages`, `packages_by_name`, `resolved_deps`,
        and `resolution_marker_exprs`.
    """
    if resolution_marker_exprs == None:
        resolution_marker_exprs = {}

    # Deduplicate: merge packages with same key
    distinct_packages = {}
    for pkg in packages:
        pkg_key = _package_key_str(pkg["name"], pkg["version"], pkg.get("tag", ""))
        if pkg_key not in distinct_packages:
            distinct_packages[pkg_key] = pkg
            continue

        # Merge: combine deps, files, extras
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

    # Resolve dependencies
    resolved_deps = {}  # pkg_key -> list of resolved dep dicts
    for pkg in all_packages:
        pkg_key = _package_key_str(pkg["name"], pkg["version"], pkg.get("tag", ""))
        pkg_resolved = []

        for dep in pkg["dependencies"]:
            dep_name = canonicalize_name(dep["name"])
            dep_specifier = dep.get("specifier", "")
            dep_marker = dep.get("marker", "")
            dep_source_id = dep.get("source_id", "")
            dep_extras = dep.get("extras", [None]) or [None]

            candidates = packages_by_name.get(dep_name, [])
            resolved_dep_name = dep_name
            if not candidates and "[" in dep_name:
                resolved_dep_name = dep_name.split("[")[0]
                candidates = packages_by_name.get(resolved_dep_name, [])
            parsed_spec = _parse_specifier_parts(dep_specifier) if candidates else None

            for req_extra in dep_extras:
                norm_req_extra = canonicalize_name(req_extra) if req_extra else ""
                display_name = _dependency_name_str(resolved_dep_name, norm_req_extra)
                matches = _resolve_candidates(
                    candidates,
                    parsed_spec,
                    dep_marker,
                    resolution_marker_exprs,
                    req_extra = norm_req_extra,
                    cand_extras_by_key = cand_extras_by_key,
                    break_on_first = bool(dep_specifier),
                    dep_source_id = dep_source_id,
                )
                for cand, edge_marker in matches:
                    entry = {
                        "name": display_name,
                        "version": cand["version"],
                        "marker": edge_marker,
                    }
                    if cand.get("tag"):
                        entry["key"] = _package_key_str(display_name, cand["version"], cand["tag"])
                    pkg_resolved.append(entry)
                if not matches and strict_dependencies:
                    fail("Found no packages to satisfy dependency (name={}, spec={})".format(dep_name, dep_specifier))

        resolved_deps[pkg_key] = pkg_resolved

    return struct(
        distinct_packages = distinct_packages,
        packages_by_name = packages_by_name,
        resolved_deps = resolved_deps,
        resolution_marker_exprs = resolution_marker_exprs,
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

        pin_packages = packages_by_name.get(pin_name)
        key_name = None
        if pin_packages == None and "[" in pin_name:
            # No separate name[extra] package (e.g. Poetry or empty extra): pin
            # the base version; lock_resolver synthesizes name[extra] if needed.
            pin_packages = packages_by_name.get(pin_name.split("[")[0])
            key_name = pin_name
        pin_packages = pin_packages or []
        parsed_spec = _parse_specifier_parts(specifier) if pin_packages else None
        matches = _resolve_candidates(
            pin_packages,
            parsed_spec,
            marker,
            resolution_marker_exprs,
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
            pkg_key = _package_key_str(key_name or cand["name"], cand["version"], cand.get("tag", ""))
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
            dep_key = dep.get("key") or _package_key_str(dep_pin_name, dep["version"])
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
        requires_python,
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
        requires_python: The requires-python specifier string.
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
    if variants == None:
        variants = []
    if resolution_marker_exprs == None:
        resolution_marker_exprs = {}

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
                raw_dep_key = dep.get("key") or _package_key_str(dep["name"], dep["version"])
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

    # Build output packages, skipping local workspace/path members.
    lock_packages = {}
    for pkg in distinct_packages.values():
        if pkg.get("is_local", False):
            continue

        pkg_key = _package_key_str(pkg["name"], pkg["version"], pkg.get("tag", ""))
        deps = resolved_deps.get(pkg_key, [])
        deps_without_self = [
            d
            for d in deps
            if base_package_key(d.get("key") or _package_key_str(d["name"], d["version"])) != pkg_key
        ]
        deps_sorted = sorted(deps_without_self, key = lambda d: (d["name"], d["version"], d.get("key", "")))
        files_sorted = sorted(pkg["files"], key = lambda f: f["name"])

        raw_package = {
            "name": pkg["name"],
            "version": pkg["version"],
            "python_versions": pkg.get("python_versions", ""),
            "dependencies": deps_sorted,
            "files": files_sorted,
        }
        if pkg.get("source_dir"):
            raw_package["source_dir"] = pkg["source_dir"]
        if pkg.get("tag") and pkg.get("source"):
            raw_package["source"] = pkg["source"]
        lock_packages[pkg_key] = raw_package

    # Simplify pins: if a pin has only one constraint with key "", flatten it.
    simplified_pins = {}
    for name, constraints in pinned_keys.items():
        keys = sorted(constraints.keys())
        if keys == [""]:
            simplified_pins[name] = constraints[""]
        else:
            simplified_pins[name] = constraints

    result = {
        "packages": lock_packages,
        "pins": simplified_pins,
        "python_versions": requires_python,
        "testonly_pins": final_testonly_pins,
    }
    if variants:
        result["variants"] = variants
    if resolution_marker_exprs:
        result["resolution_marker_exprs"] = resolution_marker_exprs

    filtered_markers = {
        name: markers
        for name, markers in (root_dependency_markers or {}).items()
        if markers != None
    }
    if filtered_markers:
        result["root_dependency_markers"] = filtered_markers

    return result

def _resolve_local_dep_constraint(constraint, dep_base_name, dep_version, resolution_marker_exprs, dep_tag = ""):
    """Combine a local package pin's constraint with any resolution-marker fork on its dependency."""
    cname = resolution_marker_constraint_name(dep_base_name, dep_version, dep_tag)
    if cname not in resolution_marker_exprs or constraint == cname:
        return constraint
    if not constraint:
        return cname
    if type(resolution_marker_exprs.get(constraint)) == "string":
        return constraint
    dep_constraint = "{}_{}".format(constraint, cname)
    resolution_marker_exprs[dep_constraint] = {
        "variant": constraint,
        "marker": cname,
    }
    return dep_constraint

def resolve_lock_graph(packages, pinned_package_specs, requires_python, strict_dependencies = True, variants = None, resolution_marker_exprs = None, testonly_pins = None, root_dependency_markers = None):
    """Resolves a dependency graph of packages.

    Ports translator_utils.py resolve_lock_graph() to Starlark.

    Each package in the packages list should be a dict with:
        - name: canonicalized package name
        - version: version string
        - dependencies: list of dicts {name, specifier, marker, extras}
        - files: list of dicts {name, sha256, urls?}
        - python_versions: requires-python specifier string
        - is_local: bool (optional, default False)
        - extras: list of extra names (optional)

    Each pinned_package_specs entry maps a dependency name (str) to
    a dict of {constraint_label: specifier_str}.

    Args:
        packages: List of package dicts.
        pinned_package_specs: Dict mapping pin name to {constraint: specifier}.
        requires_python: The requires-python specifier string.
        strict_dependencies: If True, fail on unresolved deps.
        variants: List of variant set dicts (optional).
        resolution_marker_exprs: Dict mapping constraint names to PEP 508
            marker expressions (optional). Used for resolution-marker forks.
        testonly_pins: List of pin names that are exclusively reachable from testonly groups.
        root_dependency_markers: Dict mapping root pin names (including
            extras) to the list of PEP 508 environment markers on the root
            projects' dependency edges to them (optional). Only pins that are
            exclusively requested under markers appear here.

    Returns:
        A dict in raw_lock.json format.
    """
    if resolution_marker_exprs == None:
        resolution_marker_exprs = {}
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
        if edge.from_local:
            edge_parts = parse_package_key(edge.pkg_key)
            constraint = _resolve_local_dep_constraint(
                constraint,
                base,
                edge_parts.version,
                resolution_marker_exprs,
                dep_tag = edge_parts.tag,
            )
        pinned_keys.setdefault(edge.pin_name, {})[constraint] = edge.pkg_key

        record_root_marker(final_root_markers, edge.pin_name, edge.avail_marker)
        if edge.from_local and edge.pin_name != base:
            record_root_marker(final_root_markers, base, edge.avail_marker)

        if edge.is_testonly:
            if edge.from_local:
                expanded_testonly[base] = True
            else:
                direct_testonly[edge.pin_name] = True
                if base in testonly_set:
                    direct_testonly[base] = True
        else:
            non_testonly[base] = True

    return finalize_lock_graph(
        graph,
        pinned_keys,
        requires_python = requires_python,
        variants = variants,
        resolution_marker_exprs = resolution_marker_exprs,
        testonly_pins = direct_testonly.keys(),
        expanded_testonly_pins = expanded_testonly.keys(),
        non_testonly_pins = non_testonly.keys(),
        root_dependency_markers = final_root_markers,
    )

# Prefixes accepted in dependency_groups entries ('<kind>:<name>' or '<kind>:*').
_GROUP_KINDS = ["optional", "group"]

def compute_requested_dependency_groups(
        dependency_groups,
        testonly_groups,
        non_testonly_groups,
        wildcard_testonly,
        available_groups,
        project_name = None,
        allow_missing = False):
    """Compute the definitive list of requested dependency groups and their testonly status.

    Processes wildcard group expansions and applies last-wins testonly resolution
    to construct the final dictionary of requested groups.

    Wildcard rules:
    - '*' expands to all entries in available_groups
    - 'kind:*' (e.g. 'optional:*', 'group:*') expands to all entries with that prefix

    Args:
        dependency_groups: List of requested dependency group specs (from lock_model).
        testonly_groups: List of dependency groups explicitly marked testonly.
        non_testonly_groups: List of dependency groups explicitly marked non-testonly.
        wildcard_testonly: Boolean indicating if the wildcard default is testonly.
        available_groups: List of fully-prefixed available group names
            (e.g. ["optional:extras1", "group:dev", "group:test"]).
        project_name: Optional project name for error messages.
        allow_missing: If True, skip requested groups that aren't in available_groups
            instead of failing (for repos spanning several projects, where a group only
            needs to exist in one of them).

    Returns:
        A dictionary mapping the group identifier (e.g. "optional:foo", "group:dev")
        to a boolean indicating whether it is testonly.
    """
    available_set = {g: True for g in available_groups}

    include_all = "*" in dependency_groups
    effective_groups = list(available_set.keys()) if include_all else dependency_groups

    requested = {}

    for group in effective_groups:
        kind, sep, name = group.partition(":")
        kind_wildcard = kind + ":*" if sep and kind in _GROUP_KINDS else ""
        if group in testonly_groups:
            is_testonly = True
        elif group in non_testonly_groups:
            is_testonly = False
        elif kind_wildcard and kind_wildcard in testonly_groups:
            is_testonly = True
        elif kind_wildcard and kind_wildcard in non_testonly_groups:
            is_testonly = False
        else:
            is_testonly = wildcard_testonly

        if not sep or kind not in _GROUP_KINDS:
            if group not in available_set:
                fail("Unknown dependency group '{}'. Expected '*', 'default', 'transitive', or one of: {}.".format(
                    group,
                    ", ".join(["'{}:<name>'".format(k) for k in _GROUP_KINDS]),
                ))
            requested[group] = is_testonly
            continue

        if name == "*":
            # Expand kind:* to all available groups with this prefix.
            prefix = kind + ":"
            targets = [g for g in available_set if g.startswith(prefix)]
        else:
            targets = [group]

        for target in targets:
            if target not in available_set:
                if allow_missing:
                    continue
                if project_name:
                    fail("Project '{}' does not have group '{}'.".format(project_name, target))
                fail("Dependency group '{}' not found.".format(target))

            requested[target] = is_testonly

    return requested

# Visible for testing
read_project_dict_for_testing = _read_project_dict
read_project_dicts_for_testing = _read_project_dicts
