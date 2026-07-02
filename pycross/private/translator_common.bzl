"""Shared Starlark utilities for lock file translators.

Ports resolve_lock_graph and related logic from translator_utils.py.
Used by PDM, Poetry, and UV translators.
"""

load("@pypackaging.bzl", "pypackaging")

def canonicalize_name(name):
    """Canonicalize a Python package name per PEP 503."""
    return pypackaging.utils.canonicalize_name(name)

def parse_pep508_requirement(req_str):
    """Parses a PEP 508 requirement string into components.

    Handles formats like:
        "requests>=2.23.0,<3.0.0"
        "requests (>=2.23.0,<3.0.0)"
        "requests[security]>=2.0; python_version >= '3.6'"
        "urllib3<3,>=1.21.1"

    Args:
        req_str: The PEP 508 requirement string.

    Returns:
        A struct with name, extras (list), specifier (string), marker (string).
    """
    req_str = req_str.strip()

    # Strip editable markers (PDM legacy)
    if req_str.startswith("-e "):
        req_str = req_str[3:].strip()

    parsed = pypackaging.requirements.parse(req_str)

    # Reconstruct specifier string
    specifier_str = ""
    if parsed.specifier and parsed.specifier.specs:
        specifier_str = ",".join(["{}{}".format(s.operator, s.version) for s in parsed.specifier.specs])

    # Replicate pypackaging logic to extract marker_str to maintain compatible interface
    at_idx = req_str.find("@")
    semi_idx = req_str.find(";")
    marker_str = ""

    if at_idx != -1 and (semi_idx == -1 or at_idx < semi_idx):
        # URL requirement
        right = req_str[at_idx + 1:].strip()
        ws_idx = -1

        # buildifier: disable=string-iteration
        for i in range(len(right)):
            if right[i] in " \t":
                ws_idx = i
                break
        if ws_idx != -1:
            rest = right[ws_idx:].strip()
            if rest.startswith(";"):
                marker_str = rest[1:].strip()
    else:
        # Specifier requirement
        if semi_idx != -1:
            marker_str = req_str[semi_idx + 1:].strip()

    return struct(
        name = parsed.name,
        extras = parsed.extras,
        specifier = specifier_str,
        marker = marker_str,
    )

def _dependency_name_str(name, extra = ""):
    """Format a dependency name with optional extra."""
    if extra:
        return "{}[{}]".format(name, extra)
    return name

def _package_key_str(name, version):
    """Format a package key string."""
    return "{}@{}".format(name, version)

def _specifier_contains_version(specifier_str, version_str):
    """Check if a PEP 440 specifier set contains a version.

    Args:
        specifier_str: The specifier string (e.g. ">=1.0,<2.0") or "*" or "".
        version_str: The version string (e.g. "1.5.0").

    Returns:
        True if the version satisfies the specifier.
    """
    if not specifier_str or specifier_str == "*":
        return True
    spec_set = pypackaging.specifiers.parse_set(specifier_str)
    return pypackaging.specifiers.set_contains(spec_set, version_str)

def _version_key(version_str):
    """Parse a version string into a comparable key tuple."""
    return pypackaging.version.parse(version_str).key

