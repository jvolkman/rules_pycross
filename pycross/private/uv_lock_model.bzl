"""Starlark UV translator.

Replaces the Python uv_translator.py with a pure-Starlark implementation.
Parses uv.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.

Handles UV-specific features: workspace members, conflicts/variants,
resolution markers, git sources, and editable packages.
"""

load(":lock_common.bzl", "read_toml_cached")
load(
    ":translator_graph.bzl",
    "build_lock_graph",
    "expand_root_edges",
    "finalize_lock_graph",
)
load(
    ":translator_project.bzl",
    "compute_requested_groups_for_model",
    "read_project_and_lock",
    "validate_multi_project_groups",
)
load(
    ":translator_util.bzl",
    "canonicalize_name",
    "is_external_member_path",
    "make_archive_file_entry",
    "make_file_entry",
    "make_git_file_entry",
    "strip_sha256_prefix",
)
load(":util.bzl", "resolution_marker_constraint_name", "url_decode_filename", "url_filename")
load(
    ":uv_conflicts.bzl",
    "apply_repo_variant_pins_and_defaults",
    "canonicalize_group_key",
    "instantiate_uv_conflicts",
    "make_pin_marker_folder",
    "parse_uv_conflicts_base",
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

    raw_hash = file_info.get("hash", "")
    return make_file_entry(
        filename,
        strip_sha256_prefix(raw_hash) if raw_hash else "",
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

def _is_local_source(source):
    """Return True when a UV lock `source` table refers to a local package."""
    return (
        type(source.get("editable")) == "string" or
        type(source.get("virtual")) == "string" or
        "directory" in source
    )

def _lock_pkg_version(lock_pkg):
    """Return a package's version, defaulting missing versions on local packages to '0.0.0'."""
    version = lock_pkg.get("version")
    if version:
        return version
    if _is_local_source(lock_pkg.get("source", {})):
        return "0.0.0"
    fail("Package '{}' in uv.lock is missing a 'version' field".format(lock_pkg.get("name", "<unknown>")))

def _manifest_member_names(lock_data):
    """Return a set of canonical member names from `[manifest].members`, or None if absent/empty."""
    members = lock_data.get("manifest", {}).get("members", [])
    if not members:
        return None
    return {canonicalize_name(m): True for m in members}

def _compute_source_tags(packages_list):
    """Assign deterministic `~<tag>` suffixes ONLY to `(name, version)` pairs with >1 distinct source."""
    sources_by_nv = {}  # (canonical_name, version) -> {canon_source: True}
    pkg_identities = []  # parallel to packages_list: (canonical_name, canon_source)
    for lock_pkg in packages_list:
        name = canonicalize_name(lock_pkg["name"])
        canon = _canonical_source(lock_pkg.get("source", {}))
        pkg_identities.append((name, canon))
        sources_by_nv.setdefault((name, _lock_pkg_version(lock_pkg)), {})[canon] = True

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
    if sdist == None:
        return None
    if "url" not in sdist and "file" not in sdist and "url" in source:
        # URL-based source with subdirectory or empty sdist table
        raw_hash = sdist.get("hash", "")
        return make_archive_file_entry(
            package_name,
            package_version,
            source["url"],
            strip_sha256_prefix(raw_hash) if raw_hash else "",
            index = registry,
        )
    if not sdist:
        return None
    if "git" not in source or "url" in sdist or "file" in sdist:
        return _parse_file_info(sdist, package_name, package_version, registry)
    return None

def _parse_lock_packages(packages_list, token_replacements, source_tags, pkg_identities):
    """Parse `uv.lock` `[[package]]` entries and scan `resolution-markers` forks in one pass."""
    packages = []
    fork_versions = {}  # {canonical_name: {(version, tag): [marker_expr, ...]}}

    for lock_pkg, (package_name, canon_source) in zip(packages_list, pkg_identities):
        package_version = _lock_pkg_version(lock_pkg)
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

        sdist_file = _parse_sdist_file(lock_pkg.get("sdist"), source, package_name, package_version, registry)
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

        is_local = _is_local_source(source)

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

def _build_uv_workspace_base(lock_dict):
    """Parse workspace-invariant UV lock structures and build the lock graph once."""
    lock_version = lock_dict.get("version", 0)
    if lock_version != 1:
        fail("UV lock file version {} is not supported (expected 1)".format(lock_version))

    # backwards-compat for https://github.com/astral-sh/uv/pull/5861
    distributions_list = lock_dict.get("distribution", [])
    packages_list = lock_dict.get("package", distributions_list)
    uv_conflicts = lock_dict.get("conflicts", [])

    base_conflicts = parse_uv_conflicts_base(uv_conflicts)
    source_tags, pkg_identities = _compute_source_tags(packages_list)
    packages, fork_constraints, base_resolution_marker_exprs = _parse_lock_packages(
        packages_list,
        base_conflicts.token_replacements,
        source_tags,
        pkg_identities,
    )
    graph = build_lock_graph(
        packages,
        resolution_marker_exprs = base_resolution_marker_exprs,
        strict_dependencies = True,
    )

    manifest_members = _manifest_member_names(lock_dict)
    base_workspace_members = {}
    packages_by_canon_name = {}
    for lock_pkg, (canon_name, _) in zip(packages_list, pkg_identities):
        if canon_name not in packages_by_canon_name:
            packages_by_canon_name[canon_name] = lock_pkg
        source = lock_pkg.get("source", {})
        editable = source.get("editable")
        virtual = source.get("virtual")
        if type(editable) == "string":
            member_path = editable
        elif type(virtual) == "string":
            member_path = virtual
        else:
            continue
        if manifest_members != None:
            if canon_name not in manifest_members:
                continue
        elif is_external_member_path(member_path):
            continue
        base_workspace_members[canon_name] = lock_pkg

    return struct(
        base_conflicts = base_conflicts,
        fork_constraints = fork_constraints,
        resolution_marker_exprs = base_resolution_marker_exprs,
        graph = graph,
        base_workspace_members = base_workspace_members,
        packages_by_canon_name = packages_by_canon_name,
    )

def _find_target_projects(base_workspace_members, packages_by_canon_name, project_dict, projects_list):
    """Resolve `projects_list` against workspace members without mutating cached dicts."""
    workspace_members = dict(base_workspace_members)
    if not workspace_members and packages_by_canon_name:
        # Fallback for older uv.lock (< 0.2.35) or standalone single-project locks.
        pname = project_dict.get("project", {}).get("name")
        if pname:
            pname = canonicalize_name(pname)
            if pname in packages_by_canon_name:
                workspace_members[pname] = packages_by_canon_name[pname]

    if "*" in projects_list:
        target_projects = list(workspace_members.keys())
    else:
        target_projects = [canonicalize_name(p) for p in projects_list]

    for p in target_projects:
        if p in workspace_members:
            continue
        if p not in packages_by_canon_name:
            fail("Project '{}' not found in uv.lock workspace members.".format(p))
        workspace_members[p] = packages_by_canon_name[p]

    return workspace_members, target_projects

def translate_uv(project_dict, lock_dict, lock_model, workspace_cache = None):
    """Translates UV project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml as a dict.
        lock_dict: Parsed uv.lock as a dict.
        lock_model: A struct containing the lock model attributes.
        workspace_cache: Optional dict shared across repos in the same workspace
            to reuse parsed lock packages, conflict metadata, parsed marker ASTs,
            and the lock graph.

    Returns:
        A dict in raw_lock.json format.
    """
    if workspace_cache != None:
        base = workspace_cache.get("uv_base")
        if base == None:
            base = _build_uv_workspace_base(lock_dict)
            workspace_cache["uv_base"] = base
            workspace_cache["shared_packages"] = True
        marker_parse_cache = workspace_cache.setdefault("marker_parse_cache", {})
    else:
        base = _build_uv_workspace_base(lock_dict)
        marker_parse_cache = {}

    uv_default_groups = project_dict.get("tool", {}).get("uv", {}).get("default-groups", [])

    projects_list = getattr(lock_model, "projects", [])
    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    is_build_tools_repo = getattr(lock_model, "is_build_tools_repo", False)

    workspace_members, target_projects = _find_target_projects(
        base.base_workspace_members,
        base.packages_by_canon_name,
        project_dict,
        projects_list,
    )
    conflicts = instantiate_uv_conflicts(base.base_conflicts, target_projects)

    # Copy per member because resolve_uv_pins adds edge constraints in place.
    resolution_marker_exprs = dict(base.resolution_marker_exprs)

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

    tokens_cache = {}
    fold_cache = {}
    expanded_edges = expand_root_edges(
        base.graph,
        root_edges,
        strict_dependencies = True,
        fold_pin_marker = make_pin_marker_folder(
            conflicts,
            repo_pins,
            parse_cache = marker_parse_cache,
            tokens_cache = tokens_cache,
            fold_cache = fold_cache,
        ),
    )
    resolved_pins = resolve_uv_pins(
        expanded_edges,
        conflicts = conflicts,
        repo_pins = repo_pins,
        fork_constraints = base.fork_constraints,
        resolution_marker_exprs = resolution_marker_exprs,
        parse_cache = marker_parse_cache,
        tokens_cache = tokens_cache,
        fold_cache = fold_cache,
    )

    return finalize_lock_graph(
        base.graph,
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
    manifest_members = _manifest_member_names(lock_data)

    members = []
    for pkg in packages_list:
        if manifest_members != None and canonicalize_name(pkg["name"]) not in manifest_members:
            continue
        source = pkg.get("source", {})
        editable = source.get("editable")
        virtual = source.get("virtual")
        if type(editable) == "string":
            if manifest_members == None and is_external_member_path(editable):
                continue
            members.append(struct(
                name = pkg["name"],
                path = editable,
            ))
        elif type(virtual) == "string":
            if manifest_members == None and is_external_member_path(virtual):
                continue

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
                    path = virtual,
                ))

    return members

def repo_create_uv_model(rctx, extra_project_files, lock_file, lock_model, toml_cache = None, workspace_cache = None):
    """Run the UV translator in pure Starlark."""
    project_dict, lock_dict = read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, "uv.lock", toml_cache)
    return translate_uv(project_dict, lock_dict, lock_model, workspace_cache = workspace_cache)
