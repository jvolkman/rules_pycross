"""Shared helpers for lock import/resolution extensions."""

load("@toml.bzl//toml:toml.bzl", "decode")

def validate_transition_attrs(tag, tag_name):
    """Validates that transition attributes are mutually exclusive.

    Args:
        tag: The tag to validate.
        tag_name: The name of the tag for error messages.
    """
    has_platform = bool(getattr(tag, "platform", None))
    has_flags = bool(getattr(tag, "flags", []))
    has_constraints = bool(getattr(tag, "constraint_values", []))

    if has_platform and (has_flags or has_constraints):
        fail("Tag '{}' cannot specify both 'platform' and ('flags' or 'constraint_values')".format(tag_name))

def package_annotation(
        always_build = False,
        extra_build_tools = [],
        build_tools_repo = None,
        build_target = None,
        ignore_dependencies = [],
        install_exclude_globs = [],
        post_install_patches = [],
        pre_build_patches = [],
        site_hooks = [],
        build_backend = None,
        site_paths = [],
        bin_paths = [],
        data_paths = [],
        include_paths = [],
        wheel_library_tags = []):
    """Annotations to apply to individual packages."""
    return json.encode(struct(
        always_build = always_build,
        extra_build_tools = extra_build_tools,
        build_tools_repo = build_tools_repo,
        build_target = build_target,
        ignore_dependencies = ignore_dependencies,
        install_exclude_globs = install_exclude_globs,
        post_install_patches = post_install_patches,
        pre_build_patches = pre_build_patches,
        site_hooks = site_hooks,
        build_backend = build_backend,
        site_paths = site_paths,
        bin_paths = bin_paths,
        data_paths = data_paths,
        include_paths = include_paths,
        wheel_library_tags = wheel_library_tags,
    ))

def check_unique_repo_name(owners, module_name, repo_name):
    """Check uniqueness using a repo name string instead of a tag."""
    if repo_name in owners:
        fail("lock repo '{}' wanted by module '{}' already created by module '{}'".format(
            repo_name,
            module_name,
            owners[repo_name],
        ))
    owners[repo_name] = module_name

def check_proper_tag_repo(owners, module, tag, tag_desc):
    """Checks that a tag is attached to a valid repo owned by the declaring module.

    Args:
        owners: Dict of repo_name -> module_name.
        module: The module declaring the tag.
        tag: The tag to check.
        tag_desc: Description of the tag for error messages.
    """
    owner = owners.get(tag.repo)
    if owner == None:
        fail(
            "{} declared by module '{}' attached to non-existent lock repo '{}'".format(
                tag_desc,
                module.name,
                tag.repo,
            ),
        )
    elif owner != module.name:
        fail(
            "{} declared by module '{}' attached to lock repo '{}' owned by other module '{}'".format(
                tag_desc,
                module.name,
                tag.repo,
                owner,
            ),
        )

def check_proper_package_repo(owners, module, tag):
    check_proper_tag_repo(owners, module, tag, "package '{}'".format(tag.name))

def workspace_lock_struct(ws_tag, repo_name, workspace_name, transition_attrs):
    """Create a lock struct for a workspace member, inheriting workspace-level settings."""
    return struct(
        repo_name = repo_name,
        workspace = workspace_name,
        create_transitive_aliases = transition_attrs.get("create_transitive_aliases", False),
        local_wheels = ws_tag.local_wheels,
        disallow_builds = ws_tag.disallow_builds,
        packages = {},
        flags = transition_attrs.get("flags", []),
        constraint_values = transition_attrs.get("constraint_values", []),
        platform = transition_attrs.get("platform"),
    )

def normalize_package_tag(tag):
    """Normalize a generic package tag into a struct."""
    return struct(
        always_build = tag.always_build,
        extra_build_tools = tag.extra_build_tools,
        build_tools_repo = tag.build_tools_repo,
        build_target = tag.build_target,
        ignore_dependencies = tag.ignore_dependencies,
        install_exclude_globs = tag.install_exclude_globs,
        post_install_patches = [str(label) for label in tag.post_install_patches],
        pre_build_patches = [str(label) for label in tag.pre_build_patches],
        site_hooks = tag.site_hooks,
        build_backend = tag.build_backend if tag.build_backend else None,
        site_paths = tag.site_paths,
        bin_paths = tag.bin_paths,
        data_paths = tag.data_paths,
        include_paths = tag.include_paths,
        wheel_library_tags = tag.wheel_library_tags,
    )

