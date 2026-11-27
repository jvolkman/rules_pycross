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
load(
    ":translator_graph.bzl",
    "apply_package_marker_forks",
    "build_lock_graph",
    "find_package_marker_forks",
    "resolve_lock_graph",
)
load(
    ":translator_project.bzl",
    "collect_pep621_requirements",
    "compute_requested_groups_for_model",
    "read_project_and_lock",
)
load(
    ":translator_util.bzl",
    "canonicalize_name",
    "combine_markers",
    "make_file_entry",
    "make_git_file_entry",
    "record_root_marker",
    "strip_sha256_prefix",
)
load(":util.bzl", "url_decode_filename")

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
        if constraint.startswith("=") and not constraint.startswith("=="):
            return "==" + constraint[1:].strip()
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

    clauses = []
    for part in constraint.split("||"):
        part = part.strip()
        if not part or part == "*":
            return ""
        if "," in part:
            clause = ",".join([_poetry_single_constraint_to_pep440(p) for p in part.split(",")])
        else:
            clause = _poetry_single_constraint_to_pep440(part)
        clauses.append(clause)

    return " || ".join(clauses)

def _expand_caret(version_str):
    """Expand Poetry caret constraint to PEP 440.

    ^X.Y.Z:
        If X > 0: >=X.Y.Z, <(X+1).0.0
        If X == 0 and Y > 0: >=0.Y.Z, <0.(Y+1).0
        If X == 0 and Y == 0: >=0.0.Z, <0.0.(Z+1)

    Preserves PEP 440 epochs and pre-release suffixes on the lower bound and
    carries any epoch onto the upper bound.

    Args:
        version_str: The version string after ^.

    Returns:
        PEP 440 specifier string.
    """
    parsed = pypackaging.version.try_parse(version_str)
    if parsed == None or not parsed.release:
        return ">=" + version_str

    parts = list(parsed.release)
    if parts[0] > 0:
        upper = [parts[0] + 1] + [0] * (len(parts) - 1)
    elif len(parts) >= 2 and parts[1] > 0:
        upper = [0, parts[1] + 1] + [0] * (len(parts) - 2)
    elif len(parts) >= 3:
        upper = [0, 0, parts[2] + 1] + [0] * (len(parts) - 3)
    elif len(parts) == 2:
        upper = [0, 1]
    else:
        upper = [parts[0] + 1]

    epoch_prefix = "{}!".format(parsed.epoch) if parsed.epoch else ""
    lower = pypackaging.version.to_string(parsed).split("+")[0]
    upper_str = epoch_prefix + ".".join([str(p) for p in upper])

    return ">={},<{}".format(lower, upper_str)

def _expand_tilde(version_str):
    """Expand Poetry tilde constraint to PEP 440.

    ~X.Y.Z → >=X.Y.Z, <X.(Y+1)
    ~X.Y   → >=X.Y, <X.(Y+1)

    Preserves PEP 440 epochs and pre-release suffixes on the lower bound and
    carries any epoch onto the upper bound.

    Args:
        version_str: The version string after ~.

    Returns:
        PEP 440 specifier string.
    """
    parsed = pypackaging.version.try_parse(version_str)
    if parsed == None or not parsed.release:
        return ">=" + version_str

    parts = list(parsed.release)
    epoch_prefix = "{}!".format(parsed.epoch) if parsed.epoch else ""
    lower = pypackaging.version.to_string(parsed).split("+")[0]

    if len(parts) < 2:
        # ~X → >=X, <(X+1) (unusual but handle it)
        return ">={},<{}{}".format(lower, epoch_prefix, str(parts[0] + 1))

    # Increment minor part
    upper = [parts[0], parts[1] + 1]
    upper_str = epoch_prefix + ".".join([str(p) for p in upper])

    return ">={},<{}".format(lower, upper_str)

def _poetry_python_to_marker(python):
    """Convert a Poetry `python` dependency restriction to a PEP 508 marker."""
    alternatives = []
    for part in python.split("||"):
        clauses = []
        for spec in _poetry_constraint_to_pep440(part).split(","):
            spec = spec.strip()
            op = ""
            for c in spec.elems():
                if c not in "<>=!~":
                    break
                op += c
            version = spec[len(op):].strip()
            if not op or not version:
                continue
            var = "python_full_version" if version.count(".") >= 2 else "python_version"
            clauses.append('{} {} "{}"'.format(var, op, version))
        if not clauses:
            return ""  # One alternative is unconstrained.
        alternatives.append(" and ".join(clauses))
    if len(alternatives) == 1:
        return alternatives[0]
    return " or ".join(["({})".format(a) for a in alternatives])

def _extract_poetry_marker(info_dict):
    if not info_dict:
        return ""
    marker = ""
    if "markers" in info_dict:
        marker = info_dict["markers"]
    elif "platform" in info_dict:
        marker = 'sys_platform == "{}"'.format(info_dict["platform"])
    python_marker = _poetry_python_to_marker(info_dict.get("python", ""))
    return combine_markers(marker, python_marker)

