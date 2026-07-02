"""Starlark UV translator.

Replaces the Python uv_translator.py with a pure-Starlark implementation.
Parses uv.lock and pyproject.toml files, then produces the raw_lock.json
structure consumed by lock_resolver.bzl.

Handles UV-specific features: workspace members, conflicts/variants,
resolution markers, git sources, and editable packages.
"""

load("@toml.bzl//toml:toml.bzl", "decode")
load(
    ":translator_common.bzl",
    "canonicalize_name",
    "resolve_lock_graph",
)

def _parse_file_info(file_info, package_name, package_version, registry = None):
    """Parse a UV lock file entry into a file dict.

    Args:
        file_info: A dict with "file", "filename", or "url" and "hash" keys.
        package_name: The name of the package.
        package_version: The version of the package.
        registry: An optional string representing the index URL.

    Returns:
        A dict with name, sha256, package_name, package_version, and optionally urls/index.
    """
    if "file" in file_info:
        filename = file_info["file"]
        urls = []
    elif "filename" in file_info:
        filename = file_info["filename"]
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
        urls = [url]
    else:
        fail("UV file entry has no 'file', 'filename', or 'url' member: {}".format(file_info))

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
    if registry:
        result["index"] = registry
    return result

def _sha256_from_string(s):
    """Generate a deterministic hex string from a string input.

    This is a simplistic hash for creating stable cache keys from
    git commit hashes. Not cryptographically secure, but deterministic
    and sufficient for cache keying purposes.

    Args:
        s: The input string.

    Returns:
        A 64-character hex string.
    """

    # Starlark doesn't have hashlib. We use a simple deterministic
    # encoding of the commit as a "hash". Since the commit is already
    # a hex SHA, we can use it directly padded to 64 chars.
    if len(s) >= 64:
        return s[:64]

    # Pad with repeated content
    result = s
    for _ in range(10):
        if len(result) >= 64:
            break
        result = result + s
    return result[:64]

def _resolve_package_requires_python(markers):
    """Extract python version specifiers from resolution markers.

    Args:
        markers: List of marker strings from resolution-markers.

    Returns:
        List of specifier strings.
    """
    specifiers = []
    for marker in markers:
        # Simple extraction of python_full_version constraints
        # e.g. "python_full_version >= '3.8'" -> ">= 3.8"
        if "python_full_version" in marker:
            # Parse out the operator and version
            parts = marker.strip().split("python_full_version")
            if len(parts) == 2:
                rest = parts[1].strip()

                # Extract operator
                op = ""
                for c in rest.elems():
                    if c in "<>=!":
                        op += c
                    elif c == " " and op:
                        break
                    elif op:
                        break
                version_part = rest[len(op):].strip().strip("'\"")
                if op and version_part:
                    specifiers.append("{} {}".format(op, version_part))
    return specifiers

def _parse_uv_dependency(dep):
    """Parse a UV lock dependency dict into a specifier.

    Args:
        dep: Dict with name, version, marker, extra/extras keys.

    Returns:
        A list of dep dicts suitable for resolve_lock_graph.
    """
    name = dep.get("name", "")
    version = dep.get("version", "")
    marker = dep.get("marker", "")
    extras = dep.get("extra") or dep.get("extras", [])

    results = []
    if extras:
        for extra in extras:
            dep_name = "{}[{}]".format(canonicalize_name(name), canonicalize_name(extra))
            specifier = "=={}".format(version) if version else ""
            results.append({
                "name": dep_name,
                "specifier": specifier,
                "marker": marker,
                "extras": [None],
            })
    else:
        specifier = "=={}".format(version) if version else ""
        results.append({
            "name": canonicalize_name(name),
            "specifier": specifier,
            "marker": marker,
            "extras": [None],
        })

    return results

