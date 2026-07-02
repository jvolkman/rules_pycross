"""Starlark Poetry translator.

Replaces the Python poetry_translator.py with a pure-Starlark implementation.
Parses poetry.lock (2.0+) and pyproject.toml files, then produces the
raw_lock.json structure consumed by lock_resolver.bzl.

Supports pins from:
  - [project.dependencies]  (PEP 508 format)
  - [tool.poetry.dependencies]  (Poetry format, with ^/~ expansion)
  - [tool.poetry.group.*.dependencies]  (Poetry groups)
"""

load("@pypackaging.bzl", "pypackaging")
load("@toml.bzl//toml:toml.bzl", "decode")
load(
    ":translator_common.bzl",
    "canonicalize_name",
    "parse_pep508_requirement",
    "resolve_lock_graph",
)

def _poetry_constraint_to_pep440(constraint):
    """Convert a Poetry version constraint to PEP 440 specifier string.

    Handles:
        "^1.2.3"   → ">=1.2.3,<2.0.0"
        "^0.2.3"   → ">=0.2.3,<0.3.0"
        "^0.0.3"   → ">=0.0.3,<0.0.4"
        "~1.2.3"   → ">=1.2.3,<1.3.0"
        "~1.2"     → ">=1.2,<1.3"
        ">=1.0,<2" → ">=1.0,<2" (pass through)
        "*"        → ""
        "1.2.3"    → "==1.2.3"

    Args:
        constraint: The Poetry constraint string.

    Returns:
        A PEP 440 specifier string.
    """
    constraint = constraint.strip()

    if not constraint or constraint == "*":
        return ""

    # Handle comma-separated constraints (e.g., "^1.2.3, !=1.2.5")
    if "," in constraint:
        parts = [p.strip() for p in constraint.split(",")]
        return ",".join([_poetry_constraint_to_pep440(p) for p in parts])

    # Already PEP 440? Pass through if it starts with a comparison operator
    if constraint[0] in ("<", ">", "!", "=", "~"):
        # But ~= is PEP 440 compatible release, while ~ alone is Poetry tilde
        if constraint.startswith("~="):
            return constraint
        if constraint.startswith("~"):
            return _expand_tilde(constraint[1:].strip())
        return constraint

    # Caret constraint
    if constraint.startswith("^"):
        return _expand_caret(constraint[1:].strip())

    # Exact version (bare number)
    if constraint[0].isdigit():
        return "==" + constraint

    # Unknown format, pass through
    return constraint

def _parse_version_part(part):
    """Parse an integer from a version part, stripping pre-release suffixes.

    Handles parts like "3", "3-alpha", "3rc1", "3+build".

    Args:
        part: A version part string.

    Returns:
        The integer portion of the version part.
    """
    digits = ""
    for c in part.elems():
        if c.isdigit():
            digits += c
        else:
            break
    if not digits:
        return 0
    return int(digits)

def _expand_caret(version_str):
    """Expand Poetry caret constraint to PEP 440.

    ^X.Y.Z:
        If X > 0: >=X.Y.Z, <(X+1).0.0
        If X == 0 and Y > 0: >=0.Y.Z, <0.(Y+1).0
        If X == 0 and Y == 0: >=0.0.Z, <0.0.(Z+1)

    Args:
        version_str: The version string after ^.

    Returns:
        PEP 440 specifier string.
    """
    parts = [_parse_version_part(p) for p in version_str.split(".")]

    # Pad to at least 1 part
    if len(parts) == 0:
        return ">=" + version_str

    if parts[0] > 0:
        upper = [parts[0] + 1] + [0] * (len(parts) - 1)
    elif len(parts) >= 2 and parts[1] > 0:
        upper = [0, parts[1] + 1] + [0] * (len(parts) - 2)
    elif len(parts) >= 3:
        upper = [0, 0, parts[2] + 1] + [0] * (len(parts) - 3)
    else:
        upper = [parts[0] + 1]

    lower = ".".join([str(p) for p in parts])
    upper_str = ".".join([str(p) for p in upper])

    return ">={},<{}".format(lower, upper_str)

