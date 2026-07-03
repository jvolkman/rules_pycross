"""Shared helpers for lock import/resolution extensions."""

load("@toml.bzl//toml:toml.bzl", "decode")
load(
    ":lock_attrs.bzl",
    "COMMON_IMPORT_ATTRS",
    "CREATE_REPOS_ATTRS",
    "OVERRIDE_TARGET_ATTRS",
    "PACKAGE_ATTRS",
    "PDM_ALL_MEMBERS_ATTRS",
    "PDM_IMPORT_ATTRS",
    "PDM_MEMBER_ATTRS",
    "PDM_WORKSPACE_ATTRS",
    "POETRY_IMPORT_ATTRS",
    "POETRY_MEMBER_ATTRS",
    "PYLOCK_IMPORT_ATTRS",
    "PYLOCK_MEMBER_ATTRS",
    "REPO_ATTR",
    "UV_ALL_MEMBERS_ATTRS",
    "UV_IMPORT_ATTRS",
    "UV_MEMBER_ATTRS",
    "UV_WORKSPACE_ATTRS",
    "WORKSPACE_COMMON_ATTRS",
    "WORKSPACE_MEMBER_COMMON_ATTRS",
)

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
        build_dependencies = [],
        build_repo = None,
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
        include_paths = []):
    """Annotations to apply to individual packages."""
    return json.encode(struct(
        always_build = always_build,
        build_dependencies = build_dependencies,
        build_repo = build_repo,
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
        build_dependencies = tag.build_dependencies,
        build_repo = tag.build_repo,
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

def determine_project_file(override_tag, model_type, lock_file_label, member_path):
    """Determines the project file path for a member.

    Args:
        override_tag: The override tag, if any.
        model_type: The type of lock model.
        lock_file_label: Label of the lock file.
        member_path: Path to the member.

    Returns:
        The project file path or Label.
    """
    if override_tag and override_tag.project_file:
        return override_tag.project_file
    elif model_type == "pylock":
        return ""
    else:
        return resolve_member_project_file(lock_file_label, member_path)

# (Deleted get_member_group_attrs)

def get_member_transition_attrs(members_tag, override_tag):
    """Merge transition attrs from an all_members default and optional member override.

    Args:
        members_tag: The default members tag.
        override_tag: The member override tag.

    Returns:
        A dict with merged transition attributes (flags, constraint_values, platform).
    """
    has_explicit_flags = override_tag and getattr(override_tag, "flags", [])
    has_explicit_constraints = override_tag and getattr(override_tag, "constraint_values", [])
    has_explicit_platform = override_tag and getattr(override_tag, "platform", None)

    # create_transitive_aliases: override wins if set, otherwise inherit from all_projects
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
        project_file,
        projects,
        dependency_groups,
        legacy_create_root_aliases,
        transition_attrs,
        lock_module):
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
        project_file: The project file for this member.
        projects: List of projects included in this repo.
        dependency_groups: List of dependency groups.
        legacy_create_root_aliases: Boolean to create root aliases.
        transition_attrs: Transition attributes dict.
        lock_module: The module owning this lock.
    """
    check_unique_repo_name(lock_owners, lock_module.name, repo_name)
    lock_repos[repo_name] = workspace_lock_struct(ws_tag, repo_name, ws_name, transition_attrs)
    if lock_module.is_root:
        root_direct_deps.append(repo_name)

    model = dict(
        model_type = model_type,
        project_file = str(project_file) if project_file else "",
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
        discovered_members):
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
        discovered_members: Dict of discovered members.
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

    # Check that any specific projects requested exist
    projects_list = tag.projects
    if "*" not in projects_list:
        for p in projects_list:
            if p not in discovered_members:
                # If there is only one discovered member and its name is "root" (poetry/pylock), allow it
                if len(discovered_members) == 1 and "root" in discovered_members:
                    continue

                # We allow it to pass through and fail in the translator, as the translator
                # might support standalone locks where the project name isn't in discovered members
                pass

    # Determine project_file (just grab the first project's path if we need one for legacy translators)
    member_path = ""
    if projects_list and projects_list[0] != "*":
        if projects_list[0] in discovered_members:
            member_path = discovered_members[projects_list[0]].path
    elif len(discovered_members) == 1:
        member_path = list(discovered_members.values())[0].path
    project_file = determine_project_file(tag, model_type, ws_tag.lock_file, member_path)

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
        project_file,
        tag.projects,
        tag.dependency_groups,
        tag.legacy_create_root_aliases,
        transition_attrs,
        tag_info.module,
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
                    project_file = None,
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
            project_file = getattr(tag, "project_file", None),
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
            discovered,
        )

def process_import_tags(module_ctx):
    """Processes all import tags from all modules and returns aggregated lock data.

    Args:
        module_ctx: The module_ctx object.

    Returns:
        A struct containing aggregated lock data.
    """
    lock_owners = {}
    lock_repos = {}
    root_direct_deps = []
    lock_model_structs = {}

    for name, tag_prefixes, discover_fn in [
        ("uv", ["import_uv", "import_uv_workspace"], discover_uv_all_members),
        ("pdm", ["import_pdm", "import_pdm_workspace"], discover_pdm_all_members),
        ("poetry", ["import_poetry"], discover_poetry_all_members),
        ("pylock", ["import_pylock"], discover_pylock_all_members),
    ]:
        workspace_tags = []
        member_tags = []
        all_members_tags = []

        import_tag_name = tag_prefixes[0]
        import_ws_tag_name = tag_prefixes[1] if len(tag_prefixes) > 1 else None

        for module in module_ctx.modules:
            # 1. Process workspace tags
            if import_ws_tag_name:
                for tag in getattr(module.tags, import_ws_tag_name):
                    workspace_tags.append(struct(tag = tag, module = module, ws_name = tag.name))
                for tag in getattr(module.tags, name + "_all_members"):
                    validate_transition_attrs(tag, name + "_all_members")
                    all_members_tags.append(struct(tag = tag, module = module))

            for tag in getattr(module.tags, name + "_member"):
                validate_transition_attrs(tag, name + "_member")
                member_tags.append(struct(tag = tag, module = module))

            # 2. Process legacy/standalone import tags (desugar)
            for tag in getattr(module.tags, import_tag_name):
                validate_transition_attrs(tag, import_tag_name)

                # Synthesis workspace
                workspace_tags.append(struct(tag = tag, module = module, ws_name = tag.repo))

                # Synthesis member
                member_tag = struct(
                    workspace = tag.repo,
                    projects = [],
                    repo = tag.repo,
                    project_file = getattr(tag, "project_file", None),
                    dependency_groups = ["default"],
                    legacy_create_root_aliases = getattr(tag, "legacy_create_root_aliases", False),
                    flags = getattr(tag, "flags", []),
                    constraint_values = getattr(tag, "constraint_values", []),
                    platform = getattr(tag, "platform", None),
                    create_transitive_aliases = getattr(tag, "create_transitive_aliases", False),
                )
                member_tags.append(struct(tag = member_tag, module = module))

        process_workspaces(
            module_ctx,
            lock_owners,
            lock_repos,
            lock_model_structs,
            workspace_tags,
            member_tags,
            all_members_tags,
            discover_fn,
            name,
            root_direct_deps,
        )

    workspace_packages = {}  # workspace_name -> {pkg_name -> normalized_tag}
    valid_workspaces = {r.workspace: True for r in lock_repos.values()}

    # Add package attributes
    for module in module_ctx.modules:
        for tag in module.tags.package:
            if tag.repo and tag.workspace:
                fail("package '{}' specifies both repo and workspace".format(tag.name))
            if not tag.repo and not tag.workspace:
                fail("package '{}' must specify either repo or workspace".format(tag.name))

            normalized = normalize_package_tag(tag)
            if tag.repo:
                check_proper_package_repo(lock_owners, module, tag)
                repo_info = lock_repos[tag.repo]
                if repo_info.workspace != repo_info.repo_name:
                    fail(
                        "package '{}' targets repo '{}' which is a member of workspace '{}'. ".format(tag.name, tag.repo, repo_info.workspace) +
                        "Use workspace = '{}' instead.".format(repo_info.workspace),
                    )
                if tag.name in repo_info.packages:
                    fail("Multiple package entries for package '{}' in repo '{}'".format(tag.name, tag.repo))
                repo_info.packages[tag.name] = normalized
            elif tag.workspace:
                # We intentionally don't enforce `check_proper_package_repo` for workspaces.
                # Workspaces are top-level constructs, and it's acceptable for any module to
                # inject packages into a shared workspace configuration.
                if tag.workspace not in valid_workspaces:
                    fail("Package override specifies workspace '{}' which does not exist".format(tag.workspace))
                ws_pkgs = workspace_packages.setdefault(tag.workspace, {})
                if tag.name in ws_pkgs:
                    fail("Multiple package entries for package '{}' in workspace '{}'".format(tag.name, tag.workspace))
                ws_pkgs[tag.name] = normalized

    # Generate the resolved lock repos
    workspace_memberships = {}
    repo_flags = {}
    repo_constraint_values = {}
    repo_platforms = {}
    repo_disallow_builds = {}

    for repo_info in lock_repos.values():
        workspace_memberships[repo_info.repo_name] = repo_info.workspace

        if repo_info.flags:
            repo_flags[repo_info.repo_name] = json.encode(repo_info.flags)
        if repo_info.constraint_values:
            repo_constraint_values[repo_info.repo_name] = json.encode(repo_info.constraint_values)
        if repo_info.platform:
            repo_platforms[repo_info.repo_name] = repo_info.platform
        if repo_info.disallow_builds:
            repo_disallow_builds[repo_info.repo_name] = True

    return struct(
        lock_repos = lock_repos,
        lock_model_structs = lock_model_structs,
        workspace_packages = workspace_packages,
        root_direct_deps = root_direct_deps,
        workspace_memberships = workspace_memberships,
        repo_flags = repo_flags,
        repo_constraint_values = repo_constraint_values,
        repo_platforms = repo_platforms,
        repo_disallow_builds = repo_disallow_builds,
    )

IMPORT_TAG_CLASSES = dict(
    import_pdm = tag_class(doc = "Import a PDM lock file.", attrs = PDM_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR),
    import_poetry = tag_class(doc = "Import a Poetry lock file.", attrs = POETRY_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR),
    import_uv = tag_class(doc = "Import a uv lock file.", attrs = UV_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR),
    import_pylock = tag_class(doc = "Import a pylock.toml lock file.", attrs = PYLOCK_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR),
    import_pdm_workspace = tag_class(doc = "Import a PDM workspace.", attrs = PDM_WORKSPACE_ATTRS | WORKSPACE_COMMON_ATTRS),
    pdm_all_members = tag_class(doc = "Auto-discover and import all members from a pdm.lock file.", attrs = PDM_ALL_MEMBERS_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS),
    pdm_member = tag_class(doc = "Override settings for a specific PDM member.", attrs = PDM_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS),
    import_uv_workspace = tag_class(doc = "Import a uv workspace. Define members with uv_all_members and uv_member tags.", attrs = UV_WORKSPACE_ATTRS | WORKSPACE_COMMON_ATTRS),
    uv_all_members = tag_class(doc = "Auto-discover and import all members from a uv.lock file.", attrs = UV_ALL_MEMBERS_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS),
    uv_member = tag_class(doc = "Override settings for a specific member.", attrs = UV_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS),
    poetry_member = tag_class(doc = "Override settings for a specific Poetry member.", attrs = POETRY_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS),
    pylock_member = tag_class(doc = "Override settings for a specific Pylock member.", attrs = PYLOCK_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS),
    package = tag_class(doc = "Specify package-specific settings.", attrs = PACKAGE_ATTRS | OVERRIDE_TARGET_ATTRS),
)

CREATE_TAG_CLASS = tag_class(
    doc = "Create declared Pycross repos.",
    attrs = CREATE_REPOS_ATTRS,
)
