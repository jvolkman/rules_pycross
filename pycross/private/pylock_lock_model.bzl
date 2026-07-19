"""Starlark pylock (PEP 751) translator.

Replaces the Python pylock_translator.py with a pure-Starlark implementation.
Parses pylock.toml files and produces the raw_lock.json structure consumed by
lock_resolver.bzl.
"""

load("@toml.bzl//toml:toml.bzl", "decode")
load(":translator_common.bzl", "canonicalize_name", "compute_requested_dependency_groups", "resolution_marker_constraint_name", "select_project_file")
load(":util.bzl", "extract_pep508_name", "parse_package_key")

def _strip_selection_markers(marker):
    """Strip PDM selection markers (dependency_groups, extras) from a marker string.

    PDM pylock markers combine environment markers with selection logic like
    '"default" in dependency_groups'. We only want the environment markers
    for resolution fork detection.

    Args:
        marker: A marker string, e.g. 'python_version < "3.10" and "default" in dependency_groups'

    Returns:
        A string with only environment marker parts, e.g. 'python_version < "3.10"'
    """
    if not marker:
        return ""

    # Split on " and " and filter out selection-related parts
    parts = marker.split(" and ")
    env_parts = []
    for part in parts:
        stripped = part.strip()
        if "dependency_groups" in stripped or "in extras" in stripped:
            continue
        env_parts.append(stripped)

    return " and ".join(env_parts)

