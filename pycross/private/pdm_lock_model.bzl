"""Starlark PDM translator.

Replaces the Python pdm_translator.py with a pure-Starlark implementation.
Parses pdm.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.
"""

load("@toml.bzl//toml:toml.bzl", "decode")
load(
    ":translator_common.bzl",
    "canonicalize_name",
    "parse_pep508_requirement",
    "resolution_marker_constraint_name",
    "resolve_lock_graph",
    "select_project_file",
)
load(":util.bzl", "url_decode_filename")

def _parse_file_info(file_info, package_name, package_version):
    """Parse a PDM lock file entry into a file dict.

    Args:
        file_info: A dict with "file" or "url" and "hash" keys.
        package_name: The name of the package.
        package_version: The version of the package.

    Returns:
        A dict with name, sha256, package_name, package_version, and optionally urls.
    """
    if "file" in file_info:
        filename = file_info["file"]
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

        filename = url_decode_filename(filename)
        urls = [url]
    else:
        fail("PDM file entry has no 'file' or 'url' member")

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
    return result

def translate_pdm(project_dict, lock_dict, lock_model):
    """Translates PDM project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml as a dict.
        lock_dict: Parsed pdm.lock as a dict.
        lock_model: A struct containing the lock model attributes.

    Returns:
        A dict in raw_lock.json format.
    """

    # Version check
    lock_version = lock_dict.get("metadata", {}).get("lock_version", "")
    if not lock_version:
        fail("PDM lock file has no version")

    # Check ~=4.0 compatibility: major must be 4
    v_parts = lock_version.split(".")
    if len(v_parts) < 1 or v_parts[0] != "4":
        fail("PDM lock file version {} not in supported range ~=4.0".format(lock_version))

    # Parse project dependencies
    default_deps = project_dict.get("project", {}).get("dependencies", [])
    optional_deps = project_dict.get("project", {}).get("optional-dependencies", {})

    # Development dependencies: dependency-groups + legacy tool.pdm.dev-dependencies
    dev_deps = dict(project_dict.get("dependency-groups", {}))
    legacy_dev_deps = project_dict.get("tool", {}).get("pdm", {}).get("dev-dependencies", {})
    if legacy_dev_deps:
        for group_name, deps in legacy_dev_deps.items():
            if group_name in dev_deps:
                fail("PDM error: group '{}' cannot appear in both [dependency-groups] and [tool.pdm.dev-dependencies]".format(group_name))
            dev_deps[group_name] = deps

    # Enforce PDM PEP 735 rule
    for group_name in dev_deps:
        if group_name in optional_deps:
            fail("PDM error: the same group name '{}' MUST NOT appear in both development groups and [project.optional-dependencies]".format(group_name))

    requires_python = project_dict.get("project", {}).get("requires-python", "")

    # Collect requirements based on group selection
    requirements = []

    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    include_all = "*" in dependency_groups
    include_default = "default" in dependency_groups or include_all

    if include_default:
        for dep_str in default_deps:
            requirements.append(parse_pep508_requirement(dep_str))

    effective_groups = ["optional:*", "group:*"] if include_all else dependency_groups
    for group in effective_groups:
        if group == "default" or group == "*":
            continue

        kind, _, name = group.partition(":")
        if kind == "optional":
            groups_dict = optional_deps
        elif kind == "group":
            groups_dict = dev_deps
        else:
            fail("Invalid dependency group format '{}'. Must be 'optional:name' or 'group:name'.".format(group))

        if name == "*":
            target_names = list(groups_dict.keys())
        else:
            target_names = [name]

        for target_name in target_names:
            if target_name in groups_dict:
                entries = groups_dict[target_name]
                for dep_str in entries:
                    if type(dep_str) == "string":
                        # Strip editable markers
                        stripped = dep_str.strip()
                        if stripped.startswith("-e "):
                            stripped = stripped[3:].strip()
                        requirements.append(parse_pep508_requirement(stripped))
                    elif type(dep_str) == "dict" and "include-group" in dep_str:
                        inc_group = dep_str["include-group"]
                        if inc_group in dev_deps:
                            for inc_dep in dev_deps[inc_group]:
                                if type(inc_dep) == "string":
                                    stripped = inc_dep.strip()
                                    if stripped.startswith("-e "):
                                        stripped = stripped[3:].strip()
                                    requirements.append(parse_pep508_requirement(stripped))
            else:
                fail("Non-existent {} dependency group: {}".format(kind, target_name))

    # Build pinned specs from requirements
    pinned_package_specs = {}
    for req in requirements:
        pinned_package_specs[req.name] = {"": req.specifier}

    # Parse lock packages
    packages = []
    for lock_pkg in lock_dict.get("package", []):
        name = canonicalize_name(lock_pkg["name"])
        version = lock_pkg["version"]
        pkg_requires_python = lock_pkg.get("requires_python", "")
        pkg_extras = lock_pkg.get("extras", [])

        if pkg_requires_python == "*":
            pkg_requires_python = ""

        # Read package-level markers (PDM multi-target lock files)
        package_markers = lock_pkg.get("marker", "")

        # Parse dependencies as PEP 508 requirement strings
        deps = []
        for dep_str in lock_pkg.get("dependencies", []):
            parsed = parse_pep508_requirement(dep_str)
            deps.append({
                "name": parsed.name,
                "specifier": parsed.specifier,
                "marker": parsed.marker,
                "extras": parsed.extras if parsed.extras else [None],
            })

        # Parse files
        files = []
        for f in lock_pkg.get("files", []):
            files.append(_parse_file_info(f, name, version))

        is_local = "path" in lock_pkg and "files" not in lock_pkg

        packages.append({
            "name": name,
            "version": version,
            "python_versions": pkg_requires_python,
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [e.lower() for e in pkg_extras],
            "markers": package_markers,
        })

    # Detect resolution-marker forks: same package name with multiple versions.
    resolution_marker_exprs = {}
    fork_versions = {}  # {name: {version: marker_expr}}
    for pkg in packages:
        marker = pkg.get("markers", "")
        if not marker:
            continue
        fork_versions.setdefault(pkg["name"], {})[pkg["version"]] = marker

    fork_constraints = {}  # {name: {version: constraint_name}}
    for fname, versions in fork_versions.items():
        if len(versions) <= 1:
            continue  # Single version, no fork.
        for fversion, marker_expr in versions.items():
            cname = resolution_marker_constraint_name(fname, fversion)
            fork_constraints.setdefault(fname, {})[fversion] = cname
            resolution_marker_exprs[cname] = marker_expr

    # If forks were detected, update pinned_package_specs to use conditional pins.
    for fname, version_constraints in fork_constraints.items():
        if fname in pinned_package_specs:
            conditional_pins = {}
            for fversion, cname in version_constraints.items():
                conditional_pins[cname] = "==" + fversion
            pinned_package_specs[fname] = conditional_pins

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = requires_python,
        strict_dependencies = False,
        resolution_marker_exprs = resolution_marker_exprs,
    )

def repo_create_pdm_model(rctx, extra_project_files, lock_file, lock_model, output):
    """Run the PDM translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of extra pyproject.toml files.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pdm_lock_model rule.
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
        fail("Lock file not found: {}. Ensure pdm.lock exists at the expected location.".format(lock_file))

    lock_dict = decode(rctx.read(lock_path))
    raw_lock_data = translate_pdm(project_dict, lock_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
