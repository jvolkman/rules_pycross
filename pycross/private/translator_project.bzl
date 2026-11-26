"""Project file selection, dependency group resolution, and PEP 621/735 parsing.

Shared by PDM, Poetry, UV, and Pylock Starlark translators.
"""

load(":lock_common.bzl", "read_toml_cached", "sibling_project_file")
load(":translator_util.bzl", "canonicalize_name", "parse_pep508_requirement")

def _expand_pep735_group(dev_deps, group_name):
    """Expand a PEP 735 dependency group transitively, resolving `{include-group = ...}` entries.

    Preserves declaration order, allows diamond include DAGs, and fails on
    unknown or cyclic `include-group` references per PEP 735.
    """
    norm_groups = {canonicalize_name(k): v for k, v in dev_deps.items()}
    total_entries = 0
    for entries in norm_groups.values():
        total_entries += len(entries)
    max_iters = 2 * len(norm_groups) + total_entries + 2

    deps = []
    visiting = {}
    visited = {}
    stack = [("enter", canonicalize_name(group_name))]
    for _ in range(max_iters):
        if not stack:
            break
        kind, payload = stack.pop()
        if kind == "dep":
            deps.append(payload)
            continue
        if kind == "exit":
            visiting.pop(payload)
            visited[payload] = True
            continue
        if payload in visiting:
            fail("Circular include-group detected involving dependency group '{}'".format(payload))
        if payload in visited:
            continue
        visiting[payload] = True
        stack.append(("exit", payload))
        entries = norm_groups.get(payload, [])
        for entry in reversed(entries):
            if type(entry) == "string":
                stack.append(("dep", entry))
            elif type(entry) == "dict" and "include-group" in entry:
                inc = canonicalize_name(entry["include-group"])
                if inc not in norm_groups:
                    fail("Dependency group '{}' includes unknown group '{}'".format(payload, entry["include-group"]))
                stack.append(("enter", inc))
    if stack:
        fail("expand_pep735_group exceeded max iterations for group '{}'; this is a bug in pycross".format(group_name))
    return deps

def _default_project_dict(rctx, extra_project_files, sibling_label, toml_cache):
    project_file = (
        sibling_label if (not extra_project_files or sibling_label in extra_project_files) else extra_project_files[0]
    )
    return read_toml_cached(rctx, project_file, toml_cache) or {}

def _match_project_dicts(rctx, extra_project_files, target_projects, toml_cache, stop_on_first = False):
    """Decode and return `(matched_dicts, matched_names)` for projects in `target_projects`."""
    target_names = {canonicalize_name(p): True for p in target_projects}
    matched = []
    matched_names = {}
    for f in extra_project_files:
        p_dict = read_toml_cached(rctx, f, toml_cache)
        if p_dict == None:
            continue
        p_name = p_dict.get("project", {}).get("name")
        if p_name and canonicalize_name(p_name) in target_names:
            matched.append(p_dict)
            matched_names[canonicalize_name(p_name)] = True
            if stop_on_first:
                break
    return matched, matched_names

