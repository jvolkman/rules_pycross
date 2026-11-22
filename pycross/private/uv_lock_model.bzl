"""Starlark UV translator.

Replaces the Python uv_translator.py with a pure-Starlark implementation.
Parses uv.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.

Handles UV-specific features: workspace members, conflicts/variants,
resolution markers, git sources, and editable packages.
"""

load(
    ":translator_common.bzl",
    "archive_extension",
    "canonicalize_name",
    "compute_requested_dependency_groups",
    "read_project_and_lock",
    "record_root_marker",
    "resolution_marker_constraint_name",
    "resolve_lock_graph",
    "sha256_from_string",
)
load(":util.bzl", "url_decode_filename", "variant_item_qname")

def _parse_file_info(file_info, package_name, package_version, registry = None):
    """Parse a UV lock file entry into a file dict.

    Args:
        file_info: A dict with "file", "filename", or "url" and "hash" keys.
        package_name: The name of the package.
        package_version: The version of the package.
        registry: An optional string representing the index URL.

    Returns:
        A dict with name, sha256, package_name, package_version, and optionally urls/index.
    """
    if "file" in file_info:
        filename = file_info["file"]
        urls = []
    elif "filename" in file_info:
        filename = file_info["filename"]
        urls = []
    elif "url" in file_info:
        url = file_info["url"]

        # Extract filename from URL path
        path_part = url
        if "?" in path_part:
            path_part = path_part.split("?")[0]
        if "#" in path_part:
            path_part = path_part.split("#")[0]
        filename = url_decode_filename(path_part.split("/")[-1])
        urls = [url]
    elif "path" in file_info:
        fail("Package {}=={}: local path distributions ({}) are not supported".format(package_name, package_version, file_info["path"]))
    else:
        fail("UV file entry has no 'file', 'filename', or 'url' member: {}".format(file_info))

    file_hash = file_info["hash"]
    if not file_hash.startswith("sha256:"):
        fail("Expected sha256: prefix on hash: {}".format(file_hash))

    result = {
        "name": filename,
        "sha256": file_hash[7:],
        "package_name": package_name,
        "package_version": package_version,
    }
    if urls:
        result["urls"] = urls
    if registry:
        result["index"] = registry
    return result

def _resolve_package_requires_python(markers):
    """Extract python version specifiers from resolution markers.

    Args:
        markers: List of marker strings from resolution-markers.

    Returns:
        List of specifier strings.
    """
    specifiers = []
    for marker in markers:
        # Simple extraction of python_full_version constraints
        # e.g. "python_full_version >= '3.8'" -> ">= 3.8"
        if "python_full_version" not in marker:
            continue

        # Parse out the operator and version
        parts = marker.strip().split("python_full_version")
        if len(parts) != 2:
            continue
        rest = parts[1].strip()

        # Extract operator
        op = ""
        for c in rest.elems():
            if c in "<>=!":
                op += c
            elif op:
                break
        version_part = rest[len(op):].strip().strip("'\"")
        if op and version_part:
            specifiers.append("{} {}".format(op, version_part))
    return specifiers

def _uv_conflict_token(item):
    """Return the uv-encoded conflict marker token for a conflict item."""
    kind = item["kind"]
    pkg = canonicalize_name(item["package"])
    name = item.get("name", "")
    if kind == "extra":
        return "extra-{}-{}-{}".format(len(pkg), pkg, canonicalize_name(name))
    if kind == "group":
        return "group-{}-{}-{}".format(len(pkg), pkg, canonicalize_name(name))
    if kind == "project":
        return "project-{}-{}".format(len(pkg), pkg)
    fail("Unknown conflict item kind: {}".format(kind))

def _canonicalize_group_key(key):
    """Normalize the name in a requested group key (`optional:<name>`, `group:<name>`)."""
    kind, sep, name = key.partition(":")
    if not sep:
        return key
    return "{}:{}".format(kind, canonicalize_name(name))

def _is_item_requested(item, requested_keys):
    """Whether a repo requests a conflict item of one of its projects.

    Args:
        item: The conflict item.
        requested_keys: The groups the repo requests from the item's project,
            as canonicalized keys (`default`, `optional:<name>`, `group:<name>`).

    Returns:
        True if the item is active in the repo.
    """
    kind = item["kind"]
    if kind == "project":
        # Here a project variant gates all of the project's edges.
        return bool(requested_keys)
    if kind == "extra":
        return "optional:" + item["name"] in requested_keys
    return "group:" + item["name"] in requested_keys

