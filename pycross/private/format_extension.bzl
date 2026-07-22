"""Shared factory for creating per-format lock module extensions.

Each per-format extension (uv, pdm, poetry, pylock) follows the same pattern:
  1. Collect workspace/repo/package tags
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
    extra_project_files = attr.label_list(
        doc = "Optional list of extra pyproject.toml files to consider.",
    ),
)

# Shared attrs for member override project tags (within workspace).
REPO_ATTRS = dict(
    workspace = attr.string(
        doc = "Name of the workspace this member belongs to.",
        mandatory = True,
    ),
    projects = attr.string_list(
        doc = "A list of project names to include. Use ['*'] to include all discovered projects.",
    ),
    name = attr.string(
        doc = "Override the repo name.",
    ),
    dependency_groups = attr.string_list(
        doc = "A list of target groups to include. E.g. ['default', 'group:foo', '*']. Use 'transitive' to generate aliases for transitively-reachable packages. Defaults to ['default'].",
        default = ["default"],
    ),
    legacy_create_root_aliases = attr.bool(
        doc = "Create //:pkg aliases for bare packages in the generated repo. Useful for migrating from 1.x.",
        default = False,
    ),
)

# Transition attrs for repo tags.
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
    extra_build_tools = attr.string_list(
        doc = "A list of additional package keys to use when building this package from source.",
    ),
    build_tools_repo = attr.string(
        doc = "Optional repo to use for resolving sdist build dependencies for this package.",
    ),
    ignore_dependencies = attr.string_list(
        doc = "A list of package keys to drop from this package's declared dependencies.",
    ),
    extra_dependencies = attr.string_list(
        doc = "A list of package keys to add to this package's runtime dependencies.",
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
    wheel_library_tags = attr.string_list(
        doc = "Optional tags to apply to the generated pycross_wheel_library target.",
    ),
)

def _tag_to_annotation_data(pkg, wildcard_pkg = None):
    """Convert a normalized package tag struct to an annotation data dict.

    Args:
        pkg: A normalized package tag struct.
        wildcard_pkg: Optional wildcard package tag struct for fallback values.

    Returns:
        A dict of annotation fields.
    """
    return json.decode(package_annotation(
        always_build = pkg.always_build if pkg.always_build != None else (wildcard_pkg.always_build if wildcard_pkg else False),
        extra_build_tools = pkg.extra_build_tools or (wildcard_pkg.extra_build_tools if wildcard_pkg else []),
        build_tools_repo = pkg.build_tools_repo or (wildcard_pkg.build_tools_repo if wildcard_pkg else None),
        build_target = str(pkg.build_target) if pkg.build_target else (str(wildcard_pkg.build_target) if wildcard_pkg and wildcard_pkg.build_target else None),
        ignore_dependencies = pkg.ignore_dependencies or (wildcard_pkg.ignore_dependencies if wildcard_pkg else []),
        extra_dependencies = pkg.extra_dependencies or (wildcard_pkg.extra_dependencies if wildcard_pkg else []),
        install_exclude_globs = pkg.install_exclude_globs or (wildcard_pkg.install_exclude_globs if wildcard_pkg else []),
        post_install_patches = pkg.post_install_patches or (wildcard_pkg.post_install_patches if wildcard_pkg else []),
        pre_build_patches = pkg.pre_build_patches or (wildcard_pkg.pre_build_patches if wildcard_pkg else []),
        site_hooks = pkg.site_hooks or (wildcard_pkg.site_hooks if wildcard_pkg else []),
        build_backend = pkg.build_backend or (wildcard_pkg.build_backend if wildcard_pkg else None),
        site_paths = pkg.site_paths or (wildcard_pkg.site_paths if wildcard_pkg else []),
        bin_paths = pkg.bin_paths or (wildcard_pkg.bin_paths if wildcard_pkg else []),
        data_paths = pkg.data_paths or (wildcard_pkg.data_paths if wildcard_pkg else []),
        include_paths = pkg.include_paths or (wildcard_pkg.include_paths if wildcard_pkg else []),
        wheel_library_tags = pkg.wheel_library_tags or (wildcard_pkg.wheel_library_tags if wildcard_pkg else []),
    ))

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

    extra_project_files = [Label(f) for f in getattr(lock_model, "extra_project_files", [])]
    lock_file = Label(lock_model.lock_file)

    # Use a unique output file per repo to avoid conflicts.
    output = "raw_lock_{}.json".format(lock_info.repo_name)

    repo_create_model_fn(module_ctx, extra_project_files, lock_file, lock_model, output)

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
    if wildcard_pkg:
        annotations_data["*"] = _tag_to_annotation_data(wildcard_pkg)
    for package_name, package in all_packages.items():
        annotations_data[package_name] = _tag_to_annotation_data(package, wildcard_pkg)

    local_wheels = {}
    for w in lock_info.local_wheels:
        local_wheels[module_ctx.path(w).basename] = str(w)

    resolved_lock = resolve(
        lock_model_data = raw_lock_data,
        local_wheels = local_wheels,
        remote_wheels = {},
        always_include_sdist = False,
        annotations_data = annotations_data,
        default_extra_build_tools_args = wildcard_pkg.extra_build_tools if wildcard_pkg else [],
        include_transitive = getattr(lock_model, "include_transitive", False),
        transitive_testonly = getattr(lock_model, "transitive_testonly", False),
    )

    return {
        "packages": resolved_lock.packages,
        "pins": resolved_lock.pins,
        "remote_files": resolved_lock.remote_files,
        "cycle_groups": resolved_lock.cycle_groups,
        "variants": resolved_lock.variants,
        "resolution_marker_exprs": resolved_lock.resolution_marker_exprs,
        "legacy_create_root_aliases": getattr(lock_model, "legacy_create_root_aliases", False),
        "testonly_pins": resolved_lock.testonly_pins,
    }

def make_format_extension(
        model_type,
        workspace_attrs = None,
        repo_attrs = None,
        discover_members_fn = None,
        repo_create_model_fn = None):
    """Create a module_extension for a specific lock format.

    Args:
        model_type: The lock model type string (e.g. "uv", "pdm", "poetry", "pylock").
        workspace_attrs: Format-specific attrs for workspace tags.
            Merged with WORKSPACE_COMMON_ATTRS.
        repo_attrs: Format-specific attrs for member project override tags, or None.
            Merged with REPO_ATTRS and TRANSITION_ATTRS.
        discover_members_fn: Function(mctx, lock_file_label) -> [struct(name, path)].
            Required when workspace_attrs is not None.
        repo_create_model_fn: Function(rctx, extra_project_files, lock_file, lock_model, output).
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

            # 2. Process repo tags (member overrides).
            for tag in module.tags.repo:
                validate_transition_attrs(tag, "repo")
                member_tag = struct(
                    workspace = tag.workspace,
                    projects = getattr(tag, "projects", []),
                    repo = getattr(tag, "name", ""),
                    dependency_groups = getattr(tag, "dependency_groups", ["default"]),
                    legacy_create_root_aliases = getattr(tag, "legacy_create_root_aliases", False),
                    flags = getattr(tag, "flags", []),
                    constraint_values = getattr(tag, "constraint_values", []),
                    platform = getattr(tag, "platform", None),
                )
                member_tags.append(struct(tag = member_tag, module = module))

        process_workspaces(
            module_ctx,
            lock_owners,
            lock_repos,
            lock_model_structs,
            workspace_tags,
            member_tags,
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

    # Build the repo tag_class by merging format-specific, shared, and transition attrs.
    repo_tag_attrs = {}
    if repo_attrs != None:
        repo_tag_attrs.update(repo_attrs)
    repo_tag_attrs.update(REPO_ATTRS)
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

    return module_extension(
        implementation = _impl,
        tag_classes = tag_classes,
    )
