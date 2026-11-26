"""Starlark UV translator.

Replaces the Python uv_translator.py with a pure-Starlark implementation.
Parses uv.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.

Handles UV-specific features: workspace members, conflicts/variants,
resolution markers, git sources, and editable packages.
"""

load(":lock_common.bzl", "read_toml_cached")
load(
    ":translator_common.bzl",
    "build_lock_graph",
    "canonicalize_name",
    "compute_requested_groups_for_model",
    "expand_root_edges",
    "finalize_lock_graph",
    "make_archive_file_entry",
    "make_file_entry",
    "make_git_file_entry",
    "read_project_and_lock",
    "strip_sha256_prefix",
    "validate_multi_project_groups",
)
load(":util.bzl", "resolution_marker_constraint_name", "url_decode_filename", "url_filename")
load(
    ":uv_conflicts.bzl",
    "apply_repo_variant_pins_and_defaults",
    "canonicalize_group_key",
    "make_pin_marker_folder",
    "parse_uv_conflicts",
    "resolve_uv_pins",
    "rewrite_conflict_markers",
)

def _parse_file_info(file_info, package_name, package_version, registry = None):
    """Parse a UV lock file entry into a file dict."""
    if "file" in file_info:
        filename = file_info["file"]
        urls = None
    elif "filename" in file_info:
        filename = file_info["filename"]
        urls = None
    elif "url" in file_info:
        url = file_info["url"]
        filename = url_filename(url)
        urls = [url]
    elif "path" in file_info:
        fail("Package {}=={}: local path distributions ({}) are not supported".format(package_name, package_version, file_info["path"]))
    else:
        fail("UV file entry has no 'file', 'filename', or 'url' member: {}".format(file_info))

    return make_file_entry(
        filename,
        strip_sha256_prefix(file_info["hash"]),
        package_name,
        package_version,
        urls = urls,
        index = registry,
    )

def _canonical_source(source):
    """Serialize a UV lock `source` table deterministically for identity matching."""
    if not source:
        return ""
    return json.encode([[k, source[k]] for k in sorted(source.keys())])

def _source_value(source):
    """Return a human-readable source identifier (registry/git/url/path) from a UV `source` table."""
    if not source:
        return ""
    for key in ("registry", "git", "url", "flat", "path", "directory", "editable", "virtual"):
        if key in source:
            val = str(source[key])
            sub = source.get("subdirectory", "")
            return "{}#subdirectory={}".format(val, sub) if sub and "subdirectory=" not in val else val
    return _canonical_source(source)

def _compute_source_tags(packages_list):
    """Assign deterministic `~<tag>` suffixes ONLY to `(name, version)` pairs with >1 distinct source."""
    sources_by_nv = {}  # (canonical_name, version) -> {canon_source: True}
    pkg_identities = []  # parallel to packages_list: (canonical_name, canon_source)
    for lock_pkg in packages_list:
        name = canonicalize_name(lock_pkg["name"])
        canon = _canonical_source(lock_pkg.get("source", {}))
        pkg_identities.append((name, canon))
        sources_by_nv.setdefault((name, lock_pkg["version"]), {})[canon] = True

    source_tags = {}  # (canonical_name, version, canon_source) -> tag
    for (name, version), canon_sources in sources_by_nv.items():
        if len(canon_sources) <= 1:
            continue
        used_tags = {}
        for canon in sorted(canon_sources.keys()):
            base_tag = ("00000000" + ("%x" % (hash(canon) & 0xffffffff)))[-8:] if canon else "none"
            tag = base_tag
            if tag in used_tags:
                for i in range(1, len(canon_sources) + 1):
                    cand = "{}_{}".format(base_tag, i)
                    if cand not in used_tags:
                        tag = cand
                        break
            used_tags[tag] = True
            source_tags[(name, version, canon)] = tag
    return source_tags, pkg_identities

def _parse_uv_dependency(dep, token_replacements = ()):
    """Parse a UV lock dependency dict into dep dicts for `build_lock_graph`."""
    name = canonicalize_name(dep.get("name", ""))
    version = dep.get("version", "")
    specifier = "==={}".format(version) if version else ""
    marker = rewrite_conflict_markers(dep.get("marker", ""), token_replacements)
    source_id = _canonical_source(dep.get("source", {}))
    extras = dep.get("extra") or dep.get("extras", [])

    if not extras:
        return [{
            "name": name,
            "specifier": specifier,
            "marker": marker,
            "source_id": source_id,
            "extras": [None],
        }]

    return [
        {
            "name": "{}[{}]".format(name, canonicalize_name(extra)),
            "specifier": specifier,
            "marker": marker,
            "source_id": source_id,
            "extras": [None],
        }
        for extra in extras
    ]

