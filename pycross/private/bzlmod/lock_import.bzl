"""The lock_import extension."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@toml.bzl//toml:toml.bzl", "decode")
load("//pycross/private:lock_attrs.bzl", "package_annotation")
load("//pycross/private:pdm_lock_model.bzl", "lock_repo_model_pdm")
load("//pycross/private:poetry_lock_model.bzl", "lock_repo_model_poetry")
load("//pycross/private:pylock_lock_model.bzl", "lock_repo_model_pylock")
load("//pycross/private:resolved_lock_repo.bzl", "resolved_lock_repo")
load("//pycross/private:util.bzl", "sanitize_name")
load("//pycross/private:uv_lock_model.bzl", "lock_repo_model_uv")
load(":lock_workspace_repo.bzl", "lock_workspace_repo")
load(
    ":tag_attrs.bzl",
    "COMMON_ATTRS",
    "COMMON_IMPORT_ATTRS",
    "PACKAGE_ATTRS",
    "PDM_IMPORT_ATTRS",
    "POETRY_IMPORT_ATTRS",
    "PYLOCK_IMPORT_ATTRS",
    "UV_IMPORT_ATTRS",
    "UV_WORKSPACE_ATTRS",
    "UV_WORKSPACE_MEMBERS_ATTRS",
    "UV_WORKSPACE_MEMBER_ATTRS",
    "WORKSPACE_COMMON_ATTRS",
    "WORKSPACE_MEMBER_COMMON_ATTRS",
)

def _generate_resolved_lock_repo(lock_info, serialized_lock_model):
    repo_name = lock_info.repo_name
    args = {
        "name": repo_name,
        "lock_model": serialized_lock_model,
        "target_environments": lock_info.environments,
        "default_alias_single_version": lock_info.default_alias_single_version,
        "default_build_dependencies": lock_info.default_build_dependencies,
        "disallow_builds": lock_info.disallow_builds,
        "local_wheels": lock_info.local_wheels,
        "squash_extras": lock_info.squash_extras,
        "annotations": {},
    }

    for package_name, package in lock_info.packages.items():
        args["annotations"][package_name] = package_annotation(
            always_build = package.always_build,
            build_dependencies = package.build_dependencies,
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

def _check_unique_lock_repo(owners, module, tag):
    if tag.repo in owners:
        fail("lock repo '{}' wanted by module '{}' already created by module '{}'".format(
            tag.repo,
            module.name,
            owners[tag.repo],
        ))
    owners[tag.repo] = module.name

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

def _check_package_entry_not_set(owners, lock_info, tag):
    if tag.name in lock_info.packages:
        fail("Multiple package entries for package '{}' in lock repo '{}' owned by module '{}'".format(tag.name, tag.repo, owners[tag.repo]))

def _lock_struct(mctx, tag):
    environment_files = []
    for env_file in tag.target_environments:
        data = json.decode(mctx.read(env_file))
        if "environments" in data:
            # This is an environment index file. Add its entries to our result.
            environment_files.extend([env_file.relative(entry) for entry in data["environments"]])
        else:
            environment_files.append(env_file)
        environment_files = sorted(environment_files)

    # Pre-pathify environment files after we've expanded indexes
    for env_file in environment_files:
        mctx.path(env_file)

    return struct(
        repo_name = tag.repo,
        workspace = tag.repo,
        default_alias_single_version = tag.default_alias_single_version,
        environments = environment_files,
        local_wheels = tag.local_wheels,
        disallow_builds = tag.disallow_builds,
        default_build_dependencies = tag.default_build_dependencies,
        squash_extras = tag.squash_extras,
        packages = {},
    )

def _workspace_lock_struct(mctx, ws_tag, repo_name, workspace_name):
    """Create a lock struct for a workspace member, inheriting workspace-level settings."""
    environment_files = []
    for env_file in ws_tag.target_environments:
        data = json.decode(mctx.read(env_file))
        if "environments" in data:
            environment_files.extend([env_file.relative(entry) for entry in data["environments"]])
        else:
            environment_files.append(env_file)
        environment_files = sorted(environment_files)

    for env_file in environment_files:
        mctx.path(env_file)

    return struct(
        repo_name = repo_name,
        workspace = workspace_name,
        default_alias_single_version = ws_tag.default_alias_single_version,
        environments = environment_files,
        local_wheels = ws_tag.local_wheels,
        disallow_builds = ws_tag.disallow_builds,
        default_build_dependencies = ws_tag.default_build_dependencies,
        squash_extras = ws_tag.squash_extras,
        packages = {},
    )

def _normalize_package_tag(tag):
    """Normalize a generic package tag into a struct."""
    return struct(
        always_build = tag.always_build,
        build_dependencies = tag.build_dependencies,
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

def _discover_workspace_members(mctx, lock_file_label):
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

        # Skip virtual entries (workspace roots with package = false)
    return members

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

    # Build the package path relative to the lock file's package
    lock_package = lock_file_label.package
    if lock_package:
        member_package = lock_package + "/" + clean_path
    else:
        member_package = clean_path

    return lock_file_label.relative("//{}:pyproject.toml".format(member_package))

def _get_member_group_attrs(members_tag, override_tag):
    """Merge group attrs from a uv_workspace_members default and optional uv_workspace_member override.

    The override tag wins for any attr it explicitly sets.
    """
    return dict(
        default = override_tag.default if override_tag else members_tag.default,
        optional_groups = override_tag.optional_groups if (override_tag and override_tag.optional_groups) else members_tag.optional_groups if hasattr(members_tag, "optional_groups") else [],
        all_optional_groups = override_tag.all_optional_groups if override_tag else members_tag.all_optional_groups if hasattr(members_tag, "all_optional_groups") else False,
        development_groups = override_tag.development_groups if (override_tag and override_tag.development_groups) else members_tag.development_groups if hasattr(members_tag, "development_groups") else [],
        all_development_groups = override_tag.all_development_groups if override_tag else members_tag.all_development_groups if hasattr(members_tag, "all_development_groups") else False,
    )

def _lock_import_impl(module_ctx):
    lock_owners = {}
    lock_repos = {}
    lock_model_structs = {}
    resolved_lock_files = {}

    # A first pass initialize lock structures and make sure none of the repo names are duplicated.
    for module in module_ctx.modules:
        for tag in module.tags.import_pdm + module.tags.import_poetry + module.tags.import_uv + module.tags.import_pylock:
            _check_unique_lock_repo(lock_owners, module, tag)
            lock_repos[tag.repo] = _lock_struct(module_ctx, tag)

    # Iterate over the various from_pdm and from_poetry tags and create lock models
    for module in module_ctx.modules:
        for tag in module.tags.import_pdm:
            lock_model_structs[tag.repo] = lock_repo_model_pdm(**{attr: getattr(tag, attr) for attr in PDM_IMPORT_ATTRS})
        for tag in module.tags.import_poetry:
            lock_model_structs[tag.repo] = lock_repo_model_poetry(**{attr: getattr(tag, attr) for attr in POETRY_IMPORT_ATTRS})
        for tag in module.tags.import_uv:
            lock_model_structs[tag.repo] = lock_repo_model_uv(**{attr: getattr(tag, attr) for attr in UV_IMPORT_ATTRS})
        for tag in module.tags.import_pylock:
            lock_model_structs[tag.repo] = lock_repo_model_pylock(**{attr: getattr(tag, attr) for attr in PYLOCK_IMPORT_ATTRS})

    # --- UV workspace handling ---

    # Collect workspace definitions
    uv_workspaces = {}
    for module in module_ctx.modules:
        for tag in module.tags.import_uv_workspace:
            if tag.name in uv_workspaces:
                fail("Duplicate uv workspace name: '{}'".format(tag.name))
            uv_workspaces[tag.name] = struct(
                tag = tag,
                module = module,
            )

    # Collect per-member overrides indexed by (workspace, project)
    member_overrides = {}
    for module in module_ctx.modules:
        for tag in module.tags.uv_workspace_member:
            if tag.workspace not in uv_workspaces:
                fail("uv_workspace_member references non-existent workspace: '{}'".format(tag.workspace))
            key = (tag.workspace, tag.project)
            if key in member_overrides:
                fail("Duplicate uv_workspace_member for project '{}' in workspace '{}'".format(tag.project, tag.workspace))
            member_overrides[key] = tag

    # Process bulk member imports
    for module in module_ctx.modules:
        for tag in module.tags.uv_workspace_members:
            if tag.workspace not in uv_workspaces:
                fail("uv_workspace_members references non-existent workspace: '{}'".format(tag.workspace))

            ws_info = uv_workspaces[tag.workspace]
            ws_tag = ws_info.tag

            # Auto-discover members from uv.lock
            discovered = _discover_workspace_members(module_ctx, ws_tag.lock_file)
            excluded = {p: True for p in tag.excluded_projects}

            for member in discovered:
                if member.name in excluded:
                    continue

                override = member_overrides.get((tag.workspace, member.name))

                # Determine repo name
                normalized_name = sanitize_name(member.name)
                if override and override.repo:
                    repo_name = override.repo
                else:
                    repo_name = tag.repo_pattern.format(member = normalized_name)

                # Determine project_file
                if override and override.project_file:
                    project_file = override.project_file
                else:
                    project_file = _resolve_member_project_file(ws_tag.lock_file, member.path)

                # Get group attrs (override wins)
                group_attrs = _get_member_group_attrs(tag, override)

                # Register as a lock repo
                _check_unique_repo_name(lock_owners, module.name, repo_name)
                lock_repos[repo_name] = _workspace_lock_struct(module_ctx, ws_tag, repo_name, tag.workspace)

                lock_model_structs[repo_name] = lock_repo_model_uv(
                    project_file = project_file,
                    lock_file = ws_tag.lock_file,
                    require_static_urls = ws_tag.require_static_urls,
                    **group_attrs
                )

    # --- End UV workspace handling ---

    # Add package attributes
    for module in module_ctx.modules:
        for tag in module.tags.package:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = _normalize_package_tag(tag)

    # Generate the resolved lock repos
    workspace_memberships = {}
    for repo_name, repo_info in lock_repos.items():
        resolved_lock_repo_file = _generate_resolved_lock_repo(repo_info, lock_model_structs[repo_name])
        resolved_lock_files[repo_info.repo_name] = resolved_lock_repo_file
        workspace_memberships[repo_info.repo_name] = repo_info.workspace

    lock_workspace_repo(
        name = "lock_import_repos_hub",
        repo_files = resolved_lock_files,
        workspace_memberships = workspace_memberships,
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

# Tag classes
_import_pdm_tag = tag_class(
    doc = "Import a PDM lock file.",
    attrs = PDM_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | COMMON_ATTRS,
)
_import_poetry_tag = tag_class(
    doc = "Import a Poetry lock file.",
    attrs = POETRY_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | COMMON_ATTRS,
)
_import_uv_tag = tag_class(
    doc = "Import a uv lock file.",
    attrs = UV_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | COMMON_ATTRS,
)
_import_pylock_tag = tag_class(
    doc = "Import a pylock.toml lock file.",
    attrs = PYLOCK_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | COMMON_ATTRS,
)
_import_uv_workspace_tag = tag_class(
    doc = "Import a uv workspace. Define members with uv_workspace_members and uv_workspace_member.",
    attrs = UV_WORKSPACE_ATTRS | WORKSPACE_COMMON_ATTRS,
)
_uv_workspace_members_tag = tag_class(
    doc = "Auto-discover and import all workspace members from a uv.lock file.",
    attrs = UV_WORKSPACE_MEMBERS_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_uv_workspace_member_tag = tag_class(
    doc = "Override settings for a specific workspace member.",
    attrs = UV_WORKSPACE_MEMBER_ATTRS | WORKSPACE_MEMBER_COMMON_ATTRS,
)
_package_tag = tag_class(
    doc = "Specify package-specific settings.",
    attrs = PACKAGE_ATTRS | COMMON_ATTRS,
)

lock_import = module_extension(
    implementation = _lock_import_impl,
    tag_classes = dict(
        import_pdm = _import_pdm_tag,
        import_poetry = _import_poetry_tag,
        import_uv = _import_uv_tag,
        import_pylock = _import_pylock_tag,
        import_uv_workspace = _import_uv_workspace_tag,
        uv_workspace_members = _uv_workspace_members_tag,
        uv_workspace_member = _uv_workspace_member_tag,
        package = _package_tag,
    ),
)
