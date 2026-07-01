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
    "resolve_lock_graph",
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
    legacy_dev_deps = project_dict.get("tool", {}).get("pdm", {}).get("dev-dependencies", [])
    if legacy_dev_deps:
        existing = dev_deps.get("dev", [])

        # Merge and deduplicate
        merged = list(existing)
        for d in legacy_dev_deps:
            if d not in merged:
                merged.append(d)
        dev_deps["dev"] = merged

    requires_python = project_dict.get("project", {}).get("requires-python", "")

    # Collect requirements based on group selection
    requirements = []

    if lock_model.default_group:
        for dep_str in default_deps:
            requirements.append(parse_pep508_requirement(dep_str))

    if lock_model.all_optional_groups:
        opt_groups = sorted(optional_deps.keys())
    else:
        opt_groups = getattr(lock_model, "optional_groups", [])

    for group_name in opt_groups:
        if group_name not in optional_deps:
            fail("Non-existent optional dependency group: {}".format(group_name))
        for dep_str in optional_deps[group_name]:
            requirements.append(parse_pep508_requirement(dep_str))

    if getattr(lock_model, "all_development_groups", False):
        dev_groups = sorted(dev_deps.keys())
    else:
        dev_groups = getattr(lock_model, "development_groups", [])

    for group_name in dev_groups:
        if group_name not in dev_deps:
            fail("Non-existent development dependency group: {}".format(group_name))
        for dep_str in dev_deps[group_name]:
            # Strip editable markers
            stripped = dep_str.strip()
            if stripped.startswith("-e "):
                stripped = stripped[3:].strip()
            requirements.append(parse_pep508_requirement(stripped))

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
        })

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = requires_python,
        strict_dependencies = False,
    )

def repo_create_pdm_model(rctx, project_file, lock_file, lock_model, output):
    """Run the PDM translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pdm_lock_model rule.
        output: the output file.
    """
    project_dict = decode(rctx.read(rctx.path(project_file)))
    lock_dict = decode(rctx.read(rctx.path(lock_file)))
    raw_lock_data = translate_pdm(project_dict, lock_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
