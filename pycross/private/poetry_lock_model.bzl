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
    "compute_requested_dependency_groups",
    "parse_pep508_requirement",
    "resolution_marker_constraint_name",
    "resolve_lock_graph",
    "select_project_file",
    "sha256_from_string",
)

def _poetry_single_constraint_to_pep440(constraint):
    """Convert a single Poetry version constraint part to PEP 440."""
    constraint = constraint.strip()

    if not constraint or constraint == "*":
        return ""

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

    # Poetry often encodes != X as <X || >X
    # We should convert this back to !=X or handle || in some way.
    # pypackaging.specifiers does not support ||.
    # Let's do a simple heuristic for `<X || >X`
    if " || " in constraint:
        parts = [p.strip() for p in constraint.split(" || ")]
        if len(parts) == 2:
            left_parts = parts[0].split(",")
            right_parts = parts[1].split(",")

            # Simple != X encoding (e.g., "<X || >X")
            if len(left_parts) == 1 and len(right_parts) == 1 and left_parts[0].startswith("<") and right_parts[0].startswith(">"):
                v1 = left_parts[0].replace("<", "").replace("=", "").strip()
                v2 = right_parts[0].replace(">", "").replace("=", "").strip()
                if v1 == v2:
                    constraint = "!=" + v1
                else:
                    constraint = parts[0]

                # Complex exclusion (e.g., ">=1.2.5,<2.2.0 || >2.2.0,<3")
            elif left_parts[-1].startswith("<") and right_parts[0].startswith(">"):
                v1 = left_parts[-1].replace("<", "").replace("=", "").strip()
                v2 = right_parts[0].replace(">", "").replace("=", "").strip()
                if v1 == v2:
                    # Remove the upper bound from left and lower bound from right, insert !=
                    new_left = ",".join(left_parts[:-1])
                    new_right = ",".join(right_parts[1:])
                    constraint = (new_left + "," if new_left else "") + "!=" + v1 + ("," + new_right if new_right else "")
                else:
                    # Generic || cannot be represented in PEP 440 strictly. Just pick the left side.
                    constraint = parts[0]
            else:
                constraint = parts[0]
        else:
            constraint = parts[0]

    # Handle comma-separated constraints (e.g., "^1.2.3, !=1.2.5")
    if "," in constraint:
        parts = [p.strip() for p in constraint.split(",")]
        return ",".join([_poetry_single_constraint_to_pep440(p) for p in parts])

    return _poetry_single_constraint_to_pep440(constraint)

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

    Poetry's python-versions field uses Poetry constraint syntax (^, ~, ||)
    rather than PEP 440 specifiers, so we need to convert.

    Args:
        python_versions: The python-versions string from poetry.lock.

    Returns:
        A PEP 440 specifier string.
    """
    if not python_versions or python_versions == "*":
        return ""

    # Poetry uses || for OR (union) of version constraints.
    # PEP 440 has no OR operator — comma-separated specifiers are AND.
    # Joining || parts with commas would turn ">=3.9,<3.10 || >=3.11"
    # into ">=3.9,<3.10,>=3.11" which is unsatisfiable.
    # Drop the constraint entirely: being too permissive is safe (we may
    # include a package for a Python it doesn't support, caught at build time)
    # while being too restrictive silently excludes valid packages.
    if "||" in python_versions:
        return ""

    return _poetry_constraint_to_pep440(python_versions)

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

def _parse_poetry_pin(pin, pin_info, pinned_package_specs, track_pin, enrich_only = False):
    """Parse a Poetry dependency pin into pinned_package_specs.

    Handles three formats:
        - string: "^1.2.3"
        - dict: {version = "^1.2.3", markers = "...", optional = true, ...}
        - list: [{version = "1.0", python = "~3.9"}, {version = "2.0", python = ">=3.10"}]

    Args:
        pin: Canonicalized package name.
        pin_info: The dependency value from pyproject.toml (string, dict, or list).
        pinned_package_specs: Dict to check for existing specs.
        track_pin: Callback to track pin.
        enrich_only: If True, only replace existing pin specifiers if the new one is not empty/wildcard.
    """
    existing_spec = pinned_package_specs.get(pin, {}).get("")

    # We don't propagate is_testonly here directly because pinned_package_specs
    # is now managed by the track_pin callback passed to us.

    def track_spec(spec):
        # Do not overwrite a specific existing constraint with a wildcard if enrich_only is set.
        if enrich_only and existing_spec and not spec:
            return
        track_pin(pin, spec)

    if type(pin_info) == "string":
        track_spec(_poetry_constraint_to_pep440(pin_info))
    elif type(pin_info) == "dict":
        if "path" in pin_info or pin_info.get("optional"):
            return
        track_spec(_poetry_constraint_to_pep440(pin_info.get("version", "*")))
    elif type(pin_info) == "list":
        # List-of-dicts: each entry may have version, markers, url, python, etc.
        for entry in pin_info:
            if type(entry) != "dict":
                continue
            if "path" in entry or entry.get("optional"):
                continue
            version = entry.get("version", "*")
            spec = _poetry_constraint_to_pep440(version)

            if enrich_only and existing_spec and not spec:
                continue
            track_pin(pin, spec)

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
    lock_minor = int(lock_version_parts[1]) if len(lock_version_parts) > 1 else 0
    if lock_major < 2 or (lock_major == 2 and lock_minor < 1):
        fail(
            ("Poetry lock-version {} is not supported. " +
             "rules_pycross requires Poetry 2.1+ (lock-version >= 2.1). " +
             "Please regenerate your lock file with: poetry lock --regenerate").format(lock_version),
        )

    # Collect pinned package specs from the project file
    pinned_package_specs = {}

    # First, check for [project.dependencies] (PEP 508, preferred)
    project_section = project_dict.get("project", {})
    project_name = project_section.get("name")
    project_deps = project_section.get("dependencies", [])
    has_project_deps = len(project_deps) > 0

    # Then, check for [tool.poetry.dependencies] (Poetry format)
    poetry_deps = project_dict.get("tool", {}).get("poetry", {}).get("dependencies", {})
    poetry_groups = project_dict.get("tool", {}).get("poetry", {}).get("group", {})

    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])

    testonly_groups = getattr(lock_model, "testonly_groups", [])
    non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
    wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)

    testonly_reqs = {}
    non_testonly_reqs = {}

    def track_pin(pin_name, specifier, is_testonly):
        pinned_package_specs.setdefault(pin_name, {})
        pinned_package_specs[pin_name][""] = specifier
        if is_testonly:
            testonly_reqs[pin_name] = True
        else:
            non_testonly_reqs[pin_name] = True

    project_optional_deps = project_dict.get("project", {}).get("optional-dependencies", {})
    pep735_groups = project_dict.get("dependency-groups", {})

    available_dev_groups = list({k: True for k in list(poetry_groups.keys()) + list(pep735_groups.keys())}.keys())

    requested_groups_dict = compute_requested_dependency_groups(
        dependency_groups = dependency_groups,
        testonly_groups = testonly_groups,
        non_testonly_groups = non_testonly_groups,
        wildcard_testonly = wildcard_testonly,
        available_groups = (
            ["default"] +
            ["optional:" + g for g in project_optional_deps.keys()] +
            ["group:" + g for g in available_dev_groups]
        ),
        project_name = project_name,
        fail_on_missing = False,
    )

    if "default" in requested_groups_dict:
        default_is_testonly = requested_groups_dict["default"]
        if has_project_deps:
            # PEP 508 format from [project.dependencies]
            for dep_str in project_deps:
                req = parse_pep508_requirement(dep_str)
                if req.name == "python":
                    continue
                track_pin(req.name, req.specifier, default_is_testonly)
        if poetry_deps:
            # Also merge [tool.poetry.dependencies] if present
            for pin, pin_info in poetry_deps.items():
                pin = canonicalize_name(pin)
                if pin == "python":
                    continue

                # If project.dependencies is present, tool.poetry.dependencies can only enrich them.
                if has_project_deps and pin not in pinned_package_specs:
                    continue
                _parse_poetry_pin(
                    pin,
                    pin_info,
                    pinned_package_specs,
                    track_pin = lambda p, spec: track_pin(p, spec, default_is_testonly),
                    enrich_only = has_project_deps,
                )

    for group_name in project_optional_deps.keys():
        key = "optional:{}".format(group_name)
        if key in requested_groups_dict:
            is_testonly = requested_groups_dict[key]
            for dep_str in project_optional_deps[group_name]:
                req = parse_pep508_requirement(dep_str)
                if req.name == "python":
                    continue
                track_pin(req.name, req.specifier, is_testonly)

    for group_name in available_dev_groups:
        key = "group:{}".format(group_name)
        if key in requested_groups_dict:
            is_testonly = requested_groups_dict[key]

            # Poetry merges PEP 735 and legacy groups (union, not fallback).
            if group_name in pep735_groups:
                for dep_str in pep735_groups[group_name]:
                    req = parse_pep508_requirement(dep_str)
                    if req.name == "python":
                        continue
                    track_pin(canonicalize_name(req.name), req.specifier, is_testonly)

            if group_name in poetry_groups:
                g = poetry_groups[group_name]
                for pin, pin_info in g.get("dependencies", {}).items():
                    pin = canonicalize_name(pin)
                    if pin == "python":
                        continue
                    _parse_poetry_pin(
                        pin,
                        pin_info,
                        pinned_package_specs,
                        track_pin = lambda p, spec: track_pin(p, spec, is_testonly),
                    )

    testonly_pin_names = [name for name in testonly_reqs if name not in non_testonly_reqs]

    # Parse lock file metadata
    lock_python_versions = _parse_python_versions(
        lock_dict.get("metadata", {}).get("python-versions", ""),
    )

    # Parse file info helper
    def parse_file_info(file_info, registry = None):
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

                # In Poetry 2.0 lock files, specs are mostly PEP 440, but may contain ||
                deps.append({
                    "name": canonicalize_name(dep_name),
                    "specifier": _poetry_constraint_to_pep440(spec),
                    "marker": marker,
                    "extras": extras if extras else [None],
                })

        # Source type check for local packages
        source = lock_pkg.get("source", {})
        source_type = source.get("type", "")

        # Treat git as remote
        is_local = source_type == "directory"
        registry = source.get("url") if source_type == "legacy" else None

        # Determine download URLs for URL or Git sources
        source_urls = []
        if source_type == "url" and source.get("url"):
            source_urls = [source["url"]]
        elif source_type == "git":
            git_url = source.get("url", "")
            commit = source.get("resolved_reference", "")
            if not commit:
                commit = source.get("reference", "")
            if git_url and commit:
                source_urls = ["git+{}#{}".format(git_url, commit)]

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

        # Handle git synthetic file if no files found
        if source_type == "git" and not files and source_urls:
            commit = source_urls[0].split("#")[-1]
            synthetic_hash = sha256_from_string(commit)
            filename = "{}-{}.tar.gz".format(package_name, package_version)
            files = [{
                "name": filename,
                "sha256": synthetic_hash,
            }]

        # Add package name, version, and source URLs to files
        updated_files = []
        for f in files:
            updated_f = dict(f)
            updated_f["package_name"] = package_name
            updated_f["package_version"] = package_version
            if source_urls:
                updated_f["urls"] = source_urls
            updated_files.append(updated_f)
        files = updated_files

        # Filter to only matching files for standard sources
        if source_type not in ("url", "git"):
            files = _get_files_for_package(files, package_name, package_version)

        # Read package-level markers (Poetry 2.1+)
        package_markers = lock_pkg.get("markers", "")

        packages.append({
            "name": package_name,
            "version": package_version,
            "python_versions": _parse_python_versions(package_python_versions),
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [],
            "markers": package_markers,
        })

    # Detect resolution-marker forks: same package name with multiple versions.
    resolution_marker_exprs = {}
    _fork_versions = {}  # {name: {version: marker_expr}}
    for pkg in packages:
        marker = pkg.get("markers", "")
        if not marker:
            continue
        _fork_versions.setdefault(pkg["name"], {})[pkg["version"]] = marker

    _fork_constraints = {}  # {name: {version: constraint_name}}
    for fname, versions in _fork_versions.items():
        if len(versions) <= 1:
            continue  # Single version, no fork.
        for fversion, marker_expr in versions.items():
            cname = resolution_marker_constraint_name(fname, fversion)
            _fork_constraints.setdefault(fname, {})[fversion] = cname
            resolution_marker_exprs[cname] = marker_expr

    # If forks were detected, update pinned_package_specs to use conditional pins.
    for fname, version_constraints in _fork_constraints.items():
        if fname in pinned_package_specs:
            conditional_pins = {}
            for fversion, cname in version_constraints.items():
                conditional_pins[cname] = "==" + fversion
            pinned_package_specs[fname] = conditional_pins

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = lock_python_versions,
        strict_dependencies = True,
        resolution_marker_exprs = resolution_marker_exprs,
        testonly_pins = testonly_pin_names,
    )

def repo_create_poetry_model(rctx, extra_project_files, lock_file, lock_model, output):
    """Run the Poetry translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of extra pyproject.toml files.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_poetry_lock_model rule.
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
        fail("Lock file not found: {}. Ensure poetry.lock exists at the expected location.".format(lock_file))

    lock_dict = decode(rctx.read(lock_path))
    raw_lock_data = translate_poetry(project_dict, lock_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
