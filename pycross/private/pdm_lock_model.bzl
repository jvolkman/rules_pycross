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
    "expand_pep735_group",
    "parse_pep508_requirement",
    "read_projects_and_lock",
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

def _merge_pin_spec(existing_spec, new_spec, existing_marked, new_marked):
    """Merge two root pin specifiers for the same package."""
    if existing_marked or new_marked:
        if not existing_spec or not new_spec:
            return ""
        if existing_spec == new_spec:
            return new_spec
        return existing_spec + " || " + new_spec
    if not new_spec:
        return existing_spec
    if not existing_spec or existing_spec == new_spec:
        return new_spec
    return existing_spec + "," + new_spec

def translate_pdm(project_dict, lock_dict, lock_model):
    """Translates PDM project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml dict, or list of parsed pyproject.toml dicts
            when translating multiple workspace projects.
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

    project_dicts = project_dict if type(project_dict) == "list" else [project_dict]
    multi_project = len(project_dicts) > 1

    requires_python = ""
    for p_dict in project_dicts:
        rp = p_dict.get("project", {}).get("requires-python", "")
        if rp:
            requires_python = rp
            break

    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    testonly_groups = getattr(lock_model, "testonly_groups", [])
    non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
    wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)

    # Collect requirements based on group selection across all selected projects.
    requirements = []
    groups_seen = {}
    project_names = []

    for p_dict in project_dicts:
        project_section = p_dict.get("project", {})
        project_name = project_section.get("name")
        if project_name:
            project_names.append(project_name)

        default_deps = project_section.get("dependencies", [])
        optional_deps = project_section.get("optional-dependencies", {})

        # Development dependencies: dependency-groups + legacy tool.pdm.dev-dependencies
        dev_deps = dict(p_dict.get("dependency-groups", {}))
        legacy_dev_deps = p_dict.get("tool", {}).get("pdm", {}).get("dev-dependencies", {})
        if legacy_dev_deps:
            for group_name, deps in legacy_dev_deps.items():
                if group_name in dev_deps:
                    fail("PDM error: group '{}' cannot appear in both [dependency-groups] and [tool.pdm.dev-dependencies]".format(group_name))
                dev_deps[group_name] = deps

        # Enforce PDM PEP 735 rule
        for group_name in dev_deps:
            if group_name in optional_deps:
                fail("PDM error: the same group name '{}' MUST NOT appear in both development groups and [project.optional-dependencies]".format(group_name))

        available_groups = (
            ["default"] +
            ["optional:" + g for g in optional_deps.keys()] +
            ["group:" + g for g in dev_deps.keys()]
        )
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

        if "default" in requested_groups_dict:
            default_is_testonly = requested_groups_dict["default"]
            for dep_str in default_deps:
                requirements.append((parse_pep508_requirement(dep_str), default_is_testonly))

        for target_name in optional_deps.keys():
            key = "optional:{}".format(target_name)
            if key not in requested_groups_dict:
                continue
            is_testonly = requested_groups_dict[key]
            for dep_str in optional_deps[target_name]:
                if type(dep_str) == "string":
                    requirements.append((parse_pep508_requirement(dep_str), is_testonly))

        for target_name in dev_deps.keys():
            key = "group:{}".format(target_name)
            if key not in requested_groups_dict:
                continue
            is_testonly = requested_groups_dict[key]
            for dep_str in expand_pep735_group(dev_deps, target_name):
                requirements.append((parse_pep508_requirement(dep_str), is_testonly))

    if multi_project:
        for group in dependency_groups:
            _, sep, name = group.partition(":")
            if sep and name != "*" and group not in groups_seen:
                fail("None of the projects {} has group '{}'.".format(sorted(project_names), group))

    # Build pinned specs from requirements
    pinned_package_specs = {}
    pinned_has_marker = {}
    testonly_reqs = {}
    non_testonly_reqs = {}
    root_dependency_markers = {}
    for req, is_testonly in requirements:
        # name[extra] pins resolve to the base version; lock_resolver
        # synthesizes the extra package from the base's extra-gated edges.
        for pin_name in [req.name] + ["{}[{}]".format(req.name, canonicalize_name(e)) for e in req.extras]:
            if pin_name not in pinned_package_specs:
                pinned_package_specs[pin_name] = {"": req.specifier}
            else:
                existing_spec = pinned_package_specs[pin_name].get("", "")
                merged_spec = _merge_pin_spec(
                    existing_spec,
                    req.specifier,
                    pinned_has_marker.get(pin_name, False),
                    bool(req.marker),
                )
                pinned_package_specs[pin_name] = {"": merged_spec}
            if req.marker:
                pinned_has_marker[pin_name] = True
            record_root_marker(root_dependency_markers, pin_name, req.marker)
            if is_testonly:
                testonly_reqs[pin_name] = True
            else:
                non_testonly_reqs[pin_name] = True

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

        # Parse dependencies as PEP 508 requirement strings.
        # PDM models extra combinations as separate [[package]] entries with
        # `extras = [...]` whose dependencies omit `; extra == "..."` markers
        # and include a self-edge to the base package. Synthesize the extra
        # marker (when not already present) and drop the base self-edge so
        # merging into the base package keeps bare `pkg` free of extra deps.
        norm_extras = list({canonicalize_name(e): True for e in pkg_extras}.keys())
        extra_marker = " or ".join(['extra == "{}"'.format(e) for e in norm_extras])
        deps = []
        for dep_str in lock_pkg.get("dependencies", []):
            parsed = parse_pep508_requirement(dep_str)
            if norm_extras and parsed.name == name and not parsed.extras:
                continue
            dep_marker = parsed.marker
            if extra_marker and "extra" not in dep_marker:
                if dep_marker:
                    wrapped_extra = "({})".format(extra_marker) if len(norm_extras) > 1 else extra_marker
                    dep_marker = "({}) and {}".format(dep_marker, wrapped_extra)
                else:
                    dep_marker = extra_marker
            deps.append({
                "name": parsed.name,
                "specifier": parsed.specifier,
                "marker": dep_marker,
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
            "extras": norm_extras,
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

def repo_create_pdm_model(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Run the PDM translator in pure Starlark."""
    project_dicts, lock_dict = read_projects_and_lock(rctx, extra_project_files, lock_file, lock_model, "pdm.lock", toml_cache)
    return translate_pdm(project_dicts, lock_dict, lock_model)