def translate_pylock(lock_dict, project_dict, lock_model):
    """Translates pylock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        lock_dict: Parsed pylock.toml as a dict.
        project_dict: Parsed pyproject.toml as a dict (may be None).
        lock_model: A struct containing the lock model attributes.

    Returns:
        A dict in raw_lock.json format.
    """

    lock_version = lock_dict.get("lock-version", "")
    if str(lock_version) != "1.0":
        fail("Unsupported pylock lock-version: {}. Expected 1.0".format(lock_version))

    requires_python = lock_dict.get("requires-python", "")

    packages_list = lock_dict.get("package", lock_dict.get("packages", []))

    # Create lookup map for versions.
    # Track all versions per name to support multi-target forks.
    versions = {}  # {name: version} - first version seen
    versions_all = {}  # {name: {version: marker}} - all versions with markers
    for pkg in packages_list:
        name = canonicalize_name(pkg["name"])
        version = pkg["version"]
        if name not in versions:
            versions[name] = version
        marker = pkg.get("marker", "")

        # Strip dependency_groups/extras selection markers (PDM-specific).
        # Keep only environment markers for resolution fork detection.
        env_marker = _strip_selection_markers(marker)
        versions_all.setdefault(name, {})[version] = env_marker

    lock_packages = {}

    for pkg in packages_list:
        name = canonicalize_name(pkg["name"])
        version = pkg["version"]
        pkg_key = "{}@{}".format(name, version)

        dependencies = []
        for dep in pkg.get("dependencies", []):
            dep_name_raw = dep["name"]
            dep_name = canonicalize_name(dep_name_raw)

            # Handle extras in dependency name
            dep_extra = ""
            if "[" in dep_name_raw:
                parts = dep_name_raw.split("[", 1)
                dep_name = canonicalize_name(parts[0])
                dep_extra = parts[1].rstrip("]").strip()

            dep_display = dep_name
            if dep_extra:
                dep_display = "{}[{}]".format(dep_name, canonicalize_name(dep_extra))

            dep_version = versions.get(dep_name)
            if not dep_version:
                # buildifier: disable=print
                print("WARNING: dependency '{}' of '{}' not found in lockfile, skipping".format(
                    dep_display,
                    name,
                ))
                continue

            dependencies.append({
                "name": dep_display,
                "version": dep_version,
                "marker": dep.get("marker", ""),
            })

        files = []

        # Wheels
        for wheel in pkg.get("wheels", pkg.get("wheel", [])):
            if type(wheel) != "dict":
                continue
            filename = wheel.get("name", wheel.get("file", ""))
            if not filename and "url" in wheel:
                filename = wheel["url"].split("/")[-1]
            url = wheel.get("url", "")
            urls = [url] if url else []
            hash_str = wheel.get("hash", "")
            if hash_str and hash_str.startswith("sha256:"):
                hash_val = hash_str[7:]
            else:
                hashes = wheel.get("hashes", {})
                hash_val = hashes.get("sha256", "")
            file_entry = {
                "name": filename,
                "sha256": hash_val,
                "package_name": name,
                "package_version": version,
            }
            if urls:
                file_entry["urls"] = urls
            files.append(file_entry)

        # Sdists
        sdist_list = pkg.get("sdists", pkg.get("sdist", []))
        if type(sdist_list) == "dict":
            sdist_list = [sdist_list]
        for sdist in sdist_list:
            if type(sdist) != "dict":
                continue
            filename = sdist.get("name", sdist.get("file", ""))
            if not filename and "url" in sdist:
                filename = sdist["url"].split("/")[-1]
            url = sdist.get("url", "")
            urls = [url] if url else []
            hash_str = sdist.get("hash", "")
            if hash_str and hash_str.startswith("sha256:"):
                hash_val = hash_str[7:]
            else:
                hashes = sdist.get("hashes", {})
                hash_val = hashes.get("sha256", "")
            file_entry = {
                "name": filename,
                "sha256": hash_val,
                "package_name": name,
                "package_version": version,
            }
            if urls:
                file_entry["urls"] = urls
            files.append(file_entry)

        # Sort dependencies and files for determinism
        dependencies = sorted(dependencies, key = lambda d: d["name"])
        files = sorted(files, key = lambda f: f["name"])

        package_requires_python = pkg.get("requires-python", "")

        raw_package = {
            "name": name,
            "version": version,
            "python_versions": package_requires_python,
            "dependencies": dependencies,
            "files": files,
        }

        lock_packages[pkg_key] = raw_package

    # Build dependency lookup by name
    deps_by_name = {}  # {name: [pkg_key, ...]}
    for pkg_key, pkg in lock_packages.items():
        pkg_name = pkg["name"]
        deps_by_name.setdefault(pkg_name, []).append(pkg_key)

    pins = {}

    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    include_default = "default" in dependency_groups or "*" in dependency_groups
    has_filter = not include_default or len([g for g in dependency_groups if g != "default"]) > 0

    if project_dict and has_filter:
        root_req_names = []
        testonly_root_req_names = []
        testonly_groups = getattr(lock_model, "testonly_groups", [])
        non_testonly_groups = getattr(lock_model, "non_testonly_groups", [])
        wildcard_testonly = getattr(lock_model, "wildcard_testonly", False)


        project_section = project_dict.get("project", {})
        optional_deps = project_section.get("optional-dependencies", {})
        dev_deps = project_dict.get("dependency-groups", {})

        project_name = project_dict.get("project", {}).get("name")

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
            fail_on_missing = False,  # Following precedent set by original print warning
        )

        if "default" in requested_groups_dict:
            is_testonly = requested_groups_dict["default"]
            for dep_str in project_section.get("dependencies", []):
                if is_testonly:
                    testonly_root_req_names.append(extract_pep508_name(dep_str))
                else:
                    root_req_names.append(extract_pep508_name(dep_str))

        for kind, groups_dict in [("optional", optional_deps), ("group", dev_deps)]:
            for target_name in groups_dict.keys():
                key = "{}:{}".format(kind, target_name)
                if key not in requested_groups_dict:
                    continue
                is_testonly = requested_groups_dict[key]
                entries = groups_dict[target_name]
                for entry in entries:
                    if type(entry) == "string":
                        n = extract_pep508_name(entry)
                        if is_testonly:
                            testonly_root_req_names.append(n)
                        else:
                            root_req_names.append(n)
                    elif type(entry) == "dict" and "include-group" in entry:
                        inc_group = entry["include-group"]
                        if inc_group in dev_deps:
                            for inc_dep in dev_deps[inc_group]:
                                if type(inc_dep) == "string":
                                    n = extract_pep508_name(inc_dep)
                                    if is_testonly:
                                        testonly_root_req_names.append(n)
                                    else:
                                        root_req_names.append(n)

        # Deduplicate
        root_package_names = {n: True for n in root_req_names}
        testonly_package_names = {n: True for n in testonly_root_req_names if n not in root_package_names}

        # BFS from all root names to find reachable packages
        visited_names = {}
        all_roots = dict(root_package_names)
        all_roots.update(testonly_package_names)
        queue = sorted(all_roots.keys())

        # Starlark has no while loop, simulate with for+range.
        # Upper bound: each edge can add one item to the queue, plus the initial queue size.
        total_edges = 0
        for pkg_key in lock_packages:
            total_edges += len(lock_packages[pkg_key].get("dependencies", []))
        max_iter = total_edges + len(queue) + 1
        for _ in range(max_iter):
            if not queue:
                break
            curr = queue[0]
            queue = queue[1:]
            if curr in visited_names:
                continue
            visited_names[curr] = True

            for pkg_key in deps_by_name.get(curr, []):
                if pkg_key in lock_packages:
                    for dep in lock_packages[pkg_key].get("dependencies", []):
                        dep_base = parse_package_key(dep["name"]).name
                        queue.append(dep_base)

        if queue:
            fail("BFS traversal exceeded max iterations; this is a bug in pycross")

        # Filter
        filtered_packages = {}
        for pkg_key, pkg in lock_packages.items():
            if pkg["name"] in visited_names:
                filtered_packages[pkg_key] = pkg
        lock_packages = filtered_packages

        # Pins from roots
        for root_name in sorted(all_roots.keys()):
            keys = deps_by_name.get(root_name, [])
            if keys:
                pins[root_name] = keys[0]

        testonly_pins = sorted(testonly_package_names.keys())
    else:
        # Default: include all (use first key per name; fork detection below may override)
        seen_names = {}
        for pkg_key, pkg in lock_packages.items():
            pname = pkg["name"]
            if pname not in seen_names:
                pins[pname] = pkg_key
                seen_names[pname] = True
        testonly_pins = []

    # Detect resolution-marker forks: same package name with multiple versions.
    resolution_marker_exprs = {}
    fork_constraints = {}  # {name: {version: constraint_name}}
    for fname, version_markers in versions_all.items():
        if len(version_markers) <= 1:
            continue  # Single version, no fork.
        for fversion, marker_expr in version_markers.items():
            if not marker_expr:
                continue  # Skip versions without env markers.
            cname = resolution_marker_constraint_name(fname, fversion)
            fork_constraints.setdefault(fname, {})[fversion] = cname
            resolution_marker_exprs[cname] = marker_expr

    # If forks were detected, update pins to use conditional pins.
    for fname, version_constraints in fork_constraints.items():
        if fname in pins:
            conditional_pins = {}
            for fversion, cname in version_constraints.items():
                conditional_pins[cname] = "{}@{}".format(fname, fversion)
            pins[fname] = conditional_pins

    result = {
        "packages": lock_packages,
        "pins": pins,
        "python_versions": requires_python,
        "testonly_pins": testonly_pins,
    }
    if resolution_marker_exprs:
        result["resolution_marker_exprs"] = resolution_marker_exprs
    return result

def repo_create_pylock_model(rctx, extra_project_files, lock_file, lock_model, output):
    """Run the pylock translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of extra pyproject.toml files.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pylock_lock_model rule.
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
        fail("Lock file not found: {}. Ensure the pylock file exists at the expected location.".format(lock_file))

    lock_dict = decode(rctx.read(lock_path))
    raw_lock_data = translate_pylock(lock_dict, project_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