def resolve_lock_graph(packages, pinned_package_specs, requires_python, strict_dependencies = True, variants = None):
    """Resolves a dependency graph of packages.

    Ports translator_utils.py resolve_lock_graph() to Starlark.

    Each package in the packages list should be a dict with:
        - name: canonicalized package name
        - version: version string
        - dependencies: list of dicts {name, specifier, marker, extras}
        - files: list of dicts {name, sha256, urls?}
        - python_versions: requires-python specifier string
        - is_local: bool (optional, default False)
        - extras: list of extra names (optional)

    Each pinned_package_specs entry maps a dependency name (str) to
    a dict of {constraint_label: specifier_str}.

    Args:
        packages: List of package dicts.
        pinned_package_specs: Dict mapping pin name to {constraint: specifier}.
        requires_python: The requires-python specifier string.
        strict_dependencies: If True, fail on unresolved deps.
        variants: List of variant set dicts (optional).

    Returns:
        A dict in raw_lock.json format.
    """
    if variants == None:
        variants = []

    # Deduplicate: merge packages with same key
    distinct_packages = {}
    for pkg in packages:
        pkg_key = _package_key_str(pkg["name"], pkg["version"])
        if pkg_key in distinct_packages:
            # Merge: combine deps, files, extras
            existing = distinct_packages[pkg_key]
            merged_deps = list(existing["dependencies"])
            existing_dep_keys = {"{}/{}".format(d["name"], d.get("specifier", "")): True for d in merged_deps}
            for d in pkg["dependencies"]:
                dk = "{}/{}".format(d["name"], d.get("specifier", ""))
                if dk not in existing_dep_keys:
                    merged_deps.append(d)
                    existing_dep_keys[dk] = True
            merged_files = list(existing["files"])
            existing_file_names = {f["name"]: True for f in merged_files}
            for f in pkg["files"]:
                if f["name"] not in existing_file_names:
                    merged_files.append(f)
                    existing_file_names[f["name"]] = True
            merged_extras = list(existing.get("extras", []))
            for e in pkg.get("extras", []):
                if e not in merged_extras:
                    merged_extras.append(e)
            distinct_packages[pkg_key] = dict(
                existing,
                dependencies = merged_deps,
                files = merged_files,
                extras = merged_extras,
                is_local = existing.get("is_local", False) or pkg.get("is_local", False),
            )
        else:
            distinct_packages[pkg_key] = pkg

    all_packages = distinct_packages.values()

    # Group by canonical name
    packages_by_name = {}
    for pkg in all_packages:
        name = pkg["name"]
        if name not in packages_by_name:
            packages_by_name[name] = []
        packages_by_name[name].append(pkg)

    # Sort by version descending (newest first)
    for name in list(packages_by_name.keys()):
        packages_by_name[name] = sorted(
            packages_by_name[name],
            key = lambda p: _version_key(p["version"]),
            reverse = True,
        )

    # Resolve dependencies
    resolved_deps = {}  # pkg_key -> list of resolved dep dicts

    for pkg in all_packages:
        pkg_key = _package_key_str(pkg["name"], pkg["version"])
        pkg_resolved = []

        for dep in pkg["dependencies"]:
            dep_name = canonicalize_name(dep["name"])
            dep_specifier = dep.get("specifier", "")
            dep_marker = dep.get("marker", "")
            dep_extras = dep.get("extras", [None])

            if not dep_extras:
                dep_extras = [None]

            for req_extra in dep_extras:
                display_name = _dependency_name_str(dep_name, canonicalize_name(req_extra) if req_extra else "")

                # Find matching package
                candidates = packages_by_name.get(dep_name, [])
                found = False
                for cand in candidates:
                    cand_extras = [e.lower() for e in cand.get("extras", [])]
                    if req_extra and req_extra.lower() not in cand_extras:
                        continue
                    if _specifier_contains_version(dep_specifier, cand["version"]):
                        pkg_resolved.append({
                            "name": display_name,
                            "version": cand["version"],
                            "marker": dep_marker,
                        })
                        found = True
                        break

                if not found and strict_dependencies:
                    fail("Found no packages to satisfy dependency (name={}, spec={})".format(dep_name, dep_specifier))

        resolved_deps[pkg_key] = pkg_resolved

    # Resolve pins
    pinned_keys = {}
    for pin_name, pin_specs in pinned_package_specs.items():
        pin_packages = packages_by_name.get(pin_name, [])
        pinned_keys[pin_name] = {}
        for constraint, pin_specifier in pin_specs.items():
            found = False
            for pin_pkg in pin_packages:
                if _specifier_contains_version(pin_specifier, pin_pkg["version"]):
                    pinned_keys[pin_name][constraint] = _package_key_str(pin_pkg["name"], pin_pkg["version"])
                    found = True
                    break
            if not found and strict_dependencies:
                fail("Found no packages to satisfy pin (name={}, spec={})".format(pin_name, pin_specifier))

    # Replace pins of local packages with pins of their dependencies
    for _ in range(len(pinned_keys) + 1):
        local_pins = []
        for pin_name, constraints in pinned_keys.items():
            for constraint, key in constraints.items():
                pkg = distinct_packages.get(key, {})
                if pkg.get("is_local", False):
                    local_pins.append((pin_name, constraint, key))
        if not local_pins:
            break
        for pin_name, constraint, key in local_pins:
            pkg_deps = resolved_deps.get(key, [])
            for dep in pkg_deps:
                dep_base_name = dep["name"].split("[")[0]
                if dep_base_name not in pinned_keys:
                    pinned_keys[dep_base_name] = {}
                pinned_keys[dep_base_name][constraint] = _package_key_str(dep_base_name, dep["version"])
            pinned_keys[pin_name].pop(constraint)

        # Cleanup empty dicts
        keys_to_delete = [k for k, v in pinned_keys.items() if not v]
        for k in keys_to_delete:
            pinned_keys.pop(k)

    # Build output
    lock_packages = {}
    for pkg in all_packages:
        if pkg.get("is_local", False):
            # buildifier: disable=print
            print("WARNING: Local package {} elided from pycross repo.".format(
                _package_key_str(pkg["name"], pkg["version"]),
            ))
            continue

        pkg_key = _package_key_str(pkg["name"], pkg["version"])
        deps = resolved_deps.get(pkg_key, [])

        # Filter self-deps
        deps_without_self = [d for d in deps if _package_key_str(d["name"].split("[")[0], d["version"]) != pkg_key]
        deps_sorted = sorted(deps_without_self, key = lambda d: (d["name"], d["version"]))
        files_sorted = sorted(pkg["files"], key = lambda f: f["name"])

        raw_package = {
            "name": pkg["name"],
            "version": pkg["version"],
            "python_versions": pkg.get("python_versions", ""),
            "dependencies": deps_sorted,
            "files": files_sorted,
        }

        # Include python_version_specifiers if present
        if pkg.get("python_version_specifiers"):
            raw_package["python_version_specifiers"] = pkg["python_version_specifiers"]

        # Include source_dir if present
        if pkg.get("source_dir"):
            raw_package["source_dir"] = pkg["source_dir"]

        lock_packages[pkg_key] = raw_package

    # Simplify pins: if a pin has only one constraint with key "", flatten it
    simplified_pins = {}
    for name, constraints in pinned_keys.items():
        keys = sorted(constraints.keys())
        if keys == [""]:
            simplified_pins[name] = constraints[""]
        else:
            simplified_pins[name] = constraints

    result = {
        "packages": lock_packages,
        "pins": simplified_pins,
        "python_versions": requires_python,
    }

    if variants:
        result["variants"] = variants

    return result