def translate_uv(project_dict, lock_dict, lock_model):
    """Translates UV project and lock data to raw_lock_data dict.

    This is a pure function with no I/O, suitable for direct testing.

    Args:
        project_dict: Parsed pyproject.toml as a dict.
        lock_dict: Parsed uv.lock as a dict.
        lock_model: A struct containing the lock model attributes.

    Returns:
        A dict in raw_lock.json format.
    """

    # Version check
    lock_version = lock_dict.get("version", 0)
    if lock_version != 1:
        fail("UV lock file version {} is not supported (expected 1)".format(lock_version))

    project_name = canonicalize_name(project_dict["project"]["name"])

    # backwards-compat for https://github.com/astral-sh/uv/pull/5861
    distributions_list = lock_dict.get("distribution", [])
    packages_list = lock_dict.get("package", distributions_list)
    requires_python = lock_dict.get("requires-python", "")

    # Extract default-groups and conflicts from [tool.uv]
    uv_settings = project_dict.get("tool", {}).get("uv", {})
    uv_default_groups = uv_settings.get("default-groups", [])
    uv_conflicts = lock_dict.get("conflicts", [])

    # Parse variant sets from conflicts
    variant_items_by_key = {}  # (package, kind, name) -> variant item dict
    variant_sets = []
    for variant_list in uv_conflicts:
        items = []
        for c in variant_list:
            package = c["package"]
            if "extra" in c:
                kind, vname = "extra", c["extra"]
            elif "group" in c:
                kind, vname = "group", c["group"]
            else:
                kind, vname = "project", ""
            key = (package, kind, vname)
            if key not in variant_items_by_key:
                is_default = kind == "group" and vname in uv_default_groups
                item = {"package": package, "kind": kind}
                if vname:
                    item["name"] = vname
                if is_default:
                    item["default"] = True
                variant_items_by_key[key] = item
            items.append(variant_items_by_key[key])
        variant_sets.append({"items": items})

    # Build constraint lookup from variants
    extra_variant_values = {}
    group_variant_values = {}
    for item in variant_items_by_key.values():
        kind = item["kind"]
        vname = item.get("name", "")
        if kind == "extra":
            qualified = "extra_{}".format(vname)
            extra_variant_values[vname] = qualified
        elif kind == "group":
            qualified = "group_{}".format(vname)
            group_variant_values[vname] = qualified

    # Find the project package in the lock
    project_info = None
    for pkg in packages_list:
        if canonicalize_name(pkg["name"]) == project_name:
            project_info = pkg
            break
    if not project_info:
        fail("Project '{}' not found in uv.lock".format(project_name))

    # Collect requirements from project info
    requirements = []  # list of (req_name, specifier, constraint)

    # Parse project dependencies
    default_dependencies = project_info.get("dependencies", [])
    optional_dependencies = project_info.get("optional-dependencies", {})
    development_dependencies = project_info.get("dev-dependencies", {})

    if lock_model.default_group:
        for dep in default_dependencies:
            dep_name = canonicalize_name(dep["name"])
            dep_version = dep.get("version", "")
            dep_extras = dep.get("extra") or dep.get("extras", [])
            specifier = "=={}".format(dep_version) if dep_version else ""
            if dep_extras:
                for extra in dep_extras:
                    pin_name = "{}[{}]".format(dep_name, canonicalize_name(extra))
                    requirements.append((pin_name, specifier, ""))
            else:
                requirements.append((dep_name, specifier, ""))

    if lock_model.all_optional_groups:
        opt_groups = sorted(optional_dependencies.keys())
    else:
        opt_groups = getattr(lock_model, "optional_groups", [])

    for group_name in opt_groups:
        if group_name not in optional_dependencies:
            fail("Non-existent optional dependency group: {}".format(group_name))
        constraint = extra_variant_values.get(group_name, "")
        for dep in optional_dependencies[group_name]:
            dep_name = canonicalize_name(dep["name"])
            dep_version = dep.get("version", "")
            dep_extras = dep.get("extra") or dep.get("extras", [])
            specifier = "=={}".format(dep_version) if dep_version else ""
            if dep_extras:
                for extra in dep_extras:
                    pin_name = "{}[{}]".format(dep_name, canonicalize_name(extra))
                    requirements.append((pin_name, specifier, constraint))
            else:
                requirements.append((dep_name, specifier, constraint))

    if getattr(lock_model, "all_development_groups", False):
        dev_groups = sorted(development_dependencies.keys())
    else:
        dev_groups = getattr(lock_model, "development_groups", [])

    for group_name in dev_groups:
        if group_name not in development_dependencies:
            fail("Non-existent development dependency group: {}".format(group_name))
        constraint = group_variant_values.get(group_name, "")
        for dep in development_dependencies[group_name]:
            dep_name = canonicalize_name(dep["name"])
            dep_version = dep.get("version", "")
            dep_extras = dep.get("extra") or dep.get("extras", [])
            specifier = "=={}".format(dep_version) if dep_version else ""
            if dep_extras:
                for extra in dep_extras:
                    pin_name = "{}[{}]".format(dep_name, canonicalize_name(extra))
                    requirements.append((pin_name, specifier, constraint))
            else:
                requirements.append((dep_name, specifier, constraint))

    # Build pinned specs
    pinned_package_specs = {}
    for pin_name, specifier, constraint in requirements:
        if pin_name not in pinned_package_specs:
            pinned_package_specs[pin_name] = {}
        pinned_package_specs[pin_name][constraint] = specifier

    # Process all packages from lock
    packages = []
    for lock_pkg in packages_list:
        package_name = canonicalize_name(lock_pkg["name"])
        package_version = lock_pkg["version"]
        resolution_markers = lock_pkg.get("resolution-markers", [])
        python_version_specifiers = _resolve_package_requires_python(resolution_markers)
        package_extras = lock_pkg.get("extras", [])

        # Parse base dependencies
        deps = []
        for dep in lock_pkg.get("dependencies", []):
            deps.extend(_parse_uv_dependency(dep))

        # Parse files: wheels + sdist
        files = []
        source = lock_pkg.get("source", {})
        registry = source.get("registry")

        for w in lock_pkg.get("wheels", []):
            files.append(_parse_file_info(w, package_name, package_version, registry))

        sdist = lock_pkg.get("sdist", {})

        if sdist:
            if "url" in sdist or "file" in sdist:
                files.append(_parse_file_info(sdist, package_name, package_version, registry))
            elif "url" in source:
                # URL-based source with subdirectory
                url = source["url"]
                file_hash = sdist["hash"]
                if not file_hash.startswith("sha256:"):
                    fail("Expected sha256: prefix on hash")
                filename = "{}-{}.tar.gz".format(package_name, package_version)
                f = {
                    "name": filename,
                    "sha256": file_hash[7:],
                    "urls": [url],
                    "package_name": package_name,
                    "package_version": package_version,
                }
                if registry:
                    f["index"] = registry
                files.append(f)
            elif "git" in source:
                pass  # handled below
            else:
                files.append(_parse_file_info(sdist, package_name, package_version, registry))

        # Handle git sources
        if "git" in source and not files:
            git_url = source["git"]

            # Extract commit from fragment
            commit = ""
            if "#" in git_url:
                commit = git_url.split("#")[-1]
            if commit:
                synthetic_hash = _sha256_from_string(commit)
                filename = "{}-{}.tar.gz".format(package_name, package_version)
                files.append({
                    "name": filename,
                    "sha256": synthetic_hash,
                    "urls": ["git+" + git_url],
                    "package_name": package_name,
                    "package_version": package_version,
                })

        # Source dir
        source_dir = source.get("subdirectory", "")

        # Detect local packages
        is_local_editable = "editable" in source and type(source.get("editable")) == "string"
        is_local_virtual = "virtual" in source and type(source.get("virtual")) == "string"
        is_local_sdist = type(sdist) == "dict" and "path" in sdist and "url" not in sdist
        is_local = is_local_sdist or is_local_editable or is_local_virtual

        # Base package
        base_pkg = {
            "name": package_name,
            "version": package_version,
            "python_versions": python_version_specifiers[0] if python_version_specifiers else "",
            "python_version_specifiers": python_version_specifiers,
            "dependencies": deps,
            "files": files,
            "is_local": is_local,
            "extras": [e.lower() for e in package_extras],
        }
        if source_dir:
            base_pkg["source_dir"] = source_dir
        packages.append(base_pkg)

        # Extra packages (UV's optional-dependencies within the lock package)
        for extra_name, extra_deps_list in lock_pkg.get("optional-dependencies", {}).items():
            extra_parsed_deps = []
            for dep in extra_deps_list:
                extra_parsed_deps.extend(_parse_uv_dependency(dep))

            # Add self-dependency
            extra_parsed_deps.append({
                "name": package_name,
                "specifier": "=={}".format(package_version),
                "marker": "",
                "extras": [None],
            })

            extra_pkg_name = "{}[{}]".format(package_name, canonicalize_name(extra_name))
            extra_pkg = {
                "name": extra_pkg_name,
                "version": package_version,
                "python_versions": python_version_specifiers[0] if python_version_specifiers else "",
                "python_version_specifiers": python_version_specifiers,
                "dependencies": extra_parsed_deps,
                "files": [],
                "is_local": is_local,
                "extras": [],
            }
            if source_dir:
                extra_pkg["source_dir"] = source_dir
            packages.append(extra_pkg)

    return resolve_lock_graph(
        packages = packages,
        pinned_package_specs = pinned_package_specs,
        requires_python = requires_python,
        strict_dependencies = True,
        variants = variant_sets,
    )

def repo_create_uv_model(rctx, project_file, lock_file, lock_model, output):
    """Run the UV translator in pure Starlark.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_uv_lock_model rule.
        output: the output file.
    """
    project_path = rctx.path(project_file)
    if not project_path.exists:
        fail("Project file not found: {}. Ensure pyproject.toml exists at the expected location.".format(project_file))
    lock_path = rctx.path(lock_file)
    if not lock_path.exists:
        fail("Lock file not found: {}. Ensure uv.lock exists at the expected location.".format(lock_file))
    project_dict = decode(rctx.read(project_path))
    lock_dict = decode(rctx.read(lock_path))
    raw_lock_data = translate_uv(project_dict, lock_dict, lock_model)
    rctx.file(output, json.encode(raw_lock_data))
