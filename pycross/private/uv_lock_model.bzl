"""Starlark UV translator.

Replaces the Python uv_translator.py with a pure-Starlark implementation.
Parses uv.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.

Handles UV-specific features: workspace members, conflicts/variants,
resolution markers, git sources, and editable packages.
"""

load("@toml.bzl//toml:toml.bzl", "decode")
load(
    ":translator_common.bzl",
    "canonicalize_name",
    "compute_requested_dependency_groups",
    "resolution_marker_constraint_name",
    "resolve_lock_graph",
    "select_project_file",
    "sha256_from_string",
)

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
        filename = path_part.split("/")[-1]
        urls = [url]
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
        if "python_full_version" in marker:
            # Parse out the operator and version
            parts = marker.strip().split("python_full_version")
            if len(parts) == 2:
                rest = parts[1].strip()

                # Extract operator
                op = ""
                for c in rest.elems():
                    if c in "<>=!":
                        op += c
                    elif c == " " and op:
                        break
                    elif op:
                        break
                version_part = rest[len(op):].strip().strip("'\"")
                if op and version_part:
                    specifiers.append("{} {}".format(op, version_part))
    return specifiers

def _parse_uv_dependency(dep):
    """Parse a UV lock dependency dict into a specifier.

    Args:
        dep: Dict with name, version, marker, extra/extras keys.

    Returns:
        A list of dep dicts suitable for resolve_lock_graph.
    """
    name = dep.get("name", "")
    version = dep.get("version", "")
    marker = dep.get("marker", "")
    extras = dep.get("extra") or dep.get("extras", [])

    results = []
    if extras:
        for extra in extras:
            dep_name = "{}[{}]".format(canonicalize_name(name), canonicalize_name(extra))
            specifier = "=={}".format(version) if version else ""
            results.append({
                "name": dep_name,
                "specifier": specifier,
                "marker": marker,
                "extras": [None],
            })
    else:
        specifier = "=={}".format(version) if version else ""
        results.append({
            "name": canonicalize_name(name),
            "specifier": specifier,
            "marker": marker,
            "extras": [None],
        })

    return results

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
            package = c["package"]
            if "extra" in c:
                kind, vname = "extra", c["extra"]
            elif "group" in c:
                kind, vname = "group", c["group"]
            else:
                kind, vname = "project", ""
            key = (package, kind, vname)
            if key not in variant_items_by_key:
                item = {"package": package, "kind": kind}
                if vname:
                    item["name"] = vname
                if kind == "group" and vname in uv_default_groups:
                    item["default"] = True
                variant_items_by_key[key] = item
            items.append(variant_items_by_key[key])
        variant_sets.append({"items": items})

    # Build constraint lookup from variants
    extra_variant_values = {}
    group_variant_values = {}
    for item in variant_items_by_key.values():
        kind = item["kind"]
        vname = item.get("name", "")
        if kind == "extra":
            qualified = "extra_{}".format(vname)
            extra_variant_values[vname] = qualified
        elif kind == "group":
            qualified = "group_{}".format(vname)
            group_variant_values[vname] = qualified

    # Identify projects
    projects_list = getattr(lock_model, "projects", [])
    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    testonly_groups = getattr(lock_model, "testonly_groups", [])
    non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
    wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)

    workspace_members = {}
    for pkg in packages_list:
        if pkg.get("source", {}).get("virtual") == "." or pkg.get("source", {}).get("editable"):
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
        if p not in workspace_members:
            # Fallback for standalone single-project locks
            found = False
            for pkg in packages_list:
                if canonicalize_name(pkg["name"]) == p:
                    workspace_members[p] = pkg
                    found = True
                    break
            if not found:
                fail("Project '{}' not found in uv.lock workspace members.".format(p))

    # Pre-scan: detect resolution-marker forks.
    # A fork exists when the same package name has multiple versions with
    # resolution-markers (i.e. uv resolved different versions for different
    # platforms).
    _fork_versions = {}  # {canonical_name: {version: [marker_expr, ...]}}
    for lock_pkg in packages_list:
        res_markers = lock_pkg.get("resolution-markers", [])
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



    for project_name in target_projects:
        project_info = workspace_members[project_name]

        default_dependencies = project_info.get("dependencies", [])
        optional_dependencies = project_info.get("optional-dependencies", {})
        development_dependencies = project_info.get("dev-dependencies", {})

        # Parse groups
        requested_groups_dict = compute_requested_dependency_groups(
            dependency_groups = dependency_groups,
            testonly_groups = testonly_groups,
            non_testonly_groups = non_testonly_groups,
            wildcard_testonly = wildcard_testonly,
            available_groups = (
                ["default"] +
                ["optional:" + g for g in optional_dependencies.keys()] +
                ["group:" + g for g in development_dependencies.keys()]
            ),
            project_name = project_name,
            fail_on_missing = True,
        )

        if "default" in requested_groups_dict:
            default_is_testonly = requested_groups_dict["default"]
            for dep in default_dependencies:
                dep_name = canonicalize_name(dep["name"])
                dep_version = dep.get("version", "")
                dep_extras = dep.get("extra") or dep.get("extras", [])
                specifier = "=={}".format(dep_version) if dep_version else ""

                # Resolution-marker fork: use per-version constraint.
                base_dep_name = dep_name.split("[")[0]
                if base_dep_name in _fork_constraints and dep_version in _fork_constraints[base_dep_name]:
                    fork_constraint = _fork_constraints[base_dep_name][dep_version]
                else:
                    fork_constraint = ""

                if dep_extras:
                    for extra in dep_extras:
                        pin_name = "{}[{}]".format(dep_name, canonicalize_name(extra))
                        requirements.append((pin_name, specifier, fork_constraint, default_is_testonly))
                else:
                    requirements.append((dep_name, specifier, fork_constraint, default_is_testonly))



        for kind, groups_dict, constraint_dict in [("optional", optional_dependencies, extra_variant_values), ("group", development_dependencies, group_variant_values)]:
            for group_name in groups_dict.keys():
                key = "{}:{}".format(kind, group_name)
                if key not in requested_groups_dict:
                    continue
                is_testonly = requested_groups_dict[key]
                constraint = constraint_dict.get(group_name, "")
                for dep in groups_dict[group_name]:
                    dep_name = canonicalize_name(dep["name"])
                    dep_version = dep.get("version", "")
                    dep_extras = dep.get("extra") or dep.get("extras", [])
                    specifier = "=={}".format(dep_version) if dep_version else ""

                    # Resolution-marker fork: combine variant + fork constraints.
                    base_dep_name = dep_name.split("[")[0]
                    if base_dep_name in _fork_constraints and dep_version in _fork_constraints[base_dep_name]:
                        fork_constraint = _fork_constraints[base_dep_name][dep_version]
                        if constraint:
                            effective_constraint = "{}_{}".format(constraint, fork_constraint)

                            # Register compound constraint with its components.
                            resolution_marker_exprs[effective_constraint] = {
                                "variant": constraint,
                                "marker": fork_constraint,
                            }
                        else:
                            effective_constraint = fork_constraint
                    else:
                        effective_constraint = constraint

                    if dep_extras:
                        for extra in dep_extras:
                            pin_name = "{}[{}]".format(dep_name, canonicalize_name(extra))
                            requirements.append((pin_name, specifier, effective_constraint, is_testonly))
                    else:
                        requirements.append((dep_name, specifier, effective_constraint, is_testonly))

    # End collect requirements

    # Build pinned specs
    pinned_package_specs = {}
    testonly_reqs = {}
    non_testonly_reqs = {}
    for pin_name, specifier, constraint, is_testonly in requirements:
        if pin_name not in pinned_package_specs:
            pinned_package_specs[pin_name] = {}
        pinned_package_specs[pin_name][constraint] = specifier

        base_pin_name = pin_name.split("[")[0]
        if is_testonly:
            testonly_reqs[base_pin_name] = True
        else:
            non_testonly_reqs[base_pin_name] = True

    testonly_pin_names = [name for name in testonly_reqs if name not in non_testonly_reqs]

    # Process all packages from lock
    packages = []
    for lock_pkg in packages_list:
        package_name = canonicalize_name(lock_pkg["name"])
        package_version = lock_pkg["version"]
        resolution_markers = lock_pkg.get("resolution-markers", [])
        python_version_specifiers = _resolve_package_requires_python(resolution_markers)
        package_extras = lock_pkg.get("extras", [])

        # Parse base dependencies
        deps = []
        for dep in lock_pkg.get("dependencies", []):
            deps.extend(_parse_uv_dependency(dep))

        # Parse files: wheels + sdist
        files = []
        source = lock_pkg.get("source", {})
        registry = source.get("registry")

        for w in lock_pkg.get("wheels", []):
            files.append(_parse_file_info(w, package_name, package_version, registry))

        sdist = lock_pkg.get("sdist", {})

        if sdist:
            if "url" in sdist or "file" in sdist:
                files.append(_parse_file_info(sdist, package_name, package_version, registry))
            elif "url" in source:
                # URL-based source with subdirectory
                url = source["url"]
                file_hash = sdist["hash"]
                if not file_hash.startswith("sha256:"):
                    fail("Expected sha256: prefix on hash")
                filename = "{}-{}.tar.gz".format(package_name, package_version)
                f = {
                    "name": filename,
                    "sha256": file_hash[7:],
                    "urls": [url],
                    "package_name": package_name,
                    "package_version": package_version,
                }
                if registry:
                    f["index"] = registry
                files.append(f)
            elif "git" in source:
                pass  # handled below
            else:
                files.append(_parse_file_info(sdist, package_name, package_version, registry))

        # Handle git sources
        if "git" in source and not files:
            git_url = source["git"]

            # Extract commit from fragment
            commit = ""
            if "#" in git_url:
                commit = git_url.split("#")[-1]
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

        # Source dir
        source_dir = source.get("subdirectory", "")

        # Detect local packages
        is_local_editable = "editable" in source and type(source.get("editable")) == "string"
        is_local_virtual = "virtual" in source and type(source.get("virtual")) == "string"
        is_local_sdist = type(sdist) == "dict" and "path" in sdist and "url" not in sdist
        is_local = is_local_sdist or is_local_editable or is_local_virtual

        # Base package
        base_pkg = {
            "name": package_name,
            "version": package_version,
            "python_versions": python_version_specifiers[0] if python_version_specifiers else "",
            "python_version_specifiers": python_version_specifiers,
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
                extra_parsed_deps.extend(_parse_uv_dependency(dep))

            # Add self-dependency
            extra_parsed_deps.append({
                "name": package_name,
                "specifier": "=={}".format(package_version),
                "marker": "",
                "extras": [None],
            })

            extra_pkg_name = "{}[{}]".format(package_name, canonicalize_name(extra_name))
            extra_pkg = {
                "name": extra_pkg_name,
                "version": package_version,
                "python_versions": python_version_specifiers[0] if python_version_specifiers else "",
                "python_version_specifiers": python_version_specifiers,
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
    )

def repo_create_uv_model(rctx, extra_project_files, lock_file, lock_model, output):
    """Run the UV translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of extra pyproject.toml files.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_uv_lock_model rule.
        output: the output file.
    """

    projects = getattr(lock_model, "projects", [])
    project_file = select_project_file(rctx, extra_project_files, lock_file, projects)

    project_dict = {}
    if project_file:
        project_path = rctx.path(project_file)
        if project_path.exists:
            project_dict = decode(rctx.read(project_path))

    lock_path = rctx.path(lock_file)
    if not lock_path.exists:
        fail("Lock file not found: {}. Ensure uv.lock exists at the expected location.".format(lock_file))

    lock_dict = decode(rctx.read(lock_path))
    raw_lock_data = translate_uv(project_dict, lock_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
