"""Starlark pylock (PEP 751) translator.

Replaces the Python pylock_translator.py with a pure-Starlark implementation.
Parses pylock.toml files and produces the raw_lock.json structure consumed by
lock_resolver.bzl.
"""

load("@pypackaging.bzl", "pypackaging")
load(
    ":translator_common.bzl",
    "archive_extension",
    "canonicalize_name",
    "compute_requested_dependency_groups",
    "expand_pep735_group",
    "parse_pep508_requirement",
    "read_project_and_lock",
    "record_root_marker",
    "resolution_marker_constraint_name",
    "sha256_from_string",
)
load(":util.bzl", "parse_package_key", "url_filename")

_INVERT_OP = {
    "==": "!=",
    "!=": "==",
    "<": ">=",
    ">=": "<",
    ">": "<=",
    "<=": ">",
    "in": "not in",
    "not in": "in",
}

# Only PEP 440 version variables have total ordering where `<` <-> `>=` and
# `>` <-> `<=` are complements (string comparisons `<`/`>` are always False).
_VERSION_VARS = {
    "implementation_version": True,
    "platform_release": True,
    "python_full_version": True,
    "python_version": True,
}

_EMPTY_SELECTION_ENV = {"dependency_groups": [], "extras": []}

def _collect_selection_names(parsed):
    """Collect string values compared with `in` against `dependency_groups` or `extras`."""
    groups = {}
    extras = {}
    stack = [parsed]
    for _ in range(1 << 16):
        if not stack:
            break
        node = stack.pop()
        for item in node:
            if type(item) == "list":
                stack.append(item)
            elif type(item) == "tuple":
                lhs, op, rhs = item
                if op != "in":
                    continue
                if rhs.type == "variable" and lhs.type == "string":
                    if rhs.value == "dependency_groups":
                        groups[lhs.value] = True
                    elif rhs.value == "extras":
                        extras[lhs.value] = True
    return sorted(groups.keys()), sorted(extras.keys())

def _selection_env(requested_groups):
    dep_groups = []
    req_extras = []
    for g in requested_groups:
        if g == "default":
            dep_groups.append("default")
        elif g.startswith("group:"):
            dep_groups.append(g[len("group:"):])
        elif g.startswith("optional:"):
            req_extras.append(g[len("optional:"):])
    return {"dependency_groups": dep_groups, "extras": req_extras}

def _strip_selection_markers(marker, requested_groups = None):
    """Prune PEP 751 selection markers (`dependency_groups`, `extras`) using pypackaging.markers.

    Args:
        marker: A marker string, e.g. 'python_version < "3.10" and "default" in dependency_groups'.
        requested_groups: Optional iterable/dict of requested group specs ("default", "group:<g>",
            "optional:<e>"). When provided, selection terms are partially evaluated against them
            and False is returned as None (marker cannot match any requested group).

    Returns:
        An environment-only marker string ("" if unconditional), or None if excluded by
        `requested_groups`.
    """
    if not marker:
        return ""
    if "dependency_groups" not in marker and "extras" not in marker:
        return marker
    parsed = pypackaging.markers.parse(marker)
    if requested_groups != None:
        env = _selection_env(requested_groups)
    else:
        # Standalone lockfile with no pyproject.toml: assume all positively
        # referenced selection names are active so selection terms drop out.
        dep_groups, req_extras = _collect_selection_names(parsed)
        env = {"dependency_groups": dep_groups, "extras": req_extras}
    res = pypackaging.markers.evaluate_partial(parsed, env)
    if res == False:
        return None if requested_groups != None else ""
    if res == True:
        return ""
    return pypackaging.markers.to_string(res)

def _selects_requested_group(marker, requested_groups):
    """Whether a marker's selection terms positively match at least one requested group."""
    if not marker or ("dependency_groups" not in marker and "extras" not in marker):
        return False
    parsed = pypackaging.markers.parse(marker)
    req_res = pypackaging.markers.evaluate_partial(parsed, _selection_env(requested_groups))
    if req_res == False:
        return False
    empty_res = pypackaging.markers.evaluate_partial(parsed, _EMPTY_SELECTION_ENV)
    return req_res != empty_res