def _parse_sdist_file(sdist, source, package_name, package_version, registry):
    """Parse an sdist entry from a UV lock package, or return None."""
    if not sdist:
        return None
    if "url" not in sdist and "file" not in sdist and "url" in source:
        # URL-based source with subdirectory
        return make_archive_file_entry(
            package_name,
            package_version,
            source["url"],
            strip_sha256_prefix(sdist["hash"]),
            index = registry,
        )
    elif "git" not in source or "url" in sdist or "file" in sdist:
        return _parse_file_info(sdist, package_name, package_version, registry)
    return None

def _parse_lock_packages(packages_list, token_replacements, source_tags, pkg_identities):
    """Parse `uv.lock` `[[package]]` entries and scan `resolution-markers` forks in one pass."""
    packages = []
    fork_versions = {}  # {canonical_name: {(version, tag): [marker_expr, ...]}}

    for lock_pkg, (package_name, canon_source) in zip(packages_list, pkg_identities):
        package_version = lock_pkg["version"]
        source = lock_pkg.get("source", {})
        source_tag = source_tags.get((package_name, package_version, canon_source), "")

        res_markers = [
            rewrite_conflict_markers(m, token_replacements)
            for m in lock_pkg.get("resolution-markers", [])
        ]
        if res_markers:
            fork_versions.setdefault(package_name, {}).setdefault((package_version, source_tag), []).extend(res_markers)

        deps = []
        for dep in lock_pkg.get("dependencies", []):
            deps.extend(_parse_uv_dependency(dep, token_replacements))

        files = []
        source_display = _source_value(source)
        registry = source.get("registry")

        for w in lock_pkg.get("wheels", []):
            files.append(_parse_file_info(w, package_name, package_version, registry))

        sdist_file = _parse_sdist_file(lock_pkg.get("sdist", {}), source, package_name, package_version, registry)
        if sdist_file:
            files.append(sdist_file)

        source_dir = source.get("subdirectory", "")

        if "git" in source and not files:
            git_url = source["git"]
            commit = git_url.split("#")[-1] if "#" in git_url else ""

            # uv records git subdirectories in the URL query: ?subdirectory=a%2Fb&rev=...
            if "?" in git_url:
                query = git_url.split("#")[0].split("?", 1)[1]
                for param in query.split("&"):
                    if param.startswith("subdirectory="):
                        source_dir = url_decode_filename(param[len("subdirectory="):])
            if commit:
                files.append(make_git_file_entry(
                    package_name,
                    package_version,
                    git_url,
                    commit,
                    full_url = "git+" + git_url,
                ))

        is_local = (
            ("editable" in source and type(source.get("editable")) == "string") or
            ("virtual" in source and type(source.get("virtual")) == "string") or
            "directory" in source
        )

        base_pkg = {
            "name": package_name,
            "version": package_version,
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "tag": source_tag,
            "source_id": canon_source,
            "source": source_display,
        }
        if source_dir:
            base_pkg["source_dir"] = source_dir
        packages.append(base_pkg)

        # Extra packages (UV's optional-dependencies within the lock package)
        for extra_name, extra_deps_list in lock_pkg.get("optional-dependencies", {}).items():
            extra_parsed_deps = []
            for dep in extra_deps_list:
                extra_parsed_deps.extend(_parse_uv_dependency(dep, token_replacements))
            extra_parsed_deps.append({
                "name": package_name,
                "specifier": "==={}".format(package_version),
                "marker": "",
                "source_id": canon_source,
                "extras": [None],
            })
            extra_pkg = {
                "name": "{}[{}]".format(package_name, canonicalize_name(extra_name)),
                "version": package_version,
                "dependencies": extra_parsed_deps,
                "files": [],
                "is_local": is_local,
                "tag": source_tag,
                "source_id": canon_source,
                "source": source_display,
            }
            if source_dir:
                extra_pkg["source_dir"] = source_dir
            packages.append(extra_pkg)

    resolution_marker_exprs = {}
    fork_constraints = {}
    for fname, versions in fork_versions.items():
        if len(versions) <= 1:
            continue
        for (fversion, ftag), markers in versions.items():
            combined = markers[0] if len(markers) == 1 else " or ".join(["({})".format(m) for m in markers])
            cname = resolution_marker_constraint_name(fname, fversion, ftag)
            fork_constraints.setdefault(fname, {})[(fversion, ftag)] = cname
            resolution_marker_exprs[cname] = combined

    return packages, fork_constraints, resolution_marker_exprs