def _expand_tilde(version_str):
    """Expand Poetry tilde constraint to PEP 440.

    ~X.Y.Z → >=X.Y.Z, <X.(Y+1).0
    ~X.Y   → >=X.Y, <X.(Y+1)

    Args:
        version_str: The version string after ~.

    Returns:
        PEP 440 specifier string.
    """
    parts = [_parse_version_part(p) for p in version_str.split(".")]

    if len(parts) < 2:
        # ~X → >=X, <(X+1) (unusual but handle it)
        return ">={},<{}".format(version_str, str(parts[0] + 1))

    # Increment second-to-last part
    upper = list(parts[:2])
    upper[1] = upper[1] + 1

    lower = ".".join([str(p) for p in parts])
    upper_str = ".".join([str(p) for p in upper])

    return ">={},<{}".format(lower, upper_str)

def _parse_python_versions(python_versions):
    """Parse Poetry's python-versions string to a PEP 440 specifier.

    Args:
        python_versions: The python-versions string from poetry.lock.

    Returns:
        A PEP 440 specifier string.
    """
    if not python_versions or python_versions == "*":
        return ""
    return python_versions

def _get_files_for_package(files, package_name, package_version):
    """Filter files list to only those matching the given package.

    In Poetry 2.0, files are inline per-package so this is usually
    a no-op, but we keep it for safety.

    Args:
        files: List of file dicts.
        package_name: The canonicalized package name.
        package_version: The version string.

    Returns:
        Filtered list of file dicts.
    """
    result = []
    for f in files:
        filename = f["name"]
        if filename.endswith(".whl"):
            # Parse wheel filename to check name and version
            parsed = pypackaging.utils.parse_wheel_filename(filename)
            if parsed.name == package_name and parsed.version.version_str == package_version:
                result.append(f)
        elif filename.endswith(".tar.gz") or filename.endswith(".zip"):
            parsed = pypackaging.utils.parse_sdist_filename(filename)
            if parsed.name == package_name and parsed.version.version_str == package_version:
                result.append(f)
        else:
            # Unknown format, include it
            result.append(f)

    return result

