"""Starlark pylock (PEP 751) translator.

Replaces the Python pylock_translator.py with a pure-Starlark implementation.
Parses pylock.toml files and produces the raw_lock.json structure consumed by
lock_resolver.bzl.
"""

load("@pypackaging.bzl", "pypackaging")
load("@toml.bzl//toml:toml.bzl", "decode")
load(":util.bzl", "extract_pep508_name", "parse_package_key")

def _canonicalize_name(name):
    return pypackaging.utils.canonicalize_name(name)

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

    # Create lookup map for versions. In PEP 751, each package is strictly pinned.
    versions = {}
    for pkg in packages_list:
        name = _canonicalize_name(pkg["name"])
        version = pkg["version"]
        versions[name] = version

    lock_packages = {}

    for pkg in packages_list:
        name = _canonicalize_name(pkg["name"])
        version = pkg["version"]
        pkg_key = "{}@{}".format(name, version)

        dependencies = []
        for dep in pkg.get("dependencies", []):
            dep_name_raw = dep["name"]
            dep_name = _canonicalize_name(dep_name_raw)

            # Handle extras in dependency name
            dep_extra = ""
            if "[" in dep_name_raw:
                parts = dep_name_raw.split("[", 1)
                dep_name = _canonicalize_name(parts[0])
                dep_extra = parts[1].rstrip("]").strip()

            dep_display = dep_name
            if dep_extra:
                dep_display = "{}[{}]".format(dep_name, _canonicalize_name(dep_extra))

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
    deps_by_name = {}
    for pkg_key, pkg in lock_packages.items():
        pkg_name = pkg["name"]
        deps_by_name[pkg_name] = pkg_key

    pins = {}

    dependency_groups = getattr(lock_model, "dependency_groups", ["default"])
    include_all = "*" in dependency_groups
    include_default = "default" in dependency_groups or include_all
    has_filter = not include_default or len([g for g in dependency_groups if g != "default"]) > 0

    if project_dict and has_filter:
        root_req_names = []

        project_section = project_dict.get("project", {})
        if include_default:
            for dep_str in project_section.get("dependencies", []):
                root_req_names.append(extract_pep508_name(dep_str))

        optional_deps = project_section.get("optional-dependencies", {})
        dev_deps = project_dict.get("dependency-groups", {})

        effective_groups = ["optional:*", "development:*"] if include_all else dependency_groups
        for group in effective_groups:
            if group == "default" or group == "*":
                continue

            kind, _, name = group.partition(":")
            if kind == "optional":
                groups_dict = optional_deps
            elif kind == "development":
                groups_dict = dev_deps
            else:
                fail("Invalid dependency group format '{}'. Must be 'optional:name' or 'development:name'.".format(group))

            if name == "*":
                target_names = list(groups_dict.keys())
            else:
                target_names = [name]

            for target_name in target_names:
                if target_name in groups_dict:
                    entries = groups_dict[target_name]
                    for entry in entries:
                        if type(entry) == "string":
                            root_req_names.append(extract_pep508_name(entry))
                        elif type(entry) == "dict" and "include-group" in entry:
                            inc_group = entry["include-group"]
                            if inc_group in dev_deps:
                                for inc_dep in dev_deps[inc_group]:
                                    if type(inc_dep) == "string":
                                        root_req_names.append(extract_pep508_name(inc_dep))
                else:
                    # buildifier: disable=print
                    print("WARNING: Dependency group '{}:{}' not found in project file.".format(kind, target_name))

        # Deduplicate
        root_package_names = {n: True for n in root_req_names}

        # BFS from root_package_names
        visited_names = {}
        queue = sorted(root_package_names.keys())

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

            pkg_key = deps_by_name.get(curr)
            if pkg_key and pkg_key in lock_packages:
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
        for root_name in sorted(root_package_names.keys()):
            if root_name in deps_by_name:
                pins[root_name] = deps_by_name[root_name]
    else:
        # Default: include all
        for pkg_key, pkg in lock_packages.items():
            pins[pkg["name"]] = pkg_key

    return {
        "packages": lock_packages,
        "pins": pins,
        "python_versions": requires_python,
    }

def repo_create_pylock_model(rctx, extra_project_files, lock_file, lock_model, output):
    """Run the pylock translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of extra pyproject.toml files.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pylock_lock_model rule.
        output: the output file.
    """

    # Try to find a pyproject.toml
    project_file = None
    if extra_project_files:
        project_file = extra_project_files[0]
    else:
        # Fall back to sibling pyproject.toml
        project_file = lock_file.relative(":pyproject.toml")

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