def _invert_marker_ast(marker):
    """Negate a PEP 508 marker via De Morgan's laws into a marker AST node, or return None."""
    if not marker:
        return None
    parsed = pypackaging.markers.parse(marker)
    if not parsed:
        return None

    stack = [("visit", parsed)]
    results = []
    for _ in range(1 << 16):
        if not stack:
            break
        kind, payload = stack.pop()
        if kind == "visit":
            if type(payload) == "tuple":
                lhs, op, rhs = payload
                inv = _INVERT_OP.get(op)
                if not inv:
                    return None
                if op in ("<", "<=", ">", ">="):
                    is_ver = (
                        (lhs.type == "variable" and lhs.value in _VERSION_VARS) or
                        (rhs.type == "variable" and rhs.value in _VERSION_VARS)
                    )
                    if not is_ver:
                        return None
                results.append((lhs, inv, rhs))
            elif type(payload) == "list":
                or_terms = []
                cur = []
                for elem in payload:
                    if elem == "or":
                        or_terms.append(cur)
                        cur = []
                    elif elem != "and":
                        cur.append(elem)
                if cur:
                    or_terms.append(cur)
                if not or_terms:
                    return None
                stack.append(("combine_or", len(or_terms)))
                for term in reversed(or_terms):
                    if not term:
                        return None
                    stack.append(("combine_and", len(term)))
                    for atom in reversed(term):
                        stack.append(("visit", atom))
            else:
                return None
        elif kind == "combine_and":
            # NOT (A1 and A2 ...) = (NOT A1) or (NOT A2) ...
            parts = []
            for _ in range(payload):
                parts.append(results.pop())
            parts = list(reversed(parts))
            if len(parts) == 1:
                results.append(parts[0])
            else:
                node = []
                for i, p in enumerate(parts):
                    if i > 0:
                        node.append("or")
                    node.append(p)
                results.append(node)
        elif kind == "combine_or":
            # NOT (T1 or T2 ...) = (NOT T1) and (NOT T2) ...
            parts = []
            for _ in range(payload):
                parts.append(results.pop())
            parts = list(reversed(parts))
            if len(parts) == 1:
                results.append(parts[0])
            else:
                node = []
                for i, p in enumerate(parts):
                    if i > 0:
                        node.append("and")
                    node.append(p)
                results.append(node)

    if len(results) != 1:
        return None
    return results[0]

def _combine_markers(m1, m2):
    if m1 and m2:
        return m1 if m1 == m2 else "({}) and ({})".format(m1, m2)
    return m1 or m2

def _set_dependencies(pkg, updates):
    """Replace or append dependency entries in one pass, preserving order."""
    updated_keys = {(d["name"], d["version"]): True for d in updates}
    pkg["dependencies"] = [
        d
        for d in pkg["dependencies"]
        if (d["name"], d["version"]) not in updated_keys
    ] + updates

def _link_through_hub(lock_packages, versions_all):
    """Ties a graphless lock into a single dependency cycle.

    Graphless locks (pip lock, uv export) describe one environment: every
    package is installed when its own marker matches. To model that, a hub
    depends on every other package, gated by that package's marker, and every
    package depends on the hub. The resulting cycle lets the cycle machinery
    give any root the full marker-filtered environment.

    The hub is a real unconditional package (always installed, so depending on
    it is exact). If there is none, every package links to every other instead.

    Args:
        lock_packages: {pkg_key: raw_package}, updated in place.
        versions_all: {name: {version: env_marker}}.
    """
    keys = sorted(lock_packages.keys())
    unconditional = [
        k
        for k in keys
        if versions_all[lock_packages[k]["name"]] == {lock_packages[k]["version"]: ""}
    ]
    hubs = unconditional[:1] or keys
    single_hub = len(hubs) == 1
    hub_pkg = lock_packages[hubs[0]] if single_hub else None
    hub_back_dep = [{"name": hub_pkg["name"], "version": hub_pkg["version"], "marker": ""}] if single_hub else None
    for hub in hubs:
        hub_updates = []
        for k in keys:
            if k == hub:
                continue
            pkg = lock_packages[k]
            hub_updates.append({
                "name": pkg["name"],
                "version": pkg["version"],
                "marker": versions_all[pkg["name"]][pkg["version"]],
            })
            if single_hub:
                _set_dependencies(pkg, hub_back_dep)
        _set_dependencies(lock_packages[hub], hub_updates)