def discover_uv_all_members(mctx, lock_file_label):
    """Parse uv.lock and return workspace members (editable packages).

    Args:
        mctx: The module_ctx object.
        lock_file_label: Label of the uv.lock file.

    Returns:
        A list of structs with 'name' and 'path' fields.
    """
    lock_content = mctx.read(lock_file_label)
    lock_data = decode(lock_content)

    # uv.lock uses "package" (newer) or "distribution" (older) for the package list.
    packages_list = lock_data.get("package", lock_data.get("distribution", []))

    members = []
    for pkg in packages_list:
        source = pkg.get("source", {})
        if "editable" in source:
            members.append(struct(
                name = pkg["name"],
                path = source["editable"],
            ))
        elif "virtual" in source:
            # Only include virtual members that have actual dependencies.
            # A virtual workspace root with no dependencies is just the workspace
            # definition and shouldn't produce a lock repo.
            has_deps = (
                pkg.get("dependencies") or
                pkg.get("optional-dependencies") or
                pkg.get("dev-dependencies")
            )
            if has_deps:
                members.append(struct(
                    name = pkg["name"],
                    path = source["virtual"],
                ))

    return members

def discover_pdm_all_members(mctx, lock_file_label):
    """Parse pdm.lock and return workspace members (editable local packages).

    Args:
        mctx: The module_ctx object.
        lock_file_label: Label of the pdm.lock file.

    Returns:
        A list of structs with 'name' and 'path' fields.
    """
    lock_content = mctx.read(lock_file_label)
    lock_data = decode(lock_content)

    packages_list = lock_data.get("package", [])

    members = []
    for pkg in packages_list:
        # PDM marks workspace members with editable = true and a path.
        if pkg.get("editable") and "path" in pkg:
            members.append(struct(
                name = pkg["name"],
                path = pkg["path"],
            ))

    return members

def discover_poetry_all_members(_mctx, _lock_file_label):
    return [struct(name = "root", path = "")]

def discover_pylock_all_members(_mctx, _lock_file_label):
    return [struct(name = "root", path = "")]

def resolve_member_project_file(lock_file_label, member_path):
    """Resolve a member's pyproject.toml label relative to the lock file.

    Args:
        lock_file_label: Label of the uv.lock file.
        member_path: Relative path from lock file to member directory (e.g. "./packages/lib-a").

    Returns:
        A Label pointing to the member's pyproject.toml.
    """

    # Strip leading "./" if present
    clean_path = member_path
    if clean_path.startswith("./"):
        clean_path = clean_path[2:]
    if clean_path == ".":
        clean_path = ""

    # Build the package path relative to the lock file's package
    lock_package = lock_file_label.package
    if lock_package:
        member_package = lock_package + ("/" + clean_path if clean_path else "")
    else:
        member_package = clean_path

    if member_package:
        return lock_file_label.relative("//{}:pyproject.toml".format(member_package))
    else:
        return lock_file_label.relative("//:pyproject.toml")

def get_member_transition_attrs(members_tag, override_tag):
    """Merge transition attrs from a default members tag and optional override tag.

    Args:
        members_tag: The default tag providing fallback transition values.
        override_tag: The override tag providing explicit transition values.

    Returns:
        A dict with merged transition attributes (flags, constraint_values, platform).
    """
    has_explicit_flags = override_tag and getattr(override_tag, "flags", [])
    has_explicit_constraints = override_tag and getattr(override_tag, "constraint_values", [])
    has_explicit_platform = override_tag and getattr(override_tag, "platform", None)

    # create_transitive_aliases: override wins if set, otherwise inherit from members_tag
    create_transitive_aliases = False
    if override_tag and getattr(override_tag, "create_transitive_aliases", False):
        create_transitive_aliases = True
    elif members_tag and getattr(members_tag, "create_transitive_aliases", False):
        create_transitive_aliases = True

    if override_tag and (has_explicit_flags or has_explicit_constraints or has_explicit_platform):
        return dict(
            flags = getattr(override_tag, "flags", []),
            constraint_values = [str(c) for c in getattr(override_tag, "constraint_values", [])],
            platform = str(override_tag.platform) if override_tag.platform else None,
            create_transitive_aliases = create_transitive_aliases,
        )

    return dict(
        flags = getattr(members_tag, "flags", []) if members_tag else [],
        constraint_values = [str(c) for c in getattr(members_tag, "constraint_values", [])] if members_tag else [],
        platform = str(members_tag.platform) if members_tag and getattr(members_tag, "platform", None) else None,
        create_transitive_aliases = create_transitive_aliases,
    )