def _rewrite_conflict_markers(marker, token_replacements):
    if not marker or not token_replacements or "extra" not in marker:
        return marker
    for old_quoted, new_quoted in token_replacements:
        if old_quoted in marker:
            marker = marker.replace(old_quoted, new_quoted)
    return marker

def _parse_uv_dependency(dep, token_replacements = ()):
    """Parse a UV lock dependency dict into a specifier.

    Args:
        dep: Dict with name, version, marker, extra/extras keys.
        token_replacements: Optional list of (old_quoted, new_quoted) pairs
            for rewriting uv conflict tokens into __variant_<qname>.

    Returns:
        A list of dep dicts suitable for resolve_lock_graph.
    """
    name = canonicalize_name(dep.get("name", ""))
    version = dep.get("version", "")
    specifier = "==={}".format(version) if version else ""
    marker = _rewrite_conflict_markers(dep.get("marker", ""), token_replacements)
    extras = dep.get("extra") or dep.get("extras", [])

    if not extras:
        return [{
            "name": name,
            "specifier": specifier,
            "marker": marker,
            "extras": [None],
        }]

    return [
        {
            "name": "{}[{}]".format(name, canonicalize_name(extra)),
            "specifier": specifier,
            "marker": marker,
            "extras": [None],
        }
        for extra in extras
    ]

def _resolve_uv_dep_constraint(constraint, base_dep_name, dep_version, dep_marker, fork_constraints, resolution_marker_exprs):
    """Combine a group/extra variant constraint with any resolution-marker fork constraint."""
    if base_dep_name not in fork_constraints or dep_version not in fork_constraints[base_dep_name]:
        return constraint
    fork_constraint = fork_constraints[base_dep_name][dep_version]
    if not constraint:
        return fork_constraint
    if dep_marker and dep_marker != resolution_marker_exprs.get(fork_constraint):
        edge_fork_constraint = "{}__{}".format(fork_constraint, constraint)
        resolution_marker_exprs[edge_fork_constraint] = dep_marker
        fork_constraint = edge_fork_constraint
    effective_constraint = "{}_{}".format(constraint, fork_constraint)

    # Register compound constraint with its components.
    resolution_marker_exprs[effective_constraint] = {
        "variant": constraint,
        "marker": fork_constraint,
    }
    return effective_constraint

