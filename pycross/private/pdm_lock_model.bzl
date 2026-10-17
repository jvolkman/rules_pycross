"""Starlark PDM translator.

Replaces the Python pdm_translator.py with a pure-Starlark implementation.
Parses pdm.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.
"""

load(
    ":translator_common.bzl",
    "canonicalize_name",
    "compute_requested_dependency_groups",
    "detect_package_marker_forks",
    "parse_pep508_requirement",
    "read_project_and_lock",
    "record_root_marker",
    "resolve_lock_graph",
    "sha256_from_string",
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

    project_section = project_dict.get("project", {})
    project_name = project_section.get("name")

    # Parse project dependencies
    default_deps = project_section.get("dependencies", [])
    optional_deps = project_section.get("optional-dependencies", {})

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

    testonly_groups = getattr(lock_model, "testonly_groups", [])
    non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
    wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)

    requested_groups_dict = compute_requested_dependency_groups(
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

    if "default" in requested_groups_dict:
        default_is_testonly = requested_groups_dict["default"]
        for dep_str in default_deps:
            requirements.append((parse_pep508_requirement(dep_str), default_is_testonly))

    for kind, groups_dict in [("optional", optional_deps), ("group", dev_deps)]:
        for target_name in groups_dict.keys():
            key = "{}:{}".format(kind, target_name)
            if key not in requested_groups_dict:
                continue
            is_testonly = requested_groups_dict[key]

            for dep_str in groups_dict[target_name]:
                if type(dep_str) == "string":
                    requirements.append((parse_pep508_requirement(dep_str), is_testonly))
                elif type(dep_str) == "dict" and "include-group" in dep_str:
                    inc_group = dep_str["include-group"]
                    for inc_dep in dev_deps.get(inc_group, []):
                        if type(inc_dep) == "string":
                            requirements.append((parse_pep508_requirement(inc_dep), is_testonly))

    # Build pinned specs from requirements
    pinned_package_specs = {}
    testonly_reqs = {}
    non_testonly_reqs = {}
    root_dependency_markers = {}
    for req, is_testonly in requirements:
        pinned_package_specs[req.name] = {"": req.specifier}
        if req.extras:
            for extra in req.extras:
                pin_name = "{}[{}]".format(req.name, canonicalize_name(extra))
                record_root_marker(root_dependency_markers, pin_name, req.marker)
        record_root_marker(root_dependency_markers, req.name, req.marker)
        if is_testonly:
            testonly_reqs[req.name] = True
        else:
            non_testonly_reqs[req.name] = True

    testonly_pin_names = [name for name in testonly_reqs if name not in non_testonly_reqs]

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

        # Git dependencies have no files; fetch the pinned revision instead.
        if "git" in lock_pkg and not files:
            revision = lock_pkg.get("revision")
            if not revision:
                fail("PDM git package {}=={} has no revision".format(name, version))
            files.append({
                "name": "{}-{}.tar.gz".format(name, version),
                "sha256": sha256_from_string(revision),
                "urls": ["git+{}#{}".format(lock_pkg["git"], revision)],
                "package_name": name,
                "package_version": version,
            })

        is_local = "path" in lock_pkg and "files" not in lock_pkg

        pkg = {
            "name": name,
            "version": version,
            "python_versions": pkg_requires_python,
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [e.lower() for e in pkg_extras],
            "markers": package_markers,
        }
        if lock_pkg.get("subdirectory"):
            pkg["source_dir"] = lock_pkg["subdirectory"]
        packages.append(pkg)

    resolution_marker_exprs = detect_package_marker_forks(packages, pinned_package_specs)

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = requires_python,
        strict_dependencies = False,
        resolution_marker_exprs = resolution_marker_exprs,
        testonly_pins = testonly_pin_names,
        root_dependency_markers = root_dependency_markers,
    )

def repo_create_pdm_model(rctx, extra_project_files, lock_file, lock_model):
    """Run the PDM translator in pure Starlark."""
    project_dict, lock_dict = read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, "pdm.lock")
    return translate_pdm(project_dict, lock_dict, lock_model)