def _find_target_projects(packages_list, project_dict, projects_list):
    """Discover workspace members in `uv.lock` and resolve `projects_list`."""
    workspace_members = {}
    for pkg in packages_list:
        if "virtual" in pkg.get("source", {}) or pkg.get("source", {}).get("editable"):
            workspace_members[canonicalize_name(pkg["name"])] = pkg

    if not workspace_members and packages_list:
        # Fallback for older uv.lock (< 0.2.35) or standalone single-project locks.
        pname = project_dict.get("project", {}).get("name")
        if pname:
            pname = canonicalize_name(pname)
            for pkg in packages_list:
                if canonicalize_name(pkg["name"]) == pname:
                    workspace_members[pname] = pkg
                    break

    if "*" in projects_list:
        target_projects = list(workspace_members.keys())
    else:
        target_projects = [canonicalize_name(p) for p in projects_list]

    for p in target_projects:
        if p in workspace_members:
            continue
        for pkg in packages_list:
            if canonicalize_name(pkg["name"]) == p:
                workspace_members[p] = pkg
                break
        if p not in workspace_members:
            fail("Project '{}' not found in uv.lock workspace members.".format(p))

    return workspace_members, target_projects

def translate_uv(project_dict, lock_dict, lock_model):
    """Translates UV project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml as a dict.
        lock_dict: Parsed uv.lock as a dict.
        lock_model: A struct containing the lock model attributes.

    Returns:
        A dict in raw_lock.json format.
    """
    lock_version = lock_dict.get("version", 0)
    if lock_version != 1:
        fail("UV lock file version {} is not supported (expected 1)".format(lock_version))

    # backwards-compat for https://github.com/astral-sh/uv/pull/5861
    distributions_list = lock_dict.get("distribution", [])
    packages_list = lock_dict.get("package", distributions_list)
    uv_conflicts = lock_dict.get("conflicts", [])
    uv_default_groups = project_dict.get("tool", {}).get("uv", {}).get("default-groups", [])

    projects_list = getattr(lock_model, "projects", [])
    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    is_build_tools_repo = getattr(lock_model, "is_build_tools_repo", False)

    workspace_members, target_projects = _find_target_projects(packages_list, project_dict, projects_list)
    conflicts = parse_uv_conflicts(uv_conflicts, target_projects)
    source_tags, pkg_identities = _compute_source_tags(packages_list)
    packages, fork_constraints, resolution_marker_exprs = _parse_lock_packages(
        packages_list,
        conflicts.token_replacements,
        source_tags,
        pkg_identities,
    )

    # In a repo spanning several projects, a requested extra/group applies to the
    # projects that declare it (like `uv --all-packages --group test`); it only
    # has to exist in one of them.
    multi_project = len(target_projects) > 1
    groups_seen = {"default": True}
    requested_by_project = {}
    root_edges = []

    for project_name in target_projects:
        project_info = workspace_members[project_name]
        default_dependencies = project_info.get("dependencies", [])
        optional_dependencies = project_info.get("optional-dependencies", {})
        development_dependencies = project_info.get("dev-dependencies", {})

        # uv.lock leaves empty extras and groups (e.g. `cpu = []` when only
        # `[tool.uv.sources]` depends on it) out of `optional-dependencies` and
        # `dev-dependencies`, so also read them from metadata and conflicts.
        metadata = project_info.get("metadata", {})
        extra_names = list(optional_dependencies.keys()) + metadata.get("provides-extras", [])
        group_names = list(development_dependencies.keys()) + list(metadata.get("requires-dev", {}).keys())
        for item in conflicts.variant_items_by_key.values():
            if item["package"] != project_name:
                continue
            if item["kind"] == "extra":
                extra_names.append(item["name"])
            elif item["kind"] == "group":
                group_names.append(item["name"])

        available_groups = ["default"]
        seen_canonical = {}
        for g in ["optional:" + n for n in extra_names] + ["group:" + n for n in group_names]:
            canonical = canonicalize_group_key(g)
            if canonical not in seen_canonical:
                seen_canonical[canonical] = True
                available_groups.append(g)
        for g in available_groups:
            groups_seen[g] = True

        requested_groups_dict = compute_requested_groups_for_model(
            lock_model,
            available_groups,
            project_name = project_name,
            allow_missing = multi_project,
        )
        requested_by_project[project_name] = requested_groups_dict

        # A project in a `{package = ...}` conflict has all of its edges gated on
        # its project variant; extras/groups with their own variant use that instead.
        project_constraint = conflicts.project_variant_values.get(project_name, "")
        group_batches = []
        if "default" in requested_groups_dict:
            group_batches.append((project_constraint, default_dependencies, requested_groups_dict["default"]))
        for kind, groups_dict, constraint_dict in [
            ("optional", optional_dependencies, conflicts.extra_variant_values),
            ("group", development_dependencies, conflicts.group_variant_values),
        ]:
            for group_name, deps_list in groups_dict.items():
                key = "{}:{}".format(kind, group_name)
                if key not in requested_groups_dict:
                    continue
                group_batches.append((
                    constraint_dict.get((project_name, group_name), project_constraint),
                    deps_list,
                    requested_groups_dict[key],
                ))

        for constraint, deps_list, is_testonly in group_batches:
            for dep in deps_list:
                for parsed in _parse_uv_dependency(dep, conflicts.token_replacements):
                    root_edges.append(struct(
                        pin_name = parsed["name"],
                        specifier = parsed["specifier"],
                        constraint = constraint,
                        is_testonly = is_testonly,
                        marker = parsed["marker"],
                        source_id = parsed["source_id"],
                    ))

    if multi_project:
        validate_multi_project_groups(dependency_groups, groups_seen, target_projects)

    default_owner = canonicalize_name(project_dict.get("project", {}).get("name", ""))
    repo_pins = apply_repo_variant_pins_and_defaults(
        conflicts,
        target_projects = target_projects,
        requested_by_project = requested_by_project,
        default_owner = default_owner,
        uv_default_groups = uv_default_groups,
        is_build_tools_repo = is_build_tools_repo,
    )

    graph = build_lock_graph(
        packages,
        resolution_marker_exprs = resolution_marker_exprs,
        strict_dependencies = True,
    )
    expanded_edges = expand_root_edges(
        graph,
        root_edges,
        strict_dependencies = True,
        fold_pin_marker = make_pin_marker_folder(conflicts, repo_pins),
    )
    resolved_pins = resolve_uv_pins(
        expanded_edges,
        conflicts = conflicts,
        repo_pins = repo_pins,
        fork_constraints = fork_constraints,
        resolution_marker_exprs = resolution_marker_exprs,
    )

    return finalize_lock_graph(
        graph,
        resolved_pins.pinned_keys,
        variants = conflicts.variant_sets,
        resolution_marker_exprs = resolution_marker_exprs,
        testonly_pins = resolved_pins.testonly_pins,
        expanded_testonly_pins = resolved_pins.expanded_testonly_pins,
        non_testonly_pins = resolved_pins.non_testonly_pins,
        root_dependency_markers = resolved_pins.root_dependency_markers,
    )

