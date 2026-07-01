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

    # If we have a project file and filters, subset the graph.
    has_filter = (
        not lock_model.default_group or
        getattr(lock_model, "optional_groups", []) or
        getattr(lock_model, "all_optional_groups", False) or
        getattr(lock_model, "development_groups", []) or
        getattr(lock_model, "all_development_groups", False)
    )

    if project_dict and has_filter:
        root_req_names = []

        project_section = project_dict.get("project", {})
        if lock_model.default_group:
            for dep_str in project_section.get("dependencies", []):
                root_req_names.append(extract_pep508_name(dep_str))

        optional_deps = project_section.get("optional-dependencies", {})
        if getattr(lock_model, "all_optional_groups", False):
            opt_groups = sorted(optional_deps.keys())
        else:
            opt_groups = getattr(lock_model, "optional_groups", [])

        for g in opt_groups:
            if g in optional_deps:
                for dep_str in optional_deps[g]:
                    root_req_names.append(extract_pep508_name(dep_str))
            else:
                # buildifier: disable=print
                print("WARNING: Optional group '{}' not found in project file.".format(g))

        dev_deps = project_dict.get("dependency-groups", {})
        if getattr(lock_model, "all_development_groups", False):
            dev_groups = sorted(dev_deps.keys())
        else:
            dev_groups = getattr(lock_model, "development_groups", [])

        for g in dev_groups:
            if g in dev_deps:
                for dep_entry in dev_deps[g]:
                    if type(dep_entry) == "string":
                        root_req_names.append(extract_pep508_name(dep_entry))
                    elif type(dep_entry) == "dict" and "include-group" in dep_entry:
                        inc_group = dep_entry["include-group"]
                        if inc_group in dev_deps:
                            for inc_dep in dev_deps[inc_group]:
                                if type(inc_dep) == "string":
                                    root_req_names.append(extract_pep508_name(inc_dep))
            else:
                # buildifier: disable=print
                print("WARNING: Development group '{}' not found in project file.".format(g))

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

def repo_create_pylock_model(rctx, project_file, lock_file, lock_model, output):
    """Run the pylock translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file (optional).
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pylock_lock_model rule.
        output: the output file.
    """
    lock_dict = decode(rctx.read(rctx.path(lock_file)))
    project_dict = None
    if project_file:
        project_dict = decode(rctx.read(rctx.path(project_file)))
    raw_lock_data = translate_pylock(lock_dict, project_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
