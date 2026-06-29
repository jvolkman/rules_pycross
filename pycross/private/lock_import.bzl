"""The lock_import extension."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@toml.bzl//toml:toml.bzl", "decode")
load("//pycross/private:resolved_lock_repo.bzl", "resolved_lock_repo")
load("//pycross/private:util.bzl", "sanitize_name")
load(
    ":lock_attrs.bzl",
    "COMMON_IMPORT_ATTRS",
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
load(":lock_workspace_repo.bzl", "lock_workspace_repo")

def _validate_transition_attrs(tag, tag_name):
    has_platform = bool(getattr(tag, "platform", None))
    has_flags = bool(getattr(tag, "flags", []))
    has_constraints = bool(getattr(tag, "constraint_values", []))

    if has_platform and (has_flags or has_constraints):
        fail("Tag '{}' cannot specify both 'platform' and ('flags' or 'constraint_values')".format(tag_name))

def _package_annotation(
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

def _generate_resolved_lock_repo(lock_info, serialized_lock_model, workspace_packages):
    repo_name = lock_info.repo_name
    args = {
        "name": repo_name,
        "lock_model": serialized_lock_model,
        "default_alias_single_version": lock_info.default_alias_single_version,
        "default_build_dependencies": lock_info.default_build_dependencies,
        "disallow_builds": lock_info.disallow_builds,
        "local_wheels": lock_info.local_wheels,
        "annotations": {},
    }

    # Workspace-level packages first, then repo-level packages override.
    all_packages = {}
    for package_name, package in workspace_packages.get(lock_info.workspace, {}).items():
        all_packages[package_name] = package
    for package_name, package in lock_info.packages.items():
        all_packages[package_name] = package

    for package_name, package in all_packages.items():
        args["annotations"][package_name] = _package_annotation(
            always_build = package.always_build,
            build_dependencies = package.build_dependencies,
            build_repo = package.build_repo,
            build_target = str(package.build_target) if package.build_target else None,
            ignore_dependencies = package.ignore_dependencies,
            install_exclude_globs = package.install_exclude_globs,
            post_install_patches = package.post_install_patches,
            pre_build_patches = package.pre_build_patches,
            site_hooks = package.site_hooks,
            build_backend = package.build_backend,
            site_paths = package.site_paths,
            bin_paths = package.bin_paths,
            data_paths = package.data_paths,
            include_paths = package.include_paths,
        )

    resolved_lock_repo(**args)
    return "@{}//:lock.json".format(repo_name)

def _check_unique_repo_name(owners, module_name, repo_name):
    """Check uniqueness using a repo name string instead of a tag."""
    if repo_name in owners:
        fail("lock repo '{}' wanted by module '{}' already created by module '{}'".format(
            repo_name,
            module_name,
            owners[repo_name],
        ))
    owners[repo_name] = module_name

def _check_proper_tag_repo(owners, module, tag, tag_desc):
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

def _check_proper_package_repo(owners, module, tag):
    _check_proper_tag_repo(owners, module, tag, "package '{}'".format(tag.name))

def _workspace_lock_struct(ws_tag, repo_name, workspace_name, transition_attrs):
    """Create a lock struct for a workspace member, inheriting workspace-level settings."""
    return struct(
        repo_name = repo_name,
        workspace = workspace_name,
        build_repo = ws_tag.build_repo,
        default_alias_single_version = ws_tag.default_alias_single_version,
        local_wheels = ws_tag.local_wheels,
        disallow_builds = ws_tag.disallow_builds,
        default_build_dependencies = ws_tag.default_build_dependencies,
        packages = {},
        flags = transition_attrs.get("flags", []),
        constraint_values = transition_attrs.get("constraint_values", []),
        platform = transition_attrs.get("platform"),
    )

def _normalize_package_tag(tag):
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

def _discover_uv_all_members(mctx, lock_file_label):
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

def _discover_pdm_all_members(mctx, lock_file_label):
    """Parse pdm.lock and return workspace members (editable local packages)."""
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

def _discover_poetry_all_members(_mctx, _lock_file_label):
    return [struct(name = "root", path = "")]

def _discover_pylock_all_members(_mctx, _lock_file_label):
    return [struct(name = "root", path = "")]

def _resolve_member_project_file(lock_file_label, member_path):
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

def _determine_project_file(override_tag, model_type, lock_file_label, member_path):
    if override_tag and override_tag.project_file:
        return override_tag.project_file
    elif model_type == "pylock":
        return ""
    else:
        return _resolve_member_project_file(lock_file_label, member_path)

def _get_member_group_attrs(members_tag, override_tag):
    """Merge group attrs from an all_members default and optional member override.

    Design: boolean flags live at exactly one level to avoid clobber issues
    (Starlark booleans have no None sentinel).
      - default_group: only on the override tag (per-member decision).
      - all_optional_groups: only on the all_members tag (group-wide).
        If the override specifies an explicit optional_groups list, all_optional_groups
        is disabled for that member.
      - all_development_groups: same pattern as all_optional_groups.
    """
    has_explicit_optional = override_tag and override_tag.optional_groups
    has_explicit_development = override_tag and override_tag.development_groups

    return dict(
        default_group = override_tag.default_group if override_tag else True,
        optional_groups = override_tag.optional_groups if has_explicit_optional else (members_tag.optional_groups if hasattr(members_tag, "optional_groups") else []),
        all_optional_groups = (members_tag.all_optional_groups if hasattr(members_tag, "all_optional_groups") else False) and not has_explicit_optional,
        development_groups = override_tag.development_groups if has_explicit_development else (members_tag.development_groups if hasattr(members_tag, "development_groups") else []),
        all_development_groups = (members_tag.all_development_groups if hasattr(members_tag, "all_development_groups") else False) and not has_explicit_development,
    )

def _get_member_transition_attrs(members_tag, override_tag):
    """Merge transition attrs from an all_members default and optional member override."""
    has_explicit_flags = override_tag and getattr(override_tag, "flags", [])
    has_explicit_constraints = override_tag and getattr(override_tag, "constraint_values", [])
    has_explicit_platform = override_tag and getattr(override_tag, "platform", None)

    if override_tag and (has_explicit_flags or has_explicit_constraints or has_explicit_platform):
        return dict(
            flags = getattr(override_tag, "flags", []),
            constraint_values = [str(c) for c in getattr(override_tag, "constraint_values", [])],
            platform = str(override_tag.platform) if override_tag.platform else None,
        )

    return dict(
        flags = getattr(members_tag, "flags", []) if members_tag else [],
        constraint_values = [str(c) for c in getattr(members_tag, "constraint_values", [])] if members_tag else [],
        platform = str(members_tag.platform) if members_tag and getattr(members_tag, "platform", None) else None,
    )

def _register_workspace_member(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        ws_name,
        model_type,
        repo_name,
        project_file,
        group_attrs,
        transition_attrs,
        lock_module):
    """Register a single workspace member as a lock repo with its model.

    This is the shared registration path for both bulk (uv_all_members)
    and standalone (uv_member) imports.
    """
    _check_unique_repo_name(lock_owners, lock_module.name, repo_name)
    lock_repos[repo_name] = _workspace_lock_struct(ws_tag, repo_name, ws_name, transition_attrs)
    if lock_module.is_root:
        root_direct_deps.append(repo_name)

    model = dict(
        model_type = model_type,
        project_file = str(project_file),
        lock_file = str(ws_tag.lock_file),
        **group_attrs
    )

    # Handle attributes that are not common across all lock formats
    for attr_name in ("require_static_urls",):
        if hasattr(ws_tag, attr_name):
            model[attr_name] = getattr(ws_tag, attr_name)
    lock_model_structs[repo_name] = json.encode(model)

def _process_member(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        ws_name,
        member,
        model_type,
        overrides,
        default_module,
        members_tag = None):
    for override in overrides:
        # Determine repo name
        normalized_name = sanitize_name(member.name)
        if override and override.tag.repo:
            repo_name = override.tag.repo
        elif members_tag and hasattr(members_tag, "repo_pattern"):
            repo_name = members_tag.repo_pattern.format(member = normalized_name)
        else:
            repo_name = normalized_name

        # Determine project_file
        project_file = _determine_project_file(override.tag if override else None, model_type, ws_tag.lock_file, member.path)

        # Get group attrs (override wins)
        group_attrs = _get_member_group_attrs(members_tag or struct(), override.tag if override else None)

        # Get transition attrs (override wins)
        transition_attrs = _get_member_transition_attrs(members_tag or struct(), override.tag if override else None)

        lock_module = override.module if override else default_module

        _register_workspace_member(
            lock_owners,
            lock_repos,
            lock_model_structs,
            root_direct_deps,
            ws_tag,
            ws_name,
            model_type,
            repo_name,
            project_file,
            group_attrs,
            transition_attrs,
            lock_module,
        )

def _process_workspaces(
        module_ctx,
        lock_owners,
        lock_repos,
        lock_model_structs,
        workspace_tags,
        member_tags,
        all_members_tags,
        discover_members_fn,
        model_type,
        root_direct_deps):
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

    # Collect per-member overrides indexed by (workspace, project)
    member_overrides = {}
    for tag_info in member_tags:
        tag = tag_info.tag
        module = tag_info.module
        if tag.workspace not in workspaces:
            fail("member tag references non-existent workspace: '{}'".format(tag.workspace))

        # If project is omitted, infer from discovered members.
        project = tag.project
        if not project:
            discovered = workspace_discovered_members[tag.workspace]
            if len(discovered) == 1:
                project = list(discovered.keys())[0]
            elif len(discovered) == 0:
                fail("no members discovered in workspace '{}'; cannot infer project".format(tag.workspace))
            else:
                fail("workspace '{}' has {} members ({}); 'project' is required to disambiguate".format(
                    tag.workspace,
                    len(discovered),
                    ", ".join(sorted(discovered.keys())),
                ))

        key = (tag.workspace, project)
        if key not in member_overrides:
            member_overrides[key] = []

        # Check for duplicate repo names within the same project override
        for existing in member_overrides[key]:
            if existing.tag.repo and tag.repo and existing.tag.repo == tag.repo:
                fail("Duplicate member override for project '{}' with repo '{}' in workspace '{}'".format(project, tag.repo, tag.workspace))

        member_overrides[key].append(tag_info)

    processed_members = {}  # (workspace, project) -> True

    # Process bulk member imports
    for tag_info in all_members_tags:
        tag = tag_info.tag
        module = tag_info.module
        if tag.workspace not in workspaces:
            fail("all_members tag references non-existent workspace: '{}'".format(tag.workspace))

        ws_info = workspaces[tag.workspace]
        ws_tag = ws_info.tag

        discovered = workspace_discovered_members[tag.workspace]
        excluded = {p: True for p in tag.excluded_projects}

        for member_name, member in discovered.items():
            if member_name in excluded:
                continue

            processed_members[(tag.workspace, member_name)] = True

            overrides = member_overrides.get((tag.workspace, member_name), [None])

            _process_member(
                lock_owners,
                lock_repos,
                lock_model_structs,
                root_direct_deps,
                ws_tag,
                tag.workspace,
                member,
                model_type,
                overrides,
                module,
                members_tag = tag,
            )

    # Process standalone member imports
    for key, overrides in member_overrides.items():
        if key in processed_members:
            continue

        ws_name, project = key
        ws_info = workspaces[ws_name]
        ws_tag = ws_info.tag
        discovered = workspace_discovered_members[ws_name]

        if project not in discovered:
            fail("Project '{}' not found in workspace '{}'".format(project, ws_name))

        member = discovered[project]

        _process_member(
            lock_owners,
            lock_repos,
            lock_model_structs,
            root_direct_deps,
            ws_tag,
            ws_name,
            member,
            model_type,
            overrides,
            None,
        )

def _lock_import_impl(module_ctx):
    lock_owners = {}
    lock_repos = {}
    root_direct_deps = []
    lock_model_structs = {}
    resolved_lock_files = {}

    for name, tag_prefixes, discover_fn in [
        ("uv", ["import_uv", "import_uv_workspace"], _discover_uv_all_members),
        ("pdm", ["import_pdm", "import_pdm_workspace"], _discover_pdm_all_members),
        ("poetry", ["import_poetry"], _discover_poetry_all_members),
        ("pylock", ["import_pylock"], _discover_pylock_all_members),
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
                    _validate_transition_attrs(tag, name + "_all_members")
                    all_members_tags.append(struct(tag = tag, module = module))

            for tag in getattr(module.tags, name + "_member"):
                _validate_transition_attrs(tag, name + "_member")
                member_tags.append(struct(tag = tag, module = module))

            # 2. Process legacy/standalone import tags (desugar)
            for tag in getattr(module.tags, import_tag_name):
                _validate_transition_attrs(tag, import_tag_name)

                # Synthesis workspace
                workspace_tags.append(struct(tag = tag, module = module, ws_name = tag.repo))

                # Synthesis member
                member_tag = struct(
                    workspace = tag.repo,
                    project = "",
                    repo = tag.repo,
                    project_file = getattr(tag, "project_file", None),
                    default_group = getattr(tag, "default_group", True),
                    optional_groups = getattr(tag, "optional_groups", []),
                    all_optional_groups = getattr(tag, "all_optional_groups", False),
                    development_groups = getattr(tag, "development_groups", []),
                    all_development_groups = getattr(tag, "all_development_groups", False),
                    flags = getattr(tag, "flags", []),
                    constraint_values = getattr(tag, "constraint_values", []),
                    platform = getattr(tag, "platform", None),
                )
                member_tags.append(struct(tag = member_tag, module = module))

        _process_workspaces(
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

            normalized = _normalize_package_tag(tag)
            if tag.repo:
                _check_proper_package_repo(lock_owners, module, tag)
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
                # We intentionally don't enforce `_check_proper_package_repo` for workspaces.
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
    workspace_build_repos = {}
    repo_flags = {}
    repo_constraint_values = {}
    repo_platforms = {}

    for repo_name, repo_info in lock_repos.items():
        resolved_lock_repo_file = _generate_resolved_lock_repo(repo_info, lock_model_structs[repo_name], workspace_packages)
        resolved_lock_files[repo_info.repo_name] = resolved_lock_repo_file
        workspace_memberships[repo_info.repo_name] = repo_info.workspace
        if repo_info.build_repo:
            workspace_build_repos[repo_info.workspace] = repo_info.build_repo

        if repo_info.flags:
            repo_flags[repo_info.repo_name] = json.encode(repo_info.flags)
        if repo_info.constraint_values:
            repo_constraint_values[repo_info.repo_name] = json.encode(repo_info.constraint_values)
        if repo_info.platform:
            repo_platforms[repo_info.repo_name] = repo_info.platform

    lock_workspace_repo(
        name = "lock_import_repos_hub",
        repo_files = resolved_lock_files,
        workspace_memberships = workspace_memberships,
        workspace_build_repos = workspace_build_repos,
        root_repos = root_direct_deps,
        repo_flags = repo_flags,
        repo_constraint_values = repo_constraint_values,
        repo_platforms = repo_platforms,
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

# Tag classes
_import_pdm_tag = tag_class(
    doc = "Import a PDM lock file.",
    attrs = PDM_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR,
)
_import_poetry_tag = tag_class(
    doc = "Import a Poetry lock file.",
    attrs = POETRY_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR,
)
_import_uv_tag = tag_class(
    doc = "Import a uv lock file.",
    attrs = UV_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR,
)
_import_pylock_tag = tag_class(
    doc = "Import a pylock.toml lock file.",
    attrs = PYLOCK_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | REPO_ATTR,
)
_import_pdm_workspace_tag = tag_class(
    doc = "Import a PDM workspace.",
    attrs = PDM_WORKSPACE_ATTRS | WORKSPACE_COMMON_ATTRS,
)
_pdm_all_members_tag = tag_class(
    doc = "Auto-discover and import all members from a pdm.lock file.",
    attrs = PDM_ALL_MEMBERS_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_pdm_member_tag = tag_class(
    doc = "Override settings for a specific PDM member.",
    attrs = PDM_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_import_uv_workspace_tag = tag_class(
    doc = "Import a uv workspace. Define members with uv_all_members and uv_member tags.",
    attrs = UV_WORKSPACE_ATTRS | WORKSPACE_COMMON_ATTRS,
)
_poetry_member_tag = tag_class(
    doc = "Override settings for a specific Poetry member.",
    attrs = POETRY_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_pylock_member_tag = tag_class(
    doc = "Override settings for a specific Pylock member.",
    attrs = PYLOCK_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_uv_all_members_tag = tag_class(
    doc = "Auto-discover and import all members from a uv.lock file.",
    attrs = UV_ALL_MEMBERS_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_uv_member_tag = tag_class(
    doc = "Override settings for a specific member.",
    attrs = UV_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_package_tag = tag_class(
    doc = "Specify package-specific settings.",
    attrs = PACKAGE_ATTRS | OVERRIDE_TARGET_ATTRS,
)

lock_import = module_extension(
    implementation = _lock_import_impl,
    tag_classes = dict(
        import_pdm = _import_pdm_tag,
        import_poetry = _import_poetry_tag,
        import_uv = _import_uv_tag,
        import_pylock = _import_pylock_tag,
        import_pdm_workspace = _import_pdm_workspace_tag,
        pdm_all_members = _pdm_all_members_tag,
        pdm_member = _pdm_member_tag,
        import_uv_workspace = _import_uv_workspace_tag,
        uv_all_members = _uv_all_members_tag,
        uv_member = _uv_member_tag,
        poetry_member = _poetry_member_tag,
        pylock_member = _pylock_member_tag,
        package = _package_tag,
    ),
)