def discover_uv_all_members(mctx, lock_file_label, toml_cache = None):
    """Parse uv.lock and return workspace members (editable/virtual packages).

    Args:
        mctx: The module_ctx object.
        lock_file_label: Label of the uv.lock file.
        toml_cache: Optional dict caching decoded TOML files by label.

    Returns:
        A list of structs with 'name' and 'path' fields.
    """
    lock_data = read_toml_cached(mctx, lock_file_label, toml_cache)
    if lock_data == None:
        fail("Lock file not found: {}".format(lock_file_label))

    # uv.lock uses "package" (newer) or "distribution" (older) for the package list.
    packages_list = lock_data.get("package", lock_data.get("distribution", []))

    members = []
    for pkg in packages_list:
        source = pkg.get("source", {})
        if "editable" in source:
            members.append(struct(
                name = pkg["name"],
                path = source["editable"],
            ))
        elif "virtual" in source:
            # Only include virtual members that have actual dependencies.
            # A virtual workspace root with no dependencies is just the workspace
            # definition and shouldn't produce a lock repo.
            has_deps = (
                pkg.get("dependencies") or
                pkg.get("optional-dependencies") or
                pkg.get("dev-dependencies")
            )
            if has_deps:
                members.append(struct(
                    name = pkg["name"],
                    path = source["virtual"],
                ))

    return members

def repo_create_uv_model(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Run the UV translator in pure Starlark."""
    project_dict, lock_dict = read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, "uv.lock", toml_cache)
    return translate_uv(project_dict, lock_dict, lock_model)