def register_workspace_repo(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        ws_name,
        model_type,
        repo_name,
        projects,
        dependency_groups,
        legacy_create_root_aliases,
        transition_attrs,
        lock_module,
        extra_project_files):
    """Register a workspace lock repo.

    Args:
        lock_owners: Dict to track repo ownership.
        lock_repos: Dict to store repo configs.
        lock_model_structs: Dict to store serialized lock models.
        root_direct_deps: List to store root direct dependencies.
        ws_tag: The workspace tag.
        ws_name: The workspace name.
        model_type: The lock model type.
        repo_name: The repo name for this member.
        projects: List of projects included in this repo.
        dependency_groups: List of dependency groups.
        legacy_create_root_aliases: Boolean to create root aliases.
        transition_attrs: Transition attributes dict.
        lock_module: The module owning this lock.
        extra_project_files: List of extra pyproject.toml files.
    """
    check_unique_repo_name(lock_owners, lock_module.name, repo_name)
    lock_repos[repo_name] = workspace_lock_struct(ws_tag, repo_name, ws_name, transition_attrs)
    if lock_module.is_root:
        root_direct_deps.append(repo_name)

    model = dict(
        model_type = model_type,
        extra_project_files = [str(f) for f in extra_project_files],
        lock_file = str(ws_tag.lock_file),
        projects = projects,
        dependency_groups = dependency_groups,
        legacy_create_root_aliases = legacy_create_root_aliases,
    )

    # Handle attributes that are not common across all lock formats
    for attr_name in ("require_static_urls",):
        if hasattr(ws_tag, attr_name):
            model[attr_name] = getattr(ws_tag, attr_name)
    lock_model_structs[repo_name] = json.encode(model)

def process_repo(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        ws_name,
        tag_info,
        model_type,
        extra_project_files):
    """Processes a single repo tag.

    Args:
        lock_owners: Dict to track repo ownership.
        lock_repos: Dict to store repo configs.
        lock_model_structs: Dict to store serialized lock models.
        root_direct_deps: List to store root direct dependencies.
        ws_tag: The workspace tag.
        ws_name: The workspace name.
        tag_info: The repo tag info.
        model_type: The lock model type.
        extra_project_files: List of extra pyproject.toml files.
    """
    tag = tag_info.tag

    dependency_groups = tag.dependency_groups
    has_wildcard = "*" in dependency_groups
    has_specific = False
    for group in dependency_groups:
        if group not in ("*", "default"):
            has_specific = True
            break

    if has_wildcard and has_specific:
        # buildifier: disable=print
        print("WARNING: repo '{}' in workspace '{}' specifies both wildcard ('*') and specific dependency groups ({}). The specific groups are redundant.".format(tag.repo, ws_name, dependency_groups))

    # Get transition attrs
    transition_attrs = get_member_transition_attrs(None, tag)

    register_workspace_repo(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        ws_name,
        model_type,
        tag.repo,
        tag.projects,
        tag.dependency_groups,
        tag.legacy_create_root_aliases,
        transition_attrs,
        tag_info.module,
        extra_project_files,
    )