def translate_poetry(project_dict, lock_dict, lock_model):
    """Translates Poetry project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml as a dict.
        lock_dict: Parsed poetry.lock as a dict.
        lock_model: A struct containing the lock model attributes.

    Returns:
        A dict in raw_lock.json format.
    """
    lock_version = lock_dict.get("metadata", {}).get("lock-version", "")
    if not lock_version:
        fail("Poetry lock file has no lock-version in [metadata]")

    lock_version_parts = lock_version.split(".")
    if len(lock_version_parts) < 1:
        fail("Invalid lock-version: {}".format(lock_version))
    lock_major = int(lock_version_parts[0])
    if lock_major < 2:
        fail(
            "Poetry lock-version {} is not supported. " +
            "rules_pycross requires Poetry 2.0+ (lock-version >= 2.0). " +
            "Please regenerate your lock file with: poetry lock --regenerate",
            lock_version,
        )

    # Collect pinned package specs from the project file
    pinned_package_specs = {}

    # First, check for [project.dependencies] (PEP 508, preferred)
    project_deps = project_dict.get("project", {}).get("dependencies", [])
    has_project_deps = len(project_deps) > 0

    # Then, check for [tool.poetry.dependencies] (Poetry format)
    poetry_deps = project_dict.get("tool", {}).get("poetry", {}).get("dependencies", {})
    poetry_groups = project_dict.get("tool", {}).get("poetry", {}).get("group", {})

    if lock_model.default_group:
        if has_project_deps:
            # PEP 508 format from [project.dependencies]
            for dep_str in project_deps:
                req = parse_pep508_requirement(dep_str)
                if req.name == "python":
                    continue
                pinned_package_specs[req.name] = {"": req.specifier}
        elif poetry_deps:
            # Fall back to [tool.poetry.dependencies]
            for pin, pin_info in poetry_deps.items():
                pin = canonicalize_name(pin)
                if pin == "python":
                    continue
                if type(pin_info) == "string":
                    pinned_package_specs[pin] = {"": _poetry_constraint_to_pep440(pin_info)}
                elif type(pin_info) == "dict":
                    if "path" in pin_info:
                        continue
                    pinned_package_specs[pin] = {"": _poetry_constraint_to_pep440(pin_info.get("version", "*"))}

    # Optional groups (from [tool.poetry.group.*.dependencies])
    if getattr(lock_model, "all_optional_groups", False):
        opt_groups = sorted(poetry_groups.keys())
    else:
        opt_groups = getattr(lock_model, "optional_groups", [])

    for group_name in opt_groups:
        group = poetry_groups.get(group_name, {})
        for pin, pin_info in group.get("dependencies", {}).items():
            pin = canonicalize_name(pin)
            if pin == "python":
                continue
            if type(pin_info) == "string":
                pinned_package_specs[pin] = {"": _poetry_constraint_to_pep440(pin_info)}
            elif type(pin_info) == "dict":
                if "path" in pin_info:
                    continue
                pinned_package_specs[pin] = {"": _poetry_constraint_to_pep440(pin_info.get("version", "*"))}

    # Also support [project.optional-dependencies] (PEP 508)
    project_optional_deps = project_dict.get("project", {}).get("optional-dependencies", {})
    if project_optional_deps:
        if getattr(lock_model, "all_optional_groups", False):
            pep_opt_groups = sorted(project_optional_deps.keys())
        else:
            pep_opt_groups = getattr(lock_model, "optional_groups", [])

        for group_name in pep_opt_groups:
            if group_name in project_optional_deps:
                for dep_str in project_optional_deps[group_name]:
                    req = parse_pep508_requirement(dep_str)
                    if req.name == "python":
                        continue
                    pinned_package_specs[req.name] = {"": req.specifier}

    # Parse lock file metadata
    lock_python_versions = _parse_python_versions(
        lock_dict.get("metadata", {}).get("python-versions", ""),
    )

    # Parse file info helper
    def parse_file_info(file_info, registry=None):
        filename = file_info["file"]
        file_hash = file_info["hash"]
        if not file_hash.startswith("sha256:"):
            fail("Expected sha256: prefix on hash: {}".format(file_hash))
        res = {"name": filename, "sha256": file_hash[7:]}
        if registry:
            res["index"] = registry
        return res

    # In Poetry 2.0, files are per-package (not in [metadata.files])
    # But we still support [metadata.files] as fallback for edge cases
    lock_files_by_name = {}
    for pkg_name, pkg_files in lock_dict.get("metadata", {}).get("files", {}).items():
        lock_files_by_name[pkg_name] = [parse_file_info(f) for f in pkg_files]

    # Build package list
    packages = []
    for lock_pkg in lock_dict.get("package", []):
        package_listed_name = lock_pkg["name"]
        package_name = canonicalize_name(package_listed_name)
        package_version = lock_pkg["version"]
        package_python_versions = lock_pkg.get("python-versions", "*")

        # Parse dependencies
        deps = []
        for dep_name, dep_list in lock_pkg.get("dependencies", {}).items():
            # Coerce single entry to list
            if type(dep_list) != "list":
                dep_list = [dep_list]
            for dep in dep_list:
                if type(dep) == "string":
                    marker = ""
                    spec = dep
                    extras = []
                else:
                    marker = dep.get("markers", "")
                    spec = dep.get("version", "*")
                    extras = dep.get("extras", [])

                # In Poetry 2.0 lock files, specs are already PEP 440
                deps.append({
                    "name": canonicalize_name(dep_name),
                    "specifier": spec if spec != "*" else "",
                    "marker": marker,
                    "extras": extras if extras else [None],
                })

        # Source type check for local packages
        source = lock_pkg.get("source", {})
        source_type = source.get("type", "")
        is_local = source_type in ("directory", "git", "url")
        registry = source.get("url") if source_type == "legacy" else None

        # Parse files (inline in Poetry 2.0)
        files = [parse_file_info(f, registry) for f in lock_pkg.get("files", [])]
        if not files:
            files = lock_files_by_name.get(package_listed_name, [])
            if registry:
                new_files = []
                for f in files:
                    nf = dict(f)
                    nf["index"] = registry
                    new_files.append(nf)
                files = new_files

        # Add package name and version to files
        updated_files = []
        for f in files:
            updated_f = dict(f)
            updated_f["package_name"] = package_name
            updated_f["package_version"] = package_version
            updated_files.append(updated_f)
        files = updated_files

        # Filter to only matching files
        files = _get_files_for_package(files, package_name, package_version)

        packages.append({
            "name": package_name,
            "version": package_version,
            "python_versions": _parse_python_versions(package_python_versions),
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [],
        })

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = lock_python_versions,
        strict_dependencies = True,
    )

def repo_create_poetry_model(rctx, project_file, lock_file, lock_model, output):
    """Run the Poetry translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_poetry_lock_model rule.
        output: the output file.
    """
    project_dict = decode(rctx.read(rctx.path(project_file)))
    lock_dict = decode(rctx.read(rctx.path(lock_file)))
    raw_lock_data = translate_poetry(project_dict, lock_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