def _compute_pylock_requested_groups(project_dict, lock_model):
    if not project_dict:
        return None
    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    testonly_groups = getattr(lock_model, "testonly_groups", [])
    non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
    wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)

    project_section = project_dict.get("project", {})
    optional_deps = project_section.get("optional-dependencies", {})
    dev_deps = project_dict.get("dependency-groups", {})
    project_name = project_section.get("name")

    return compute_requested_dependency_groups(
        dependency_groups = dependency_groups,
        testonly_groups = testonly_groups,
        non_testonly_groups = non_testonly_groups,
        wildcard_testonly = wildcard_testonly,
        available_groups = (
            ["default"] +
            ["optional:" + g for g in optional_deps.keys()] +
            ["group:" + g for g in dev_deps.keys()]
        ),
        project_name = project_name,
    )

def _resolve_pylock_project_pins(project_dict, requested_groups_dict, lock_packages, deps_by_name, pkg_markers, versions_all):
    """Filter lock_packages and compute pins, testonly_pins, and root_dependency_markers."""
    if not project_dict:
        # Default: include all (use first key per name; fork detection below may override)
        pins = {}
        for pkg_key, pkg in lock_packages.items():
            pins.setdefault(pkg["name"], pkg_key)
        return lock_packages, pins, [], {}

    project_section = project_dict.get("project", {})
    optional_deps = project_section.get("optional-dependencies", {})
    dev_deps = project_dict.get("dependency-groups", {})

    root_req_names = []
    testonly_root_req_names = []
    root_dependency_markers = {}

    def handle_dep_str(dep_str, is_testonly):
        req = parse_pep508_requirement(dep_str)
        n = req.name
        pin_names = [n] + ["{}[{}]".format(n, canonicalize_name(extra)) for extra in req.extras]
        for pin_name in pin_names:
            if is_testonly:
                testonly_root_req_names.append(pin_name)
            else:
                root_req_names.append(pin_name)
            record_root_marker(root_dependency_markers, pin_name, req.marker)

    if "default" in requested_groups_dict:
        is_testonly = requested_groups_dict["default"]
        for dep_str in project_section.get("dependencies", []):
            handle_dep_str(dep_str, is_testonly)

    for target_name, entries in optional_deps.items():
        key = "optional:{}".format(target_name)
        if key not in requested_groups_dict:
            continue
        is_testonly = requested_groups_dict[key]
        for entry in entries:
            if type(entry) == "string":
                handle_dep_str(entry, is_testonly)

    for target_name in dev_deps.keys():
        key = "group:{}".format(target_name)
        if key not in requested_groups_dict:
            continue
        is_testonly = requested_groups_dict[key]
        for dep_str in expand_pep735_group(dev_deps, target_name):
            handle_dep_str(dep_str, is_testonly)

    # Deduplicate
    root_package_names = {n: True for n in root_req_names}
    testonly_package_names = {n: True for n in testonly_root_req_names if n not in root_package_names}

    # BFS from all root base package names to find reachable packages
    visited_names = {}
    all_roots = dict(root_package_names)
    all_roots.update(testonly_package_names)
    root_base_names = {parse_package_key(n).name: True for n in all_roots.keys()}
    queue = sorted(root_base_names.keys())
    enqueued = dict(root_base_names)
    head = 0

    # Starlark has no while loop, simulate with for+range.
    # Each unique package name is enqueued at most once; upper bound is initial roots + edges.
    total_edges = 0
    for pkg_key in lock_packages:
        total_edges += len(lock_packages[pkg_key].get("dependencies", []))
    max_iter = total_edges + len(queue) + 1
    for _ in range(max_iter):
        if head >= len(queue):
            break
        curr = queue[head]
        head += 1
        visited_names[curr] = True

        for pkg_key in deps_by_name.get(curr, []):
            if pkg_key not in lock_packages:
                continue
            for dep in lock_packages[pkg_key].get("dependencies", []):
                dep_name = parse_package_key(dep["name"]).name
                if dep_name not in enqueued:
                    enqueued[dep_name] = True
                    queue.append(dep_name)

    if head < len(queue):
        fail("BFS traversal exceeded max iterations; this is a bug in pycross")

    # PDM's export drops extras edges (requests[socks] -> pysocks), leaving
    # locked packages unreachable from the roots. If any such orphan's PDM
    # selection marker names a requested group, model the lock as graphless
    # instead. Other unreachable packages are pruned as before.
    orphans = {
        k: True
        for k, pkg in lock_packages.items()
        if pkg["name"] not in visited_names and _selects_requested_group(pkg_markers[k], requested_groups_dict)
    }
    if orphans:
        lock_packages = {
            k: pkg
            for k, pkg in lock_packages.items()
            if k in orphans or pkg["name"] in visited_names
        }
        _link_through_hub(lock_packages, versions_all)
        visited_names = {pkg["name"]: True for pkg in lock_packages.values()}

    lock_packages = {
        pkg_key: pkg
        for pkg_key, pkg in lock_packages.items()
        if pkg["name"] in visited_names
    }

    pins = {}
    for root_name in sorted(all_roots.keys()):
        base_name = parse_package_key(root_name).name
        keys = deps_by_name.get(base_name, [])
        if keys:
            if "[" in root_name:
                ver = parse_package_key(keys[0]).version
                pins[root_name] = "{}@{}".format(root_name, ver)
            else:
                pins[root_name] = keys[0]

    return lock_packages, pins, sorted(testonly_package_names.keys()), root_dependency_markers