def _parse_poetry_pin(pin, pin_info, pinned_package_specs, track_pin, enrich_only = False, allow_optional = False):
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
        enrich_only: If True, only replace existing pin specifiers if the new one is not empty/wildcard,
            and do not overwrite existing root markers when this entry has no marker.
        allow_optional: If True, include entries marked `optional = true` (used for `[tool.poetry.extras]`).
    """
    existing_spec = pinned_package_specs.get(pin, {}).get("")

    # We don't propagate is_testonly here directly because pinned_package_specs
    # is now managed by the track_pin callback passed to us.

    def track_spec(spec, marker = "", extras = []):
        # Do not overwrite a specific existing constraint with a wildcard if enrich_only is set.
        if enrich_only and existing_spec and not spec:
            if not marker and not extras:
                return
            spec = existing_spec
        track_pin(pin, spec, marker, extras)

    if type(pin_info) == "string":
        track_spec(_poetry_constraint_to_pep440(pin_info), "")
        return
    entries = [pin_info] if type(pin_info) == "dict" else (pin_info if type(pin_info) == "list" else [])
    for entry in entries:
        if type(entry) != "dict" or "path" in entry or (entry.get("optional") and not allow_optional):
            continue
        track_spec(
            _poetry_constraint_to_pep440(entry.get("version", "*")),
            _extract_poetry_marker(entry),
            entry.get("extras", []),
        )

def _build_poetry_workspace_base(lock_dict):
    """Parse workspace-invariant Poetry lock packages, marker forks, and lock graph once."""
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

    packages = []
    for lock_pkg in lock_dict.get("package", []):
        package_name = canonicalize_name(lock_pkg["name"])
        source = lock_pkg.get("source", {})
        source_type = source.get("type", "")

        # Treat git as remote.
        is_local = source_type == "directory"
        package_version = lock_pkg.get("version")
        if not package_version:
            if is_local:
                package_version = "0.0.0"
            else:
                fail("Package '{}' in poetry.lock is missing a 'version' field".format(lock_pkg.get("name", "<unknown>")))

        deps = []
        for dep_name, dep_list in lock_pkg.get("dependencies", {}).items():
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

                # In Poetry 2.0 lock files, specs are mostly PEP 440, but may contain ||.
                deps.append({
                    "name": canonicalize_name(dep_name),
                    "specifier": _poetry_constraint_to_pep440(spec),
                    "marker": marker,
                    "extras": extras if extras else [None],
                })

        registry = source.get("url") if source_type == "legacy" else None

        source_urls = []
        git_url = ""
        commit = ""
        if source_type == "url" and source.get("url"):
            source_urls = [source["url"]]
        elif source_type == "git":
            git_url = source.get("url", "")
            commit = source.get("resolved_reference", "") or source.get("reference", "")
            if git_url and commit:
                source_urls = ["git+{}#{}".format(git_url, commit)]

        files = [
            make_file_entry(
                url_decode_filename(f["file"]),
                strip_sha256_prefix(f["hash"]) if f.get("hash") else "",
                package_name,
                package_version,
                urls = source_urls,
                index = registry,
            )
            for f in lock_pkg.get("files", [])
        ]

        if source_type == "git" and not files and git_url and commit:
            files = [make_git_file_entry(package_name, package_version, git_url, commit)]

        package_markers = lock_pkg.get("markers", "")

        pkg = {
            "name": package_name,
            "version": package_version,
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [canonicalize_name(e) for e in lock_pkg.get("extras", {}).keys()],
            "markers": package_markers,
        }
        if source_type in ("url", "git") and source.get("subdirectory"):
            pkg["source_dir"] = source["subdirectory"]
        packages.append(pkg)

    resolution_marker_exprs, forks_by_name = find_package_marker_forks(packages)
    graph = build_lock_graph(
        packages,
        resolution_marker_exprs = resolution_marker_exprs,
        strict_dependencies = True,
    )
    return struct(
        packages = packages,
        resolution_marker_exprs = resolution_marker_exprs,
        forks_by_name = forks_by_name,
        graph = graph,
    )

def translate_poetry(project_dict, lock_dict, lock_model, workspace_cache = None):
    """Translates Poetry project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml as a dict.
        lock_dict: Parsed poetry.lock as a dict.
        lock_model: A struct containing the lock model attributes.
        workspace_cache: Optional dict shared across repos in the same workspace
            to reuse parsed lock packages, marker forks, and the lock graph.

    Returns:
        A dict in raw_lock.json format.
    """
    if workspace_cache != None:
        base = workspace_cache.get("poetry_base")
        if base == None:
            base = _build_poetry_workspace_base(lock_dict)
            workspace_cache["poetry_base"] = base
            workspace_cache["shared_packages"] = True
    else:
        base = _build_poetry_workspace_base(lock_dict)

    # Collect pinned package specs from the project file
    pinned_package_specs = {}

    # First, check for [project.dependencies] (PEP 508, preferred)
    project_section = project_dict.get("project", {})
    project_name = project_section.get("name")
    project_deps = project_section.get("dependencies", [])
    has_project_deps = len(project_deps) > 0

    # Then, check for [tool.poetry.dependencies] (Poetry format)
    poetry_section = project_dict.get("tool", {}).get("poetry", {})
    poetry_deps = poetry_section.get("dependencies", {})
    poetry_groups = poetry_section.get("group", {})
    poetry_extras = poetry_section.get("extras", {})

    testonly_reqs = {}
    non_testonly_reqs = {}
    root_dependency_markers = {}

    def track_pin(pin_name, specifier, is_testonly, marker = "", extras = [], preserve_empty_marker = False):
        # name[extra] pins resolve to the base version; lock_resolver
        # synthesizes the extra package from the base's extra-gated edges.
        base_markers = root_dependency_markers.get(pin_name) if preserve_empty_marker and not marker else None
        for name in [pin_name] + ["{}[{}]".format(pin_name, canonicalize_name(e)) for e in extras]:
            pinned_package_specs.setdefault(name, {})
            pinned_package_specs[name][""] = specifier
            if is_testonly:
                testonly_reqs[name] = True
            else:
                non_testonly_reqs[name] = True
            if preserve_empty_marker and not marker:
                if name in root_dependency_markers:
                    continue
                if base_markers != None:
                    root_dependency_markers[name] = list(base_markers)
                    continue
            record_root_marker(root_dependency_markers, name, marker)

    def track_pep621(groups_subset):
        for req, is_testonly in collect_pep621_requirements(project_dict, groups_subset):
            if req.name != "python":
                track_pin(req.name, req.specifier, is_testonly, req.marker, req.extras)

    project_optional_deps = project_section.get("optional-dependencies", {})
    pep735_groups = project_dict.get("dependency-groups", {})

    available_optional_groups = list({k: True for k in list(project_optional_deps.keys()) + list(poetry_extras.keys())}.keys())
    available_dev_groups = list({k: True for k in list(poetry_groups.keys()) + list(pep735_groups.keys())}.keys())

    requested_groups_dict = compute_requested_groups_for_model(
        lock_model,
        available_groups = (
            ["default"] +
            ["optional:" + g for g in available_optional_groups] +
            ["group:" + g for g in available_dev_groups]
        ),
        project_name = project_name,
    )

    if "default" in requested_groups_dict:
        default_is_testonly = requested_groups_dict["default"]
        track_pep621({"default": default_is_testonly})
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
                    track_pin = lambda p, spec, marker, extras: track_pin(
                        p,
                        spec,
                        default_is_testonly,
                        marker,
                        extras,
                        preserve_empty_marker = has_project_deps,
                    ),
                    enrich_only = has_project_deps,
                )

    canonical_poetry_deps = {canonicalize_name(k): v for k, v in poetry_deps.items()}
    for group_name in available_optional_groups:
        key = "optional:{}".format(group_name)
        if key not in requested_groups_dict:
            continue
        is_testonly = requested_groups_dict[key]
        track_pep621({key: is_testonly})
        for dep_name in poetry_extras.get(group_name, []):
            pin = canonicalize_name(dep_name)
            if pin == "python":
                continue
            if pin in canonical_poetry_deps:
                _parse_poetry_pin(
                    pin,
                    canonical_poetry_deps[pin],
                    pinned_package_specs,
                    track_pin = lambda p, spec, marker, extras: track_pin(p, spec, is_testonly, marker, extras),
                    allow_optional = True,
                )
            else:
                existing_spec = pinned_package_specs.get(pin, {}).get("", "")
                track_pin(pin, existing_spec, is_testonly, preserve_empty_marker = pin in root_dependency_markers)

    # Poetry merges PEP 735 and legacy groups (union, not fallback).
    for group_name in available_dev_groups:
        key = "group:{}".format(group_name)
        if key not in requested_groups_dict:
            continue
        is_testonly = requested_groups_dict[key]
        track_pep621({key: is_testonly})
        for pin, pin_info in poetry_groups.get(group_name, {}).get("dependencies", {}).items():
            pin = canonicalize_name(pin)
            if pin == "python":
                continue
            _parse_poetry_pin(
                pin,
                pin_info,
                pinned_package_specs,
                track_pin = lambda p, spec, marker, extras: track_pin(p, spec, is_testonly, marker, extras),
            )

    testonly_pin_names = [name for name in testonly_reqs if name not in non_testonly_reqs]
    apply_package_marker_forks(pinned_package_specs, base.forks_by_name)

    return resolve_lock_graph(
        packages = base.packages,
        pinned_package_specs = pinned_package_specs,
        strict_dependencies = True,
        resolution_marker_exprs = base.resolution_marker_exprs,
        testonly_pins = testonly_pin_names,
        root_dependency_markers = root_dependency_markers,
        graph = base.graph,
    )

def repo_create_poetry_model(rctx, extra_project_files, lock_file, lock_model, toml_cache = None, workspace_cache = None):
    """Run the Poetry translator in pure Starlark."""
    project_dict, lock_dict = read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, "poetry.lock", toml_cache)
    return translate_poetry(project_dict, lock_dict, lock_model, workspace_cache = workspace_cache)
