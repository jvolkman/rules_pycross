"""Shared helpers for lock import/resolution extensions."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@toml.bzl//toml:toml.bzl", "decode")
load(":lock_contract.bzl", "build_repo_name")

def validate_transition_attrs(tag, tag_name):
    """Validates that transition attributes are mutually exclusive.

    Args:
        tag: The tag to validate.
        tag_name: The name of the tag for error messages.
    """
    has_platform = bool(getattr(tag, "platform", None))
    has_flags = bool(getattr(tag, "flags", [])) or bool(getattr(tag, "settings", {}))
    has_constraints = bool(getattr(tag, "constraint_values", []))

    if has_platform and (has_flags or has_constraints):
        fail("Tag '{}' cannot specify both 'platform' and ('flags', 'settings' or 'constraint_values')".format(tag_name))

def check_unique_repo_name(owners, module_name, repo_name):
    """Check uniqueness using a repo name string instead of a tag."""
    if repo_name in owners:
        fail("lock repo '{}' wanted by module '{}' already created by module '{}'".format(
            repo_name,
            module_name,
            owners[repo_name],
        ))
    owners[repo_name] = module_name

_EMPTY_TRANSITION = struct(
    flags = [],
    settings = {},
    constraint_values = [],
    platform = None,
)

def read_toml_cached(ctx, file_label, toml_cache = None):
    """Read and decode a TOML file, caching the decoded dict by label.

    Args:
        ctx: The module_ctx or repository_ctx object.
        file_label: Label of the TOML file to read.
        toml_cache: Optional dict mapping Label -> decoded dict (or None if missing).

    Returns:
        The decoded TOML dict, or None if the file does not exist.
    """
    if toml_cache != None and file_label in toml_cache:
        return toml_cache[file_label]
    path = ctx.path(file_label)
    data = decode(ctx.read(path)) if path.exists else None
    if toml_cache != None:
        toml_cache[file_label] = data
    return data

def resolve_member_project_file(lock_file_label, member_path):
    """Resolve a member's pyproject.toml label relative to the lock file's directory.

    The result stays in the lock file's package when it can (e.g. `//:project/uv.lock` with
    member `apps/a` gives `//:project/apps/a/pyproject.toml`), so member directories don't
    need to be Bazel packages. Labels that cross into subpackages are fine for
    `module_ctx.path()`/`repository_ctx.path()`.

    Args:
        lock_file_label: Label of the lock file.
        member_path: Relative path from the lock file's directory to the member directory
            (e.g. "./packages/lib-a"). Use "" or "." for the lock file's own directory.

    Returns:
        A Label pointing to the member's pyproject.toml.
    """
    if paths.is_absolute(member_path):
        fail("Workspace member path '{}' (relative to {}) must be relative".format(member_path, lock_file_label))
    lock_dir = paths.dirname(lock_file_label.name)
    rel = paths.normalize(paths.join(lock_dir, member_path, "pyproject.toml"))
    if not paths.starts_with(rel, ".."):
        return lock_file_label.same_package_label(rel)

    # The member is outside the lock file's package: resolve from the repo root.
    repo_rel = paths.normalize(paths.join(lock_file_label.package, rel))
    if paths.starts_with(repo_rel, ".."):
        fail("Workspace member path '{}' (relative to {}) is outside the repository".format(member_path, lock_file_label))
    return lock_file_label.relative("//:" + repo_rel)

def sibling_project_file(lock_file_label):
    """Return the label of the pyproject.toml next to a lock file."""
    return resolve_member_project_file(lock_file_label, "")

def parse_dependency_group_entries(raw_groups):
    """Parse dependency group entries with last-wins testonly semantics.

    Processes a list of dependency group entries (e.g., ["default", "group:dev;testonly",
    "*;testonly", "transitive"]) and resolves testonly status with last-wins precedence:
    - When * appears, it sets the default testonly status and clears prior specific overrides
    - Specific entries after * override individual groups
    - The last entry matching a group wins

    Args:
        raw_groups: List of raw dependency group strings from the user's config.

    Returns:
        A struct with:
            dependency_groups: Parsed group specs (without ;testonly suffixes).
            testonly_groups: Groups explicitly marked testonly (after last *).
            non_testonly_groups: Groups explicitly marked non-testonly (after last *).
            wildcard_testonly: Whether * was marked testonly.
            include_transitive: Whether "transitive" was present.
            transitive_testonly: Whether "transitive;testonly" was present.
    """
    parsed_groups = []
    include_transitive = False
    transitive_testonly = False

    wildcard_testonly = False
    testonly_overrides = {}  # group -> is_testonly (only entries after last *)

    for entry in raw_groups:
        parts = entry.split(";")
        spec = parts[0]
        for modifier in parts[1:]:
            if modifier != "testonly":
                fail("Unknown modifier ';{}' in dependency_groups entry '{}'. Only ';testonly' is supported.".format(modifier, entry))
        is_testonly = "testonly" in parts[1:]

        if spec == "transitive":
            include_transitive = True
            transitive_testonly = is_testonly
        elif spec == "*":
            wildcard_testonly = is_testonly
            testonly_overrides = {}  # Reset: * supersedes earlier entries
            parsed_groups.append(spec)
        elif spec.endswith(":*"):
            prefix = spec[:-1]
            testonly_overrides = {
                k: v
                for k, v in testonly_overrides.items()
                if not k.startswith(prefix)
            }
            testonly_overrides[spec] = is_testonly
            parsed_groups.append(spec)
        else:
            testonly_overrides[spec] = is_testonly
            parsed_groups.append(spec)

    testonly_groups = sorted([g for g, t in testonly_overrides.items() if t])
    non_testonly_groups = sorted([g for g, t in testonly_overrides.items() if not t])

    return struct(
        dependency_groups = parsed_groups,
        testonly_groups = testonly_groups,
        non_testonly_groups = non_testonly_groups,
        wildcard_testonly = wildcard_testonly,
        include_transitive = include_transitive,
        transitive_testonly = transitive_testonly,
    )

def _warn_redundant_dependency_groups(repo_name, ws_name, raw_groups):
    has_wildcard = False
    wildcard_is_testonly = False
    redundant_specific = False
    for entry in raw_groups:
        parts = entry.split(";")
        spec = parts[0]
        entry_is_testonly = "testonly" in parts[1:]
        if spec == "*":
            has_wildcard = True
            wildcard_is_testonly = entry_is_testonly
        elif spec not in ("default", "transitive"):
            # Entries that toggle ;testonly after '*' are meaningful overrides, not redundant.
            if not has_wildcard or entry_is_testonly == wildcard_is_testonly:
                redundant_specific = True

    if has_wildcard and redundant_specific:
        # buildifier: disable=print
        print("WARNING: repo '{}' in workspace '{}' specifies both wildcard ('*') and specific dependency groups ({}). The specific groups are redundant.".format(repo_name, ws_name, raw_groups))

def _make_repo(
        ws_tag,
        ws_name,
        repo_name,
        projects,
        raw_dependency_groups,
        transition,
        extra_project_files,
        is_auto_build_repo = False):
    parsed = parse_dependency_group_entries(raw_dependency_groups)
    is_build_tools_repo = repo_name == build_repo_name(ws_name)
    return struct(
        name = repo_name,
        workspace = ws_name,
        local_wheels = getattr(ws_tag, "local_wheels", []),
        transition = transition,
        is_auto_build_repo = is_auto_build_repo,
        is_build_tools_repo = is_build_tools_repo,
        lock_model = struct(
            extra_project_files = extra_project_files,
            lock_file = ws_tag.lock_file,
            projects = projects,
            dependency_groups = parsed.dependency_groups,
            testonly_groups = parsed.testonly_groups,
            non_testonly_groups = parsed.non_testonly_groups,
            wildcard_testonly = parsed.wildcard_testonly,
            include_transitive = parsed.include_transitive,
            transitive_testonly = parsed.transitive_testonly,
            is_build_tools_repo = is_build_tools_repo,
        ),
    )

def _record_root_dep(module, repo_name, is_dev_dependency, root_direct_deps, root_direct_dev_deps):
    if not module.is_root:
        return
    if is_dev_dependency:
        root_direct_dev_deps.append(repo_name)
    else:
        root_direct_deps.append(repo_name)

def process_workspaces(
        module_ctx,
        workspace_tags,
        member_tags,
        discover_members_fn,
        toml_cache = None):
    """Process workspace definitions, discover members, and return structured workspace descriptors.

    Args:
        module_ctx: The module_ctx object.
        workspace_tags: List of `struct(tag, module, is_dev_dependency)` workspace tag wrappers.
        member_tags: List of `struct(tag, transition, module, is_dev_dependency)` repo tag wrappers.
        discover_members_fn: Function(module_ctx, lock_file_label, toml_cache) -> [struct(name, path)].
        toml_cache: Optional dict caching decoded TOML files by label.

    Returns:
        `struct(workspaces, root_direct_deps, root_direct_dev_deps)` where `workspaces` maps
        workspace name -> `struct(name, pypi_indexes, repos)`.
    """

    # Collect workspace definitions.
    ws_infos = {}
    for tag_info in workspace_tags:
        ws_name = tag_info.tag.name
        if ws_name in ws_infos:
            fail("Duplicate workspace name: '{}'".format(ws_name))
        ws_infos[ws_name] = tag_info

    # Auto-discover members and compute extra_project_files for each workspace.
    ws_discovered = {}
    ws_extra_project_files = {}
    for ws_name, ws_info in ws_infos.items():
        ws_tag = ws_info.tag
        discovered = {m.name: m for m in discover_members_fn(module_ctx, ws_tag.lock_file, toml_cache)}
        ws_discovered[ws_name] = discovered

        # The pyproject.toml next to the lock comes first: it's the workspace root
        # (whose settings, such as default-groups, apply to repos spanning several
        # projects), even when the root is a virtual project that isn't discovered
        # as a member. Then the auto-discovered workspace members.
        project_files = []
        sibling = sibling_project_file(ws_tag.lock_file)
        if module_ctx.path(sibling).exists:
            project_files.append(sibling)
        for member_info in discovered.values():
            label = resolve_member_project_file(ws_tag.lock_file, member_info.path)
            if label not in project_files:
                project_files.append(label)

        if not project_files:
            # Nothing found; keep the sibling pyproject.toml as the (missing) default.
            project_files.append(sibling)

        # Append any user-specified extra_project_files, deduplicating.
        for f in getattr(ws_tag, "extra_project_files", []):
            if f not in project_files:
                project_files.append(f)

        ws_extra_project_files[ws_name] = project_files

    # Count explicit repo tags per workspace and validate references.
    ws_repo_count = {ws_name: 0 for ws_name in ws_infos}
    for tag_info in member_tags:
        ws_name = tag_info.tag.workspace
        if ws_name not in ws_repo_count:
            fail("repo tag references non-existent workspace: '{}'".format(ws_name))
        ws_repo_count[ws_name] += 1

    owners = {}
    root_direct_deps = []
    root_direct_dev_deps = []
    ws_repos = {ws_name: [] for ws_name in ws_infos}
    ws_repo_names = {ws_name: {} for ws_name in ws_infos}

    # Register explicit repo tags.
    for tag_info in member_tags:
        tag = tag_info.tag
        ws_name = tag.workspace
        discovered = ws_discovered[ws_name]
        ws_info = ws_infos[ws_name]

        projects = list(getattr(tag, "projects", []))
        if not projects:
            if len(discovered) != 1:
                fail("projects list is empty but workspace '{}' has {} members".format(ws_name, len(discovered)))
            projects = [list(discovered.keys())[0]]

        repo_name = getattr(tag, "name", "")
        if not repo_name:
            if ws_repo_count[ws_name] != 1:
                fail("repo name is required for repo tags in workspace '{}' (multiple repo tags exist)".format(ws_name))
            repo_name = ws_name

        raw_groups = getattr(tag, "dependency_groups", ["default"])
        _warn_redundant_dependency_groups(repo_name, ws_name, raw_groups)

        check_unique_repo_name(owners, tag_info.module.name, repo_name)
        _record_root_dep(
            tag_info.module,
            repo_name,
            getattr(tag_info, "is_dev_dependency", False),
            root_direct_deps,
            root_direct_dev_deps,
        )
        repo = _make_repo(
            ws_tag = ws_info.tag,
            ws_name = ws_name,
            repo_name = repo_name,
            projects = projects,
            raw_dependency_groups = raw_groups,
            transition = getattr(tag_info, "transition", _EMPTY_TRANSITION),
            extra_project_files = ws_extra_project_files[ws_name],
        )
        ws_repos[ws_name].append(repo)
        ws_repo_names[ws_name][repo_name] = True

    # Apply defaulting rules for workspaces with no explicit repo tags.
    for ws_name, ws_info in ws_infos.items():
        if ws_repo_count[ws_name] != 0:
            continue
        discovered = ws_discovered[ws_name]
        if not discovered:
            fail("workspace '{}' contains no projects.".format(ws_name))
        if len(discovered) > 1:
            fail("workspace '{}' contains multiple projects but has no repo tags.".format(ws_name))

        project_name = list(discovered.keys())[0]
        check_unique_repo_name(owners, ws_info.module.name, ws_name)
        _record_root_dep(
            ws_info.module,
            ws_name,
            getattr(ws_info, "is_dev_dependency", False),
            root_direct_deps,
            root_direct_dev_deps,
        )
        repo = _make_repo(
            ws_tag = ws_info.tag,
            ws_name = ws_name,
            repo_name = ws_name,
            projects = [project_name],
            raw_dependency_groups = ["default"],
            transition = _EMPTY_TRANSITION,
            extra_project_files = ws_extra_project_files[ws_name],
        )
        ws_repos[ws_name].append(repo)
        ws_repo_names[ws_name][ws_name] = True

    # Auto-generate the `<ws>__build` thin repo for each workspace unless the user declared one.
    for ws_name, ws_info in ws_infos.items():
        auto_build_repo = build_repo_name(ws_name)
        if auto_build_repo in ws_repo_names[ws_name]:
            continue

        check_unique_repo_name(owners, ws_info.module.name, auto_build_repo)
        repo = _make_repo(
            ws_tag = ws_info.tag,
            ws_name = ws_name,
            repo_name = auto_build_repo,
            projects = ["*"],
            raw_dependency_groups = ["*", "transitive"],
            transition = _EMPTY_TRANSITION,
            extra_project_files = ws_extra_project_files[ws_name],
            is_auto_build_repo = True,
        )
        ws_repos[ws_name].append(repo)

    workspaces = {
        ws_name: struct(
            name = ws_name,
            pypi_indexes = list(getattr(ws_info.tag, "pypi_indexes", [])),
            repos = ws_repos[ws_name],
        )
        for ws_name, ws_info in ws_infos.items()
    }
    return struct(
        workspaces = workspaces,
        root_direct_deps = root_direct_deps,
        root_direct_dev_deps = root_direct_dev_deps,
    )
