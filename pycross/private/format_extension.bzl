"""Shared factory for creating per-format lock module extensions.

Each per-format extension (uv, pdm, poetry, pylock) follows the same pattern:
  1. Collect project/workspace/all_projects/package tags
  2. Desugar standalone projects into workspace + member
  3. Process workspaces (discover members, register repos)
  4. Run translators + resolver inline
  5. Call create_repos()

This factory eliminates the boilerplate, similar to make_override_extension()
for backend extensions.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load(":json_file_repo.bzl", "json_file_repo")
load(
    ":lock_common.bzl",
    "normalize_package_tag",
    "package_annotation",
    "process_workspaces",
    "validate_transition_attrs",
)
load(":lock_repo_creation.bzl", "create_repos")
load(":lock_resolver.bzl", "resolve")

# Shared attrs for workspace tags.
WORKSPACE_COMMON_ATTRS = dict(
    name = attr.string(
        doc = "Workspace name. Used to link members to this workspace.",
        mandatory = True,
    ),
    lock_file = attr.label(
        doc = "The shared lock file for the workspace.",
        allow_single_file = True,
        mandatory = True,
    ),
    local_wheels = attr.label_list(
        doc = "A list of local .whl files to consider when processing lock files.",
    ),
    disallow_builds = attr.bool(
        doc = "If True, only pre-built wheels are allowed.",
    ),
    pypi_indexes = attr.string_list(
        doc = "List of PyPI-compatible indexes to use for downloading packages.",
    ),
)

# Shared attrs for all_projects tags.
ALL_PROJECTS_COMMON_ATTRS = dict(
    workspace = attr.string(
        doc = "Name of the workspace to auto-discover members from.",
        mandatory = True,
    ),
    repo_pattern = attr.string(
        doc = "Pattern for auto-generated repo names. Use '{member}' as a placeholder " +
              "for the normalized project name.",
        default = "{member}",
    ),
    excluded_projects = attr.string_list(
        doc = "Project names to skip during auto-discovery.",
    ),
    alias_transitive = attr.bool(
        doc = "Generate aliases for transitive single-version packages in generated repos.",
    ),
)

# Shared attrs for member override project tags (within workspace).
REPO_ATTRS = dict(
    workspace = attr.string(
        doc = "Name of the workspace this member belongs to.",
        mandatory = True,
    ),
    project = attr.string(
        doc = "The project name as it appears in the lock file. Optional if the workspace has only one member.",
    ),
    name = attr.string(
        doc = "Override the repo name.",
    ),
    project_file = attr.label(
        doc = "Override auto-discovered pyproject.toml path.",
        allow_single_file = True,
    ),
    alias_transitive = attr.bool(
        doc = "Generate aliases for transitive single-version packages in this repo.",
    ),
)

# Transition attrs for project and all_projects tags.
TRANSITION_ATTRS = dict(
    constraint_values = attr.label_list(
        doc = "A list of constraint values to apply to the generated platform.",
    ),
    flags = attr.string_list(
        doc = "A list of flags to apply to the generated platform (e.g., '--@flag=value').",
    ),
    platform = attr.label(
        doc = "An existing platform target to use directly.",
    ),
)

# Group-selection attrs for all_projects tags (group-wide defaults).
GROUP_ATTRS = dict(
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install.",
    ),
    all_optional_groups = attr.bool(
        doc = "Install all optional dependencies.",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install.",
    ),
    all_development_groups = attr.bool(
        doc = "Install all dev dependencies.",
    ),
)

# Group-selection attrs for member override project tags.
GROUP_OVERRIDE_ATTRS = dict(
    default_group = attr.bool(
        doc = "Whether to install dependencies from the default group.",
        default = True,
    ),
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install (overrides all_projects setting).",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install (overrides all_projects setting).",
    ),
)

# Attrs for the package tag.
PACKAGE_ATTRS = dict(
    name = attr.string(
        doc = "The package key (name or name@version). Can be '*' to apply to all packages in the workspace.",
        mandatory = True,
    ),
    workspace = attr.string(
        doc = "The workspace name (optional if inferable).",
    ),
    build_backend = attr.string(
        doc = "An explicit build backend rule name to use for this package.",
    ),
    build_target = attr.label(
        doc = "An optional override build target to use when building from source.",
    ),
    always_build = attr.bool(
        doc = "If True, don't use pre-built wheels for this package.",
    ),
    build_dependencies = attr.string_list(
        doc = "A list of additional package keys to use when building this package from source.",
    ),
    build_repo = attr.string(
        doc = "Optional repo to use for resolving sdist build dependencies for this package.",
    ),
    ignore_dependencies = attr.string_list(
        doc = "A list of package keys to drop from this package's declared dependencies.",
    ),
    install_exclude_globs = attr.string_list(
        doc = "A list of globs for files to exclude during installation.",
    ),
    post_install_patches = attr.label_list(
        doc = "A list of patches to apply after wheel installation.",
        allow_files = True,
    ),
    pre_build_patches = attr.label_list(
        doc = "A list of patches to apply to the sdist source tree before building.",
        allow_files = True,
    ),
    site_hooks = attr.string_list(
        doc = "A list of Python code snippets to execute on interpreter startup during builds.",
    ),
    site_paths = attr.string_list(
        doc = "Override the auto-detected top-level importable paths.",
    ),
    bin_paths = attr.string_list(
        doc = "Override the auto-detected bin paths.",
    ),
    data_paths = attr.string_list(
        doc = "Override the auto-detected data paths.",
    ),
    include_paths = attr.string_list(
        doc = "Override the auto-detected include paths.",
    ),
)

def _resolve_lock_inline(module_ctx, lock_info, serialized_lock_model, workspace_packages, repo_create_model_fn):
    """Run translator + resolver inline within module_ctx.

    Args:
        module_ctx: The module_ctx object.
        lock_info: The lock repo info struct.
        serialized_lock_model: JSON-encoded lock model.
        workspace_packages: Dict of workspace_name -> {pkg_name -> normalized_tag}.
        repo_create_model_fn: The format-specific translator function.

    Returns:
        A dict containing the resolved lock data (packages, pins, remote_files, etc.).
    """
    lock_model = json.decode(serialized_lock_model)
    if type(lock_model) == "dict":
        lock_model = struct(**lock_model)

    project_file = Label(lock_model.project_file) if getattr(lock_model, "project_file", "") else None
    lock_file = Label(lock_model.lock_file)

    # Use a unique output file per repo to avoid conflicts.
    output = "raw_lock_{}.json".format(lock_info.repo_name)

    repo_create_model_fn(module_ctx, project_file, lock_file, lock_model, output)

    # Read the raw lock and resolve.
    raw_lock_data = json.decode(module_ctx.read(module_ctx.path(output)))

    # Compute annotations from package tags.
    all_packages = {}
    for package_name, package in workspace_packages.get(lock_info.workspace, {}).items():
        all_packages[package_name] = package
    for package_name, package in lock_info.packages.items():
        all_packages[package_name] = package

    wildcard_pkg = all_packages.pop("*", None)

    annotations_data = {}
    for package_name, package in all_packages.items():
        annotations_data[package_name] = json.decode(package_annotation(
            always_build = package.always_build if package.always_build != None else (wildcard_pkg.always_build if wildcard_pkg else False),
            build_dependencies = package.build_dependencies or (wildcard_pkg.build_dependencies if wildcard_pkg else []),
            build_repo = package.build_repo or (wildcard_pkg.build_repo if wildcard_pkg else None),
            build_target = str(package.build_target) if package.build_target else (str(wildcard_pkg.build_target) if wildcard_pkg and wildcard_pkg.build_target else None),
            ignore_dependencies = package.ignore_dependencies or (wildcard_pkg.ignore_dependencies if wildcard_pkg else []),
            install_exclude_globs = package.install_exclude_globs or (wildcard_pkg.install_exclude_globs if wildcard_pkg else []),
            post_install_patches = package.post_install_patches or (wildcard_pkg.post_install_patches if wildcard_pkg else []),
            pre_build_patches = package.pre_build_patches or (wildcard_pkg.pre_build_patches if wildcard_pkg else []),
            site_hooks = package.site_hooks or (wildcard_pkg.site_hooks if wildcard_pkg else []),
            build_backend = package.build_backend or (wildcard_pkg.build_backend if wildcard_pkg else None),
            site_paths = package.site_paths or (wildcard_pkg.site_paths if wildcard_pkg else []),
            bin_paths = package.bin_paths or (wildcard_pkg.bin_paths if wildcard_pkg else []),
            data_paths = package.data_paths or (wildcard_pkg.data_paths if wildcard_pkg else []),
            include_paths = package.include_paths or (wildcard_pkg.include_paths if wildcard_pkg else []),
        ))

    local_wheels = {}
    for w in lock_info.local_wheels:
        local_wheels[module_ctx.path(w).basename] = str(w)

    resolved_lock = resolve(
        lock_model_data = raw_lock_data,
        local_wheels = local_wheels,
        remote_wheels = {},
        always_include_sdist = False,
        annotations_data = annotations_data,
        default_build_dependencies_args = wildcard_pkg.build_dependencies if wildcard_pkg else [],
        alias_transitive = lock_info.alias_transitive,
    )

    return {
        "packages": resolved_lock.packages,
        "pins": resolved_lock.pins,
        "remote_files": resolved_lock.remote_files,
        "cycle_groups": resolved_lock.cycle_groups,
        "variants": resolved_lock.variants,
    }

def make_format_extension(
        model_type,
        workspace_attrs = None,
        all_projects_attrs = None,
        repo_attrs = None,
        discover_members_fn = None,
        repo_create_model_fn = None):
    """Create a module_extension for a specific lock format.

    Args:
        model_type: The lock model type string (e.g. "uv", "pdm", "poetry", "pylock").
        workspace_attrs: Format-specific attrs for workspace tags.
            Merged with WORKSPACE_COMMON_ATTRS.
        all_projects_attrs: Format-specific attrs for all_projects tags, or None.
            Merged with ALL_PROJECTS_COMMON_ATTRS and TRANSITION_ATTRS.
        repo_attrs: Format-specific attrs for member project override tags, or None.
            Merged with REPO_ATTRS, GROUP_OVERRIDE_ATTRS, and TRANSITION_ATTRS.
        discover_members_fn: Function(mctx, lock_file_label) -> [struct(name, path)].
            Required when workspace_attrs is not None.
        repo_create_model_fn: Function(module_ctx, project_file, lock_file, lock_model, output).
            Runs the format-specific translator to produce raw lock JSON.

    Returns:
        A module_extension value.
    """

    def _impl(module_ctx):
        lock_owners = {}
        lock_repos = {}
        root_direct_deps = []
        lock_model_structs = {}

        # Collect tags per module.
        workspace_tags = []
        member_tags = []
        all_members_tags = []

        # Track per-workspace pypi_indexes (from workspace or standalone project tags).
        workspace_pypi_indexes = {}

        for module in module_ctx.modules:
            # 1. Process workspace tags.
            if workspace_attrs != None:
                for tag in module.tags.workspace:
                    ws_name = tag.name
                    workspace_tags.append(struct(tag = tag, module = module, ws_name = ws_name))
                    if tag.pypi_indexes:
                        workspace_pypi_indexes[ws_name] = tag.pypi_indexes

            # 2. Process all_projects tags (if supported).
            if all_projects_attrs != None:
                for tag in module.tags.all_projects:
                    validate_transition_attrs(tag, "all_projects")
                    all_members_tags.append(struct(tag = tag, module = module))

            # 3. Process project tags (member overrides).
            for tag in module.tags.repo:
                validate_transition_attrs(tag, "repo")
                member_tag = struct(
                    workspace = tag.workspace,
                    project = getattr(tag, "project", ""),
                    repo = getattr(tag, "name", ""),
                    project_file = getattr(tag, "project_file", None),
                    default_group = getattr(tag, "default_group", True),
                    optional_groups = getattr(tag, "optional_groups", []),
                    development_groups = getattr(tag, "development_groups", []),
                    flags = getattr(tag, "flags", []),
                    constraint_values = getattr(tag, "constraint_values", []),
                    platform = getattr(tag, "platform", None),
                    alias_transitive = getattr(tag, "alias_transitive", False),
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
            discover_members_fn,
            model_type,
            root_direct_deps,
        )

        # Track which workspaces each module declares for validation
        module_workspaces = {}
        valid_workspaces = {r.workspace: True for r in lock_repos.values()}

        for module in module_ctx.modules:
            module_workspaces[module.name] = []
            if workspace_attrs != None:
                for tag in module.tags.workspace:
                    module_workspaces[module.name].append(tag.name)

        # Process package annotations.
        workspace_packages = {}

        for module in module_ctx.modules:
            workspaces_in_module = module_workspaces[module.name]

            for tag in module.tags.package:
                ws_name = tag.workspace
                if not ws_name:
                    if len(workspaces_in_module) == 1:
                        ws_name = workspaces_in_module[0]
                    else:
                        fail("package '{}' must specify workspace (module defines workspaces: {})".format(
                            tag.name,
                            ", ".join(workspaces_in_module) if workspaces_in_module else "none",
                        ))

                if ws_name not in workspaces_in_module:
                    fail("package '{}': workspace '{}' not declared by this module".format(tag.name, ws_name))

                if ws_name not in valid_workspaces:
                    fail("Package override specifies workspace '{}' which does not exist".format(ws_name))

                normalized = normalize_package_tag(tag)
                ws_pkgs = workspace_packages.setdefault(ws_name, {})
                if tag.name in ws_pkgs:
                    fail("Multiple package entries for package '{}' in workspace '{}'".format(tag.name, ws_name))
                ws_pkgs[tag.name] = normalized

        if not lock_repos:
            if bazel_features.external_deps.extension_metadata_has_reproducible:
                return module_ctx.extension_metadata(reproducible = True)
            return module_ctx.extension_metadata()

        # Run translators + resolver inline for each lock repo.
        resolved_locks = {}
        all_locks = {}
        repo_pypi_indexes = {}  # repo_name -> pypi_indexes list

        for repo_name, repo_info in lock_repos.items():
            # Determine pypi_indexes for this repo from its workspace.
            pypi_indexes = workspace_pypi_indexes.get(repo_info.workspace, [])
            if pypi_indexes:
                repo_pypi_indexes[repo_name] = pypi_indexes

            resolved_data = _resolve_lock_inline(
                module_ctx,
                repo_info,
                lock_model_structs[repo_name],
                workspace_packages,
                repo_create_model_fn,
            )
            resolved_locks[repo_info.repo_name] = resolved_data

            # Write the resolved lock JSON to a repo.
            lock_repo_name = "{}_lock_json".format(repo_info.repo_name)
            json_file_repo(
                name = lock_repo_name,
                content = json.encode(resolved_data),
            )
            all_locks[repo_info.repo_name] = "@{}//:data.json".format(lock_repo_name)

        # Compute workspace metadata.
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

        create_repos(
            module_ctx = module_ctx,
            all_locks = all_locks,
            workspace_memberships = workspace_memberships,
            repo_flags = repo_flags,
            repo_constraint_values = repo_constraint_values,
            repo_platforms = repo_platforms,
            repo_disallow_builds = repo_disallow_builds,
            workspace_pypi_indexes = workspace_pypi_indexes,
            resolved_locks = resolved_locks,
        )

        if bazel_features.external_deps.extension_metadata_has_reproducible:
            return module_ctx.extension_metadata(
                root_module_direct_deps = root_direct_deps,
                root_module_direct_dev_deps = [],
                reproducible = True,
            )
        return module_ctx.extension_metadata(
            root_module_direct_deps = root_direct_deps,
            root_module_direct_dev_deps = [],
        )

    # Build tag classes.
    #
    # The "repo" tag is dual-purpose:
    # - When lock_file is provided: standalone project (uses STANDALONE_PROJECT_ATTRS)
    # - When workspace is provided: member override (uses REPO_ATTRS)
    #
    # We merge all attrs into a single tag_class since Bazel tag_class doesn't
    # support conditional attrs. The _impl validates mutual exclusivity.
    repo_tag_attrs = {}
    if repo_attrs != None:
        repo_tag_attrs.update(repo_attrs)
    repo_tag_attrs.update(REPO_ATTRS)
    repo_tag_attrs.update(GROUP_OVERRIDE_ATTRS)
    repo_tag_attrs.update(TRANSITION_ATTRS)

    tag_classes = {
        "repo": tag_class(
            doc = "Override a %s workspace member's settings." % model_type,
            attrs = repo_tag_attrs,
        ),
        "package": tag_class(
            doc = "Specify package-specific settings.",
            attrs = PACKAGE_ATTRS,
        ),
    }

    if workspace_attrs != None:
        ws_attrs = dict(workspace_attrs)
        ws_attrs.update(WORKSPACE_COMMON_ATTRS)
        tag_classes["workspace"] = tag_class(
            doc = "Declare a %s workspace from a shared lock file." % model_type,
            attrs = ws_attrs,
        )

    if all_projects_attrs != None:
        ap_attrs = dict(all_projects_attrs)
        ap_attrs.update(ALL_PROJECTS_COMMON_ATTRS)
        ap_attrs.update(GROUP_ATTRS)
        ap_attrs.update(TRANSITION_ATTRS)
        tag_classes["all_projects"] = tag_class(
            doc = "Auto-discover and import all members of a %s workspace." % model_type,
            attrs = ap_attrs,
        )

    return module_extension(
        implementation = _impl,
        tag_classes = tag_classes,
    )