def _read_project_dicts(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Select and decode all matching pyproject.toml files as a list of dicts."""
    sibling_label = sibling_project_file(lock_file)
    if not extra_project_files:
        return [read_toml_cached(rctx, sibling_label, toml_cache) or {}]

    projects = getattr(lock_model, "projects", [])
    if not projects or "*" in projects:
        # Order root/sibling file first (for requires-python and workspace metadata),
        # followed by all other member pyproject.toml files.
        ordered = ([sibling_label] if sibling_label in extra_project_files else []) + [
            f
            for f in extra_project_files
            if f != sibling_label
        ]
        dicts = []
        seen = {}
        for f in ordered:
            if f in seen:
                continue
            seen[f] = True
            p_dict = read_toml_cached(rctx, f, toml_cache)
            if p_dict != None:
                dicts.append(p_dict)
        return dicts or [{}]

    matched, matched_names = _match_project_dicts(rctx, extra_project_files, projects, toml_cache)
    if matched:
        missing = [p for p in projects if canonicalize_name(p) not in matched_names]
        if missing:
            fail("Project(s) {} not found in workspace pyproject.toml files".format(missing))
        return matched

    return [_default_project_dict(rctx, extra_project_files, sibling_label, toml_cache)]

def _read_project_dict(rctx, extra_project_files, lock_file, lock_model, toml_cache = None):
    """Select and decode the relevant pyproject.toml as a dict.

    A single-project repo reads its member's pyproject.toml; multi-project and
    wildcard repos read the root or sibling pyproject.toml (used by uv for
    workspace-level `default-groups`).
    """
    sibling_label = sibling_project_file(lock_file)
    projects = getattr(lock_model, "projects", [])
    if extra_project_files and len(projects) == 1 and projects[0] != "*":
        matched, _ = _match_project_dicts(rctx, extra_project_files, projects, toml_cache, stop_on_first = True)
        if matched:
            return matched[0]
    return _default_project_dict(rctx, extra_project_files, sibling_label, toml_cache)

def _read_lock_dict(rctx, lock_file, lock_label_hint, toml_cache = None):
    lock_dict = read_toml_cached(rctx, lock_file, toml_cache)
    if lock_dict == None:
        fail("Lock file not found: {}. Ensure {} exists at the expected location.".format(lock_file, lock_label_hint))
    return lock_dict

def read_projects_and_lock(rctx, extra_project_files, lock_file, lock_model, lock_label_hint, toml_cache = None):
    """Select and decode all matching pyproject.toml files and the lock file.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of pyproject.toml labels.
        lock_file: The lock file label.
        lock_model: Struct with lock model attributes (including optional `projects`).
        lock_label_hint: Human-readable lock file name for error messages (for example, `"pdm.lock"`).
        toml_cache: Optional dict caching decoded TOML files by label.

    Returns:
        A tuple of `(project_dicts, lock_dict)`.
    """
    project_dicts = _read_project_dicts(rctx, extra_project_files, lock_file, lock_model, toml_cache)
    return project_dicts, _read_lock_dict(rctx, lock_file, lock_label_hint, toml_cache)

def read_project_and_lock(rctx, extra_project_files, lock_file, lock_model, lock_label_hint, toml_cache = None):
    """Select and decode pyproject.toml and the lock file.

    Args:
        rctx: The repository_ctx or module_ctx object.
        extra_project_files: List of pyproject.toml labels.
        lock_file: The lock file label.
        lock_model: Struct with lock model attributes (including optional `projects`).
        lock_label_hint: Human-readable lock file name for error messages (for example, `"uv.lock"`).
        toml_cache: Optional dict caching decoded TOML files by label.

    Returns:
        A tuple of `(project_dict, lock_dict)`.
    """
    project_dict = _read_project_dict(rctx, extra_project_files, lock_file, lock_model, toml_cache)
    return project_dict, _read_lock_dict(rctx, lock_file, lock_label_hint, toml_cache)

# Prefixes accepted in dependency_groups entries ('<kind>:<name>' or '<kind>:*').
_GROUP_KINDS = ["optional", "group"]

def _compute_requested_dependency_groups(
        dependency_groups,
        testonly_groups,
        non_testonly_groups,
        wildcard_testonly,
        available_groups,
        project_name = None,
        allow_missing = False):
    """Compute the requested dependency groups and their testonly status.

    Processes wildcard group expansions and applies last-wins testonly
    resolution to construct the final dictionary of requested groups.
    """
    available_set = {g: True for g in available_groups}

    include_all = "*" in dependency_groups
    effective_groups = list(available_set.keys()) if include_all else dependency_groups

    requested = {}

    for group in effective_groups:
        kind, sep, name = group.partition(":")
        kind_wildcard = kind + ":*" if sep and kind in _GROUP_KINDS else ""
        if group in testonly_groups:
            is_testonly = True
        elif group in non_testonly_groups:
            is_testonly = False
        elif kind_wildcard and kind_wildcard in testonly_groups:
            is_testonly = True
        elif kind_wildcard and kind_wildcard in non_testonly_groups:
            is_testonly = False
        else:
            is_testonly = wildcard_testonly

        if not sep or kind not in _GROUP_KINDS:
            if group not in available_set:
                fail("Unknown dependency group '{}'. Expected '*', 'default', 'transitive', or one of: {}.".format(
                    group,
                    ", ".join(["'{}:<name>'".format(k) for k in _GROUP_KINDS]),
                ))
            requested[group] = is_testonly
            continue

        if name == "*":
            prefix = kind + ":"
            targets = [g for g in available_set if g.startswith(prefix)]
        else:
            targets = [group]

        for target in targets:
            if target not in available_set:
                if allow_missing:
                    continue
                if project_name:
                    fail("Project '{}' does not have group '{}'.".format(project_name, target))
                fail("Dependency group '{}' not found.".format(target))

            requested[target] = is_testonly

    return requested

def compute_requested_groups_for_model(lock_model, available_groups, project_name = None, allow_missing = False):
    """Compute requested dependency groups using attributes from `lock_model`.

    Args:
        lock_model: Struct with `dependency_groups`, `testonly_groups`,
            `non_testonly_groups`, and `wildcard_testonly` attributes.
        available_groups: List of fully-prefixed available group names
            (for example, `["default", "optional:extras1", "group:dev"]`).
        project_name: Optional project name for error messages.
        allow_missing: If True, skip requested groups absent from `available_groups`
            instead of failing.

    Returns:
        Dict mapping requested group identifier -> `is_testonly` bool.
    """
    return _compute_requested_dependency_groups(
        dependency_groups = getattr(lock_model, "dependency_groups", ["default"]),
        testonly_groups = getattr(lock_model, "testonly_groups", []),
        non_testonly_groups = getattr(lock_model, "non_testonly_groups", []),
        wildcard_testonly = getattr(lock_model, "wildcard_testonly", False),
        available_groups = available_groups,
        project_name = project_name,
        allow_missing = allow_missing,
    )

def validate_multi_project_groups(dependency_groups, groups_seen, target_projects):
    """Fail if any explicitly requested group was not declared by any target project.

    Args:
        dependency_groups: Requested dependency group specs from `lock_model`.
        groups_seen: Dict or iterable of group keys declared across target projects.
        target_projects: Iterable of project names for the error message.
    """
    for group in dependency_groups:
        _, sep, name = group.partition(":")
        if sep and name != "*" and group not in groups_seen:
            fail("None of the projects {} has group '{}'.".format(sorted(target_projects), group))

def collect_pep621_requirements(project_dict, requested_groups_dict, dev_deps = None):
    """Collect `(parsed_req, is_testonly)` pairs for requested PEP 621 and PEP 735 groups.

    Args:
        project_dict: Parsed pyproject.toml dict.
        requested_groups_dict: Dict mapping requested group key -> `is_testonly` bool.
        dev_deps: Optional dict of dev dependency groups (defaults to `[dependency-groups]`).

    Returns:
        List of `(parsed_req, is_testonly)` tuples.
    """
    project_section = project_dict.get("project", {})
    optional_deps = project_section.get("optional-dependencies", {})
    if dev_deps == None:
        dev_deps = project_dict.get("dependency-groups", {})

    requirements = []
    if "default" in requested_groups_dict:
        is_testonly = requested_groups_dict["default"]
        for dep_str in project_section.get("dependencies", []):
            requirements.append((parse_pep508_requirement(dep_str), is_testonly))

    for target_name, entries in optional_deps.items():
        key = "optional:{}".format(target_name)
        if key not in requested_groups_dict:
            continue
        is_testonly = requested_groups_dict[key]
        for dep_str in entries:
            if type(dep_str) == "string":
                requirements.append((parse_pep508_requirement(dep_str), is_testonly))

    for target_name in dev_deps.keys():
        key = "group:{}".format(target_name)
        if key not in requested_groups_dict:
            continue
        is_testonly = requested_groups_dict[key]
        for dep_str in _expand_pep735_group(dev_deps, target_name):
            requirements.append((parse_pep508_requirement(dep_str), is_testonly))

    return requirements

# Visible for testing
compute_requested_dependency_groups_for_testing = _compute_requested_dependency_groups
read_project_dict_for_testing = _read_project_dict
read_project_dicts_for_testing = _read_project_dicts