def translate_pylock(lock_dict, project_dict, lock_model):
    """Translates pylock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        lock_dict: Parsed pylock.toml as a dict.
        project_dict: Parsed pyproject.toml as a dict (may be None).
        lock_model: A struct containing the lock model attributes.

    Returns:
        A dict in raw_lock.json format.
    """

    lock_version = lock_dict.get("lock-version", "")
    if str(lock_version) != "1.0":
        fail("Unsupported pylock lock-version: {}. Expected 1.0".format(lock_version))

    requires_python = lock_dict.get("requires-python", "")

    packages_list = lock_dict.get("package", lock_dict.get("packages", []))

    # Directory entries are local source trees (e.g. workspace members). Like
    # the other translators' local packages they have no downloadable
    # artifact, and uv omits their version.
    packages_list = [pkg for pkg in packages_list if "directory" not in pkg]
    for pkg in packages_list:
        if "version" not in pkg:
            fail("pylock package '{}' has no version, which rules_pycross requires".format(pkg["name"]))

    # pip lock and uv export write no dependency graph; see _link_through_hub.
    has_graph = [
        True
        for pkg in packages_list
        if "dependencies" in pkg or "dependencies" in pkg.get("tool", {}).get("pdm", {})
    ]

    requested_groups_dict = _compute_pylock_requested_groups(project_dict, lock_model)

    # Create lookup map for versions.
    # Track all versions per name to support multi-target forks.
    versions = {}  # {name: version} - first version seen
    versions_all = {}  # {name: {version: marker}} - all active versions with env markers
    all_lock_versions = {}  # {name: {version: True}} - all versions before selection pruning
    pkg_markers = {}  # {pkg_key: raw marker}
    active_packages_list = []
    for pkg in packages_list:
        name = canonicalize_name(pkg["name"])
        version = pkg["version"]
        all_lock_versions.setdefault(name, {})[version] = True
        marker = pkg.get("marker", "")

        # Prune dependency_groups/extras selection markers via pypackaging.markers.
        env_marker = _strip_selection_markers(marker, requested_groups_dict)
        if env_marker == None:
            continue
        active_packages_list.append(pkg)
        if name not in versions:
            versions[name] = version
        pkg_markers["{}@{}".format(name, version)] = marker
        versions_all.setdefault(name, {})[version] = env_marker

    # If a multi-version fork has a single unmarked fallback branch alongside
    # marked branches whose markers can be negated into a PEP 508 expression,
    # synthesize the complementary marker so both fork edges and pins stay
    # mutually exclusive. Otherwise keep "" as the fallback branch in pins.
    for fname, version_markers in versions_all.items():
        if len(version_markers) <= 1:
            continue
        unmarked = [v for v, m in version_markers.items() if not m]
        marked = [m for m in version_markers.values() if m]
        if len(unmarked) == 1 and marked:
            inverted_asts = [_invert_marker_ast(m) for m in marked]
            if all(inverted_asts):
                combined = []
                for i, ast in enumerate(inverted_asts):
                    if i > 0:
                        combined.append("and")
                    combined.append(ast)
                version_markers[unmarked[0]] = pypackaging.markers.to_string(combined)

    lock_packages = {}

    for pkg in active_packages_list:
        name = canonicalize_name(pkg["name"])
        version = pkg["version"]
        pkg_key = "{}@{}".format(name, version)

        raw_deps = pkg.get("dependencies")
        if raw_deps == None:
            # PDM's exporter records the graph as PEP 508 strings under tool.pdm.
            raw_deps = []
            for req_str in pkg.get("tool", {}).get("pdm", {}).get("dependencies", []):
                req = parse_pep508_requirement(req_str)
                for extra in req.extras or [""]:
                    raw_deps.append({
                        "name": "{}[{}]".format(req.name, extra) if extra else req.name,
                        "marker": req.marker,
                    })

        dependencies = []
        for dep in raw_deps:
            dep_name_raw = dep["name"]
            dep_name = canonicalize_name(dep_name_raw)

            # Handle extras in dependency name
            dep_extra = ""
            if "[" in dep_name_raw:
                parts = dep_name_raw.split("[", 1)
                dep_name = canonicalize_name(parts[0])
                dep_extra = parts[1].rstrip("]").strip()

            dep_display = dep_name
            if dep_extra:
                dep_display = "{}[{}]".format(dep_name, canonicalize_name(dep_extra))

            dep_versions = versions_all.get(dep_name)
            if not dep_versions:
                # buildifier: disable=print
                print("WARNING: dependency '{}' of '{}' not found in lockfile, skipping".format(
                    dep_display,
                    name,
                ))
                continue

            dep_marker = dep.get("marker", "")
            explicit_ver = dep.get("version")
            if explicit_ver:
                if explicit_ver not in dep_versions:
                    if explicit_ver not in all_lock_versions.get(dep_name, {}):
                        # buildifier: disable=print
                        print("WARNING: dependency '{}=={}' of '{}' not found in lockfile, skipping".format(
                            dep_display,
                            explicit_ver,
                            name,
                        ))
                    continue
                dependencies.append({
                    "name": dep_display,
                    "version": explicit_ver,
                    "marker": dep_marker,
                })
            elif len(dep_versions) == 1:
                dependencies.append({
                    "name": dep_display,
                    "version": versions[dep_name],
                    "marker": dep_marker,
                })
            else:
                for cand_ver, cand_marker in sorted(dep_versions.items()):
                    dependencies.append({
                        "name": dep_display,
                        "version": cand_ver,
                        "marker": _combine_markers(dep_marker, cand_marker),
                    })

        files = []
        pkg_index = pkg.get("index", "")

        # Wheels and sdists
        sdist_list = pkg.get("sdists", pkg.get("sdist", []))
        if type(sdist_list) == "dict":
            sdist_list = [sdist_list]
        for artifact in list(pkg.get("wheels", pkg.get("wheel", []))) + list(sdist_list):
            if type(artifact) != "dict":
                continue
            filename = artifact.get("name", artifact.get("file", ""))
            if not filename and "url" in artifact:
                filename = url_filename(artifact["url"])
            url = artifact.get("url", "")
            hash_str = artifact.get("hash", "")
            if hash_str and hash_str.startswith("sha256:"):
                hash_val = hash_str[7:]
            else:
                hash_val = artifact.get("hashes", {}).get("sha256", "")
            file_entry = {
                "name": filename,
                "sha256": hash_val,
                "package_name": name,
                "package_version": version,
            }
            if url:
                file_entry["urls"] = [url]
            elif pkg_index:
                file_entry["index"] = pkg_index
            files.append(file_entry)

        # Direct references: a VCS checkout or a source archive URL.
        source_dir = ""
        vcs = pkg.get("vcs")
        archive = pkg.get("archive")
        if vcs:
            commit = vcs.get("commit-id", "")
            if vcs.get("type") != "git" or not vcs.get("url") or not commit:
                fail("pylock package '{}': only git vcs entries with a url and commit-id are supported".format(name))
            files.append({
                "name": "{}-{}.tar.gz".format(name, version),
                "sha256": sha256_from_string(commit),
                "urls": ["git+{}#{}".format(vcs["url"], commit)],
                "package_name": name,
                "package_version": version,
            })
            source_dir = vcs.get("subdirectory", "")
        elif archive:
            if not archive.get("url"):
                fail("pylock package '{}': local archive entries are not supported".format(name))
            files.append({
                "name": "{}-{}{}".format(name, version, archive_extension(archive["url"])),
                "sha256": archive.get("hashes", {}).get("sha256", ""),
                "urls": [archive["url"]],
                "package_name": name,
                "package_version": version,
            })
            source_dir = archive.get("subdirectory", "")
        elif not files:
            fail("pylock package '{}' has no wheels, sdist, vcs, or archive entry".format(name))

        # Sort dependencies and files for determinism
        dependencies = sorted(dependencies, key = lambda d: (d["name"], d["version"]))
        files = sorted(files, key = lambda f: f["name"])

        package_requires_python = pkg.get("requires-python", "")

        raw_package = {
            "name": name,
            "version": version,
            "python_versions": package_requires_python,
            "dependencies": dependencies,
            "files": files,
        }
        if source_dir:
            raw_package["source_dir"] = source_dir

        lock_packages[pkg_key] = raw_package

    if len(lock_packages) > 1 and not has_graph:
        _link_through_hub(lock_packages, versions_all)

    # Build dependency lookup by name
    deps_by_name = {}  # {name: [pkg_key, ...]}
    for pkg_key, pkg in lock_packages.items():
        pkg_name = pkg["name"]
        deps_by_name.setdefault(pkg_name, []).append(pkg_key)

    lock_packages, pins, testonly_pins, root_dependency_markers = _resolve_pylock_project_pins(
        project_dict,
        requested_groups_dict,
        lock_packages,
        deps_by_name,
        pkg_markers,
        versions_all,
    )

    # Detect resolution-marker forks among surviving packages.
    surviving_versions_all = {}
    for pkg_key, pkg in lock_packages.items():
        fname = pkg["name"]
        fver = pkg["version"]
        surviving_versions_all.setdefault(fname, {})[fver] = versions_all.get(fname, {}).get(fver, "")

    resolution_marker_exprs = {}
    fork_constraints = {}  # {name: {version: constraint_name}}
    for fname, version_markers in surviving_versions_all.items():
        if len(version_markers) <= 1:
            continue  # Single version, no fork.
        if not any(version_markers.values()):
            continue  # No env markers distinguish these versions.
        seen_unmarked = False
        for fversion, marker_expr in sorted(version_markers.items()):
            if not marker_expr:
                if seen_unmarked:
                    continue
                seen_unmarked = True

                # Unmarked fallback branch: keep under "" (default select branch).
                fork_constraints.setdefault(fname, {})[fversion] = ""
                continue
            cname = resolution_marker_constraint_name(fname, fversion)
            fork_constraints.setdefault(fname, {})[fversion] = cname
            resolution_marker_exprs[cname] = marker_expr

    # If forks were detected, update pins (including base[extra] pins) to use conditional pins.
    for fname, version_constraints in fork_constraints.items():
        for pin_name in list(pins.keys()):
            if pin_name == fname or pin_name.startswith(fname + "["):
                pins[pin_name] = {
                    cname: "{}@{}".format(pin_name, fversion)
                    for fversion, cname in version_constraints.items()
                }

    result = {
        "packages": lock_packages,
        "pins": pins,
        "python_versions": requires_python,
        "testonly_pins": testonly_pins,
    }
    if resolution_marker_exprs:
        result["resolution_marker_exprs"] = resolution_marker_exprs
    filtered_root_markers = {
        name: markers
        for name, markers in root_dependency_markers.items()
        if markers != None
    }
    if filtered_root_markers:
        result["root_dependency_markers"] = filtered_root_markers
    return result

def repo_create_pylock_model(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Run the pylock translator in pure Starlark."""
    project_dict, lock_dict = read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, "the pylock file", toml_cache)
    return translate_pylock(lock_dict, project_dict, lock_model)