def _parse_sdist_file(sdist, source, package_name, package_version, registry):
    """Parse an sdist entry from a UV lock package, or return None."""
    if not sdist:
        return None
    if "url" not in sdist and "file" not in sdist and "url" in source:
        # URL-based source with subdirectory
        url = source["url"]
        file_hash = sdist["hash"]
        if not file_hash.startswith("sha256:"):
            fail("Expected sha256: prefix on hash")
        filename = "{}-{}{}".format(package_name, package_version, archive_extension(url))
        f = {
            "name": filename,
            "sha256": file_hash[7:],
            "urls": [url],
            "package_name": package_name,
            "package_version": package_version,
        }
        if registry:
            f["index"] = registry
        return f
    elif "git" not in source or "url" in sdist or "file" in sdist:
        return _parse_file_info(sdist, package_name, package_version, registry)
    return None

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

    # Version check
    lock_version = lock_dict.get("version", 0)
    if lock_version != 1:
        fail("UV lock file version {} is not supported (expected 1)".format(lock_version))

    # backwards-compat for https://github.com/astral-sh/uv/pull/5861
    distributions_list = lock_dict.get("distribution", [])
    packages_list = lock_dict.get("package", distributions_list)
    requires_python = lock_dict.get("requires-python", "")

    # Extract conflicts from [tool.uv]
    uv_conflicts = lock_dict.get("conflicts", [])
    uv_default_groups = project_dict.get("tool", {}).get("uv", {}).get("default-groups", [])

    # Parse variant sets from conflicts
    variant_items_by_key = {}  # (package, kind, name) -> variant item dict
    variant_sets = []
    for variant_list in uv_conflicts:
        items = []
        for c in variant_list:
            package = canonicalize_name(c["package"])
            if "extra" in c:
                kind, vname = "extra", canonicalize_name(c["extra"])
            elif "group" in c:
                kind, vname = "group", canonicalize_name(c["group"])
            else:
                kind, vname = "project", ""
            key = (package, kind, vname)
            if key not in variant_items_by_key:
                item = {"package": package, "kind": kind}
                if vname:
                    item["name"] = vname
                variant_items_by_key[key] = item
            items.append(variant_items_by_key[key])
        variant_sets.append({"items": items})

    # Build constraint lookup from variants, keyed by (package, name) so a
    # conflict declared on one project's extra/group doesn't apply to a
    # same-named extra/group of another project.
    extra_variant_values = {}
    group_variant_values = {}
    project_variant_values = {}  # package -> qname, for `{package = ...}` conflicts
    token_replacements = []
    for item in variant_items_by_key.values():
        kind = item["kind"]
        vname = item.get("name", "")
        lookup_key = (item["package"], vname)
        qualified = variant_item_qname(item)
        if kind == "extra":
            extra_variant_values[lookup_key] = qualified
        elif kind == "group":
            group_variant_values[lookup_key] = qualified
        elif kind == "project":
            project_variant_values[item["package"]] = qualified
        uv_tok = _uv_conflict_token(item)
        var_tok = "__variant_{}".format(qualified)
        token_replacements.append(("'{}'".format(uv_tok), "'{}'".format(var_tok)))
        token_replacements.append(('"{}"'.format(uv_tok), '"{}"'.format(var_tok)))

    # Identify projects
    projects_list = getattr(lock_model, "projects", [])
    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    testonly_groups = getattr(lock_model, "testonly_groups", [])
    non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
    wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)

    workspace_members = {}
    for pkg in packages_list:
        if "virtual" in pkg.get("source", {}) or pkg.get("source", {}).get("editable"):
            workspace_members[canonicalize_name(pkg["name"])] = pkg

    if not workspace_members and packages_list:
        # Fallback for older uv.lock (< 0.2.35) or non-workspace setups.
        # It's a single-project lock. Just read the project name from pyproject.toml.
        pname = project_dict.get("project", {}).get("name")
        if pname:
            pname = canonicalize_name(pname)
            for pkg in packages_list:
                if canonicalize_name(pkg["name"]) == pname:
                    workspace_members[pname] = pkg
                    break

    target_projects = []
    if "*" in projects_list:
        target_projects = list(workspace_members.keys())
    else:
        target_projects = [canonicalize_name(p) for p in projects_list]

    for p in target_projects:
        if p in workspace_members:
            continue

        # Fallback for standalone single-project locks
        for pkg in packages_list:
            if canonicalize_name(pkg["name"]) == p:
                workspace_members[p] = pkg
                break
        if p not in workspace_members:
            fail("Project '{}' not found in uv.lock workspace members.".format(p))

    # User-facing `_variants` flags for this repo, for items declared by its own
    # projects (other projects' items get none):
    #   - `<kind>_<name>` (e.g. `group_test`) covers that extra/group in every
    #     project of the repo, like `uv --group test` across selected packages.
    #   - `<kind>_<project>_<name>` (e.g. `group_app-a_test`) covers one project,
    #     like `uv --package app-a --group test`.
    # Names are normalized (`-` only), so the two forms can't collide.
    target_projects_set = {p: True for p in target_projects}
    for item in variant_items_by_key.values():
        if item["package"] not in target_projects_set:
            continue
        if item["kind"] == "project":
            item["flags"] = ["package_{}".format(item["package"])]
        else:
            item["flags"] = [
                "{}_{}".format(item["kind"], item["name"]),
                "{}_{}_{}".format(item["kind"], item["package"], item["name"]),
            ]

    # Pre-scan: detect resolution-marker forks.
    # A fork exists when the same package name has multiple versions with
    # resolution-markers (i.e. uv resolved different versions for different
    # platforms).
    _fork_versions = {}  # {canonical_name: {version: [marker_expr, ...]}}
    for lock_pkg in packages_list:
        res_markers = [
            _rewrite_conflict_markers(m, token_replacements)
            for m in lock_pkg.get("resolution-markers", [])
        ]
        if not res_markers:
            continue
        fname = canonicalize_name(lock_pkg["name"])
        fversion = lock_pkg["version"]
        _fork_versions.setdefault(fname, {}).setdefault(fversion, []).extend(res_markers)

    # Build fork constraints for names with multiple versions.
    resolution_marker_exprs = {}  # constraint_name -> marker_expression
    _fork_constraints = {}  # {name: {version: constraint_name}}
    for fname, versions in _fork_versions.items():
        if len(versions) <= 1:
            continue  # Not a fork — single version, no conditional pin needed.
        for fversion, markers in versions.items():
            if len(markers) == 1:
                combined = markers[0]
            else:
                combined = " or ".join(["({})".format(m) for m in markers])
            cname = resolution_marker_constraint_name(fname, fversion)
            _fork_constraints.setdefault(fname, {})[fversion] = cname
            resolution_marker_exprs[cname] = combined

    # Collect requirements
    requirements = []  # list of (req_name, specifier, constraint, is_testonly)

    # Root dependency markers per exact pin; extras also record their implied
    # base package marker. See record_root_marker.
    root_dependency_markers = {}

    # In a repo spanning several projects, a requested extra/group applies to the
    # projects that declare it (like `uv --all-packages --group test`); it only
    # has to exist in one of them.
    multi_project = len(target_projects) > 1
    groups_seen = {"default": True}
    requested_by_project = {}  # project -> requested groups dict
    for project_name in target_projects:
        project_info = workspace_members[project_name]

        default_dependencies = project_info.get("dependencies", [])
        optional_dependencies = project_info.get("optional-dependencies", {})
        development_dependencies = project_info.get("dev-dependencies", {})

        # Parse groups. uv.lock leaves empty extras and groups (e.g. `cpu = []`
        # when only `[tool.uv.sources]` depends on it) out of
        # `optional-dependencies` and `dev-dependencies`, so also read them from
        # the package metadata and the conflict items.
        metadata = project_info.get("metadata", {})
        extra_names = list(optional_dependencies.keys()) + metadata.get("provides-extras", [])
        group_names = list(development_dependencies.keys()) + list(metadata.get("requires-dev", {}).keys())
        for item in variant_items_by_key.values():
            if item["package"] != project_name:
                continue
            if item["kind"] == "extra":
                extra_names.append(item["name"])
            elif item["kind"] == "group":
                group_names.append(item["name"])
        available_groups = ["default"]
        seen_canonical = {}
        for g in ["optional:" + n for n in extra_names] + ["group:" + n for n in group_names]:
            canonical = _canonicalize_group_key(g)
            if canonical not in seen_canonical:
                seen_canonical[canonical] = True
                available_groups.append(g)
        for g in available_groups:
            groups_seen[g] = True
        requested_groups_dict = compute_requested_dependency_groups(
            dependency_groups = dependency_groups,
            testonly_groups = testonly_groups,
            non_testonly_groups = non_testonly_groups,
            wildcard_testonly = wildcard_testonly,
            available_groups = available_groups,
            project_name = project_name,
            allow_missing = multi_project,
        )
        requested_by_project[project_name] = requested_groups_dict

        # A project in a `{package = ...}` conflict has all of its edges gated on
        # its project variant (uv marks them `extra == 'project-<n>-<name>'`).
        # Extras/groups with their own conflict variant use that instead.
        project_constraint = project_variant_values.get(project_name, "")
        group_batches = []
        if "default" in requested_groups_dict:
            group_batches.append((project_constraint, default_dependencies, requested_groups_dict["default"]))
        for kind, groups_dict, constraint_dict in [
            ("optional", optional_dependencies, extra_variant_values),
            ("group", development_dependencies, group_variant_values),
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
                dep_name = canonicalize_name(dep["name"])
                dep_version = dep.get("version", "")
                dep_extras = dep.get("extra") or dep.get("extras", [])
                dep_marker = _rewrite_conflict_markers(dep.get("marker", ""), token_replacements)
                specifier = "==={}".format(dep_version) if dep_version else ""

                # Resolution-marker fork: combine variant + fork constraints.
                base_dep_name = dep_name.split("[")[0]
                effective_constraint = _resolve_uv_dep_constraint(
                    constraint,
                    base_dep_name,
                    dep_version,
                    dep_marker,
                    _fork_constraints,
                    resolution_marker_exprs,
                )

                if dep_extras:
                    for extra in dep_extras:
                        pin_name = "{}[{}]".format(dep_name, canonicalize_name(extra))
                        record_root_marker(root_dependency_markers, pin_name, dep_marker)
                        requirements.append((pin_name, specifier, effective_constraint, is_testonly, dep_marker))

                # An extras pin implies its base package, so the base records
                # the same marker (an unmarked extras edge unlocks the base).
                record_root_marker(root_dependency_markers, base_dep_name, dep_marker)
                if not dep_extras:
                    requirements.append((dep_name, specifier, effective_constraint, is_testonly, dep_marker))

    # End collect requirements

    if multi_project:
        for group in dependency_groups:
            kind, sep, name = group.partition(":")
            if sep and name != "*" and group not in groups_seen:
                fail("None of the projects {} has group '{}'.".format(sorted(target_projects), group))

    # Pins and defaults for each conflict set in this repo.
    #
    # In uv, extras and groups are active only when requested. Here a project
    # item's (`{package = ...}`) variant gates all of that project's edges, so
    # it's active whenever the repo requests anything from the project. So if
    # this repo requests exactly one item of a set, that item is the selection,
    # as with `uv sync --extra cpu` or `uv sync --package app-a --group test`.
    # The repo's transition pins it through `_pin_<set>`. The workspace's
    # `__build` repo serves sdist builds for every repo, so it never pins.
    #
    # When the repo requests several items of a set, its default comes from the
    # selected pyproject's `[tool.uv] default-groups`. As in uv, a project's
    # default-groups name its own groups. The pyproject is the member's for a
    # single-project repo (`uv sync --package <member>`) and the root's
    # otherwise (`uv sync --all-packages`). A project whose default
    # dependencies the repo requests is a candidate too, so
    # `[{package = "a"}, {package = "b", group = "g"}]` defaults to `a` in a
    # repo that requests both. A set gets a default only if exactly one item
    # qualifies; otherwise a flag must select one. The repo's transition sets
    # `_default_<set>`, and the workspace repo has no static defaults.
    is_build_tools_repo = getattr(lock_model, "is_build_tools_repo", False)
    requested_keys = {
        project: {_canonicalize_group_key(key): True for key in requested.keys()}
        for project, requested in requested_by_project.items()
    }
    default_owner = canonicalize_name(project_dict.get("project", {}).get("name", ""))
    requested_by_set = []
    rival_requested = {}  # qname -> True if another requested item conflicts with it in some set
    for variant_set in variant_sets:
        owned_items = [item for item in variant_set["items"] if item["package"] in target_projects_set]
        requested_items = [item for item in owned_items if _is_item_requested(item, requested_keys[item["package"]])]
        requested_by_set.append((owned_items, requested_items))
        if requested_items:
            variant_set["repo_requested"] = [variant_item_qname(item) for item in requested_items]
        if len(requested_items) > 1:
            for item in requested_items:
                rival_requested[variant_item_qname(item)] = True

    for variant_set, (owned_items, requested_items) in zip(variant_sets, requested_by_set):
        # An item can be in several sets (e.g. `[[cpu, gpu], [cpu, gpu-test]]`).
        # Pin it only if the repo requests none of its rivals in any of them;
        # otherwise the sets could select conflicting items at once.
        # A set with at most one requested item gets no default either: a rival
        # elsewhere would make the default disagree with that set's selection.
        if len(requested_items) <= 1:
            if requested_items and not is_build_tools_repo:
                qname = variant_item_qname(requested_items[0])
                if qname not in rival_requested:
                    variant_set["repo_pin"] = qname
            continue

        candidates = []
        for item in owned_items:
            requested = requested_keys[item["package"]]
            if item["kind"] == "project":
                if "default" in requested:
                    candidates.append(item)
                continue
            if item["kind"] != "group" or item["package"] != default_owner:
                continue
            if uv_default_groups != "all" and item["name"] not in [canonicalize_name(g) for g in uv_default_groups]:
                continue
            if "group:" + item["name"] not in requested:
                continue
            candidates.append(item)
        if len(candidates) == 1:
            variant_set["repo_default"] = variant_item_qname(candidates[0])

    # uv can split one edge into several versions with conflict markers and no
    # `resolution-markers` on the packages (e.g. a group of a conflicted project:
    # `iniconfig 1.1.1; extra == 'project-1-a'` and `iniconfig 2.0.0;
    # extra != 'project-1-a'`). Under one constraint those would overwrite each
    # other, so give each version its own constraint from its edge markers.
    edges = {}  # (pin_name, constraint) -> {specifier: [markers]}
    for pin_name, specifier, constraint, _, dep_marker in requirements:
        edges.setdefault((pin_name, constraint), {}).setdefault(specifier, []).append(dep_marker)
    edge_constraints = {}  # (pin_name, constraint, specifier) -> constraint
    for (pin_name, constraint), by_specifier in edges.items():
        if len(by_specifier) <= 1:
            continue
        for specifier, markers in by_specifier.items():
            if "" in markers:
                continue  # an unmarked edge: can't narrow it
            unique = sorted({m: True for m in markers}.keys())
            marker = unique[0] if len(unique) == 1 else " or ".join(["({})".format(m) for m in unique])

            # Keyed by the marker so repos (whose requested groups can OR in
            # different edges) never map one name to different markers, and
            # identical markers share an evaluator.
            edge_constraint = "%s__edge_%x" % (
                resolution_marker_constraint_name(pin_name.split("[")[0], specifier.lstrip("=")),
                hash(marker) & 0xffffffff,
            )
            resolution_marker_exprs[edge_constraint] = marker
            if constraint:
                compound = "{}_{}".format(constraint, edge_constraint)
                resolution_marker_exprs[compound] = {"variant": constraint, "marker": edge_constraint}
                edge_constraint = compound
            edge_constraints[(pin_name, constraint, specifier)] = edge_constraint

    # Build pinned specs
    pinned_package_specs = {}
    testonly_reqs = {}
    non_testonly_reqs = {}
    for pin_name, specifier, constraint, is_testonly, _ in requirements:
        constraint = edge_constraints.get((pin_name, constraint, specifier), constraint)
        if pin_name not in pinned_package_specs:
            pinned_package_specs[pin_name] = {}
        pinned_package_specs[pin_name][constraint] = specifier

        base_pin_name = pin_name.split("[")[0]
        if is_testonly:
            testonly_reqs[base_pin_name] = True
        else:
            non_testonly_reqs[base_pin_name] = True

    testonly_pin_names = [name for name in testonly_reqs if name not in non_testonly_reqs]

    # A plain edge-split entry (from an edge outside the conflict, e.g. an
    # unconflicted project's `iniconfig; extra != 'project-1-a'`) can sit in a
    # pin next to entries for that conflict set's variants. With no variant
    # selected it would match alongside the `_unselected_<set>` error branch and
    # make the select() ambiguous.
    #   - If every item of the set has its own (un-narrowed) entry, the edge entry
    #     is redundant: uv resolves one version per fork, so it agrees with them
    #     whenever a variant is selected. Drop it.
    #   - Otherwise (e.g. `b` doesn't depend on the package at all), the edge
    #     entry is still needed for the uncovered items: narrow it to "some
    #     variant of the set is selected", so it's false when none is.
    set_qnames = [[variant_item_qname(item) for item in vs["items"]] for vs in variant_sets]
    for pin_name, specs in pinned_package_specs.items():
        variant_qnames = {}
        for key in specs.keys():
            expr = resolution_marker_exprs.get(key)
            variant_qnames[expr["variant"] if type(expr) == "dict" else key] = True
        for key in list(specs.keys()):
            expr = resolution_marker_exprs.get(key)
            if type(expr) != "string" or "__edge_" not in key:
                continue
            guards = []
            drop = False
            for qnames in set_qnames:
                if not [q for q in qnames if "'__variant_{}'".format(q) in expr]:
                    continue
                if not [q for q in qnames if q in variant_qnames]:
                    continue
                if all([q in specs for q in qnames]):
                    drop = True
                    break
                guards.append("(" + " or ".join(["extra == '__variant_{}'".format(q) for q in qnames]) + ")")
            if drop:
                specs.pop(key)
            elif guards:
                specifier = specs.pop(key)
                narrowed = " and ".join(guards + ["({})".format(expr)])
                narrowed_key = "%s__edge_%x" % (
                    resolution_marker_constraint_name(pin_name.split("[")[0], specifier.lstrip("=")),
                    hash(narrowed) & 0xffffffff,
                )
                resolution_marker_exprs[narrowed_key] = narrowed
                specs[narrowed_key] = specifier

    # Process all packages from lock
    packages = []
    for lock_pkg in packages_list:
        package_name = canonicalize_name(lock_pkg["name"])
        package_version = lock_pkg["version"]
        resolution_markers = [
            _rewrite_conflict_markers(m, token_replacements)
            for m in lock_pkg.get("resolution-markers", [])
        ]
        python_version_specifiers = _resolve_package_requires_python(resolution_markers)
        package_extras = lock_pkg.get("extras", [])

        # Parse base dependencies
        deps = []
        for dep in lock_pkg.get("dependencies", []):
            deps.extend(_parse_uv_dependency(dep, token_replacements))

        # Parse files: wheels + sdist
        files = []
        source = lock_pkg.get("source", {})
        registry = source.get("registry")

        for w in lock_pkg.get("wheels", []):
            files.append(_parse_file_info(w, package_name, package_version, registry))

        sdist = lock_pkg.get("sdist", {})
        sdist_file = _parse_sdist_file(sdist, source, package_name, package_version, registry)
        if sdist_file:
            files.append(sdist_file)

        # Source dir
        source_dir = source.get("subdirectory", "")

        # Handle git sources
        if "git" in source and not files:
            git_url = source["git"]

            # Extract commit from fragment
            commit = ""
            if "#" in git_url:
                commit = git_url.split("#")[-1]

            # uv records git subdirectories in the URL query: ?subdirectory=a%2Fb&rev=...
            if "?" in git_url:
                query = git_url.split("#")[0].split("?", 1)[1]
                for param in query.split("&"):
                    if param.startswith("subdirectory="):
                        source_dir = url_decode_filename(param[len("subdirectory="):])
            if commit:
                synthetic_hash = sha256_from_string(commit)
                filename = "{}-{}.tar.gz".format(package_name, package_version)
                files.append({
                    "name": filename,
                    "sha256": synthetic_hash,
                    "urls": ["git+" + git_url],
                    "package_name": package_name,
                    "package_version": package_version,
                })

        # Detect local packages
        is_local_editable = "editable" in source and type(source.get("editable")) == "string"
        is_local_virtual = "virtual" in source and type(source.get("virtual")) == "string"
        is_local_directory = "directory" in source
        is_local_sdist = type(sdist) == "dict" and "path" in sdist and "url" not in sdist
        is_local = is_local_sdist or is_local_editable or is_local_virtual or is_local_directory

        pkg_python_versions = python_version_specifiers[0] if python_version_specifiers else ""

        # Base package
        base_pkg = {
            "name": package_name,
            "version": package_version,
            "python_versions": pkg_python_versions,
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [e.lower() for e in package_extras],
        }
        if source_dir:
            base_pkg["source_dir"] = source_dir
        packages.append(base_pkg)

        # Extra packages (UV's optional-dependencies within the lock package)
        for extra_name, extra_deps_list in lock_pkg.get("optional-dependencies", {}).items():
            extra_parsed_deps = []
            for dep in extra_deps_list:
                extra_parsed_deps.extend(_parse_uv_dependency(dep, token_replacements))

            # Add self-dependency
            extra_parsed_deps.append({
                "name": package_name,
                "specifier": "==={}".format(package_version),
                "marker": "",
                "extras": [None],
            })

            extra_pkg_name = "{}[{}]".format(package_name, canonicalize_name(extra_name))
            extra_pkg = {
                "name": extra_pkg_name,
                "version": package_version,
                "python_versions": pkg_python_versions,
                "dependencies": extra_parsed_deps,
                "files": [],
                "is_local": is_local,
                "extras": [],
            }
            if source_dir:
                extra_pkg["source_dir"] = source_dir
            packages.append(extra_pkg)

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = requires_python,
        strict_dependencies = True,
        variants = variant_sets,
        resolution_marker_exprs = resolution_marker_exprs,
        testonly_pins = testonly_pin_names,
        root_dependency_markers = root_dependency_markers,
    )

def repo_create_uv_model(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Run the UV translator in pure Starlark."""
    project_dict, lock_dict = read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, "uv.lock", toml_cache)
    return translate_uv(project_dict, lock_dict, lock_model)