def process_workspaces(
        module_ctx,
        lock_owners,
        lock_repos,
        lock_model_structs,
        workspace_tags,
        member_tags,
        discover_members_fn,
        model_type,
        root_direct_deps):
    """Processes workspace definitions, discovers members, and processes them.

    Args:
        module_ctx: The module_ctx object.
        lock_owners: Dict to track repo ownership.
        lock_repos: Dict to store repo configs.
        lock_model_structs: Dict to store serialized lock models.
        workspace_tags: List of workspace tags.
        member_tags: List of member tags.
        discover_members_fn: Function to discover members.
        model_type: The lock model type.
        root_direct_deps: List to store root direct dependencies.
    """

    # Collect workspace definitions
    workspaces = {}
    for tag_info in workspace_tags:
        if tag_info.ws_name in workspaces:
            fail("Duplicate workspace name: '{}'".format(tag_info.ws_name))
        workspaces[tag_info.ws_name] = tag_info

    # Auto-discover members for each workspace
    workspace_discovered_members = {}
    for name, ws_info in workspaces.items():
        discovered = discover_members_fn(module_ctx, ws_info.tag.lock_file)
        workspace_discovered_members[name] = {m.name: m for m in discovered}

    # Compute extra_project_files for each workspace (explicit or auto-discovered)
    workspace_extra_project_files = {}
    for name, ws_info in workspaces.items():
        ws_tag = ws_info.tag

        # Always start with auto-discovered project files from workspace members.
        project_files = []
        discovered = workspace_discovered_members[name]
        for member_info in discovered.values():
            label = resolve_member_project_file(ws_tag.lock_file, member_info.path)
            project_files.append(label)

        if not project_files:
            # No workspace members discovered; fall back to sibling pyproject.toml.
            project_files.append(ws_tag.lock_file.relative(":pyproject.toml"))

        # Append any user-specified extra_project_files, deduplicating.
        for f in getattr(ws_tag, "extra_project_files", []):
            if f not in project_files:
                project_files.append(f)

        workspace_extra_project_files[name] = project_files

    # Count repos per workspace
    workspace_repo_count = {name: 0 for name in workspaces}
    for tag_info in member_tags:
        if tag_info.tag.workspace in workspace_repo_count:
            workspace_repo_count[tag_info.tag.workspace] += 1
        else:
            fail("repo tag references non-existent workspace: '{}'".format(tag_info.tag.workspace))

    # Apply Defaulting Rules
    for ws_name, ws_info in workspaces.items():
        if workspace_repo_count[ws_name] == 0:
            discovered = workspace_discovered_members[ws_name]
            if len(discovered) == 1:
                # Auto-create implicit repo for the only project
                project_name = list(discovered.keys())[0]
                implicit_tag = struct(
                    workspace = ws_name,
                    projects = [project_name],
                    repo = ws_name,
                    dependency_groups = ["default"],
                    legacy_create_root_aliases = False,
                    flags = [],
                    constraint_values = [],
                    platform = None,
                    create_transitive_aliases = False,
                )
                member_tags.append(struct(tag = implicit_tag, module = ws_info.module))
                workspace_repo_count[ws_name] += 1
            elif len(discovered) > 1:
                fail("workspace '{}' contains multiple projects but has no repo tags.".format(ws_name))
            else:
                fail("workspace '{}' contains no projects.".format(ws_name))

    for tag_info in member_tags:
        tag = tag_info.tag
        ws_name = tag.workspace
        discovered = workspace_discovered_members[ws_name]
        ws_info = workspaces[ws_name]

        projects = getattr(tag, "projects", [])
        if not projects:
            if len(discovered) == 1:
                projects = [list(discovered.keys())[0]]
            else:
                fail("projects list is empty but workspace '{}' has {} members".format(ws_name, len(discovered)))

        repo = tag.repo
        if not repo:
            if workspace_repo_count[ws_name] == 1:
                repo = ws_name
            else:
                fail("repo name is required for repo tags in workspace '{}' (multiple repo tags exist)".format(ws_name))

        # Build complete tag
        new_tag = struct(
            workspace = ws_name,
            projects = projects,
            repo = repo,
            dependency_groups = getattr(tag, "dependency_groups", ["default"]),
            legacy_create_root_aliases = getattr(tag, "legacy_create_root_aliases", False),
            flags = getattr(tag, "flags", []),
            constraint_values = getattr(tag, "constraint_values", []),
            platform = getattr(tag, "platform", None),
            create_transitive_aliases = getattr(tag, "create_transitive_aliases", False),
        )
        new_tag_info = struct(tag = new_tag, module = tag_info.module)

        process_repo(
            lock_owners,
            lock_repos,
            lock_model_structs,
            root_direct_deps,
            ws_info.tag,
            ws_name,
            new_tag_info,
            model_type,
            workspace_extra_project_files[ws_name],
        )

    # Auto-generate the __build thin repo for this workspace.
    for ws_name, ws_info in workspaces.items():
        build_repo_name = "{}__build".format(ws_name)

        if build_repo_name in lock_repos:
            continue

        register_workspace_repo(
            lock_owners = lock_owners,
            lock_repos = lock_repos,
            lock_model_structs = lock_model_structs,
            root_direct_deps = [],  # Do not report as root direct dep
            ws_tag = ws_info.tag,
            ws_name = ws_name,
            model_type = model_type,
            repo_name = build_repo_name,
            projects = ["*"],
            dependency_groups = ["*"],
            legacy_create_root_aliases = False,
            transition_attrs = dict(
                flags = [],
                constraint_values = [],
                platform = None,
                create_transitive_aliases = True,
            ),
            lock_module = ws_info.module,
            extra_project_files = workspace_extra_project_files[ws_name],
        )
