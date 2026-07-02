"""The unified lock extension.

This is the preferred way to import and use Python lock files with rules_pycross.
It replaces the separate lock_import + lock_repos two-extension pattern.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load(":json_file_repo.bzl", "json_file_repo")
load(
    ":lock_common.bzl",
    "CREATE_TAG_CLASS",
    "IMPORT_TAG_CLASSES",
    "package_annotation",
    "process_import_tags",
)
load(":lock_repo_creation.bzl", "create_repos")
load(":lock_resolver.bzl", "resolve")
load(":pdm_lock_model.bzl", "repo_create_pdm_model")
load(":poetry_lock_model.bzl", "repo_create_poetry_model")
load(":pylock_lock_model.bzl", "repo_create_pylock_model")
load(":uv_lock_model.bzl", "repo_create_uv_model")

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _resolve_lock_inline(module_ctx, lock_info, serialized_lock_model, workspace_packages):
    """Run translator + resolver inline within module_ctx.

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

    if lock_model.model_type == "pdm":
        repo_create_pdm_model(module_ctx, project_file, lock_file, lock_model, output)
    elif lock_model.model_type == "poetry":
        repo_create_poetry_model(module_ctx, project_file, lock_file, lock_model, output)
    elif lock_model.model_type == "uv":
        repo_create_uv_model(module_ctx, project_file, lock_file, lock_model, output)
    elif lock_model.model_type == "pylock":
        repo_create_pylock_model(module_ctx, project_file, lock_file, lock_model, output)
    else:
        fail("Invalid model type: " + lock_model.model_type)

    # Read the raw lock and resolve.
    raw_lock_data = json.decode(module_ctx.read(module_ctx.path(output)))

    # Compute annotations from package tags.
    all_packages = {}
    for package_name, package in workspace_packages.get(lock_info.workspace, {}).items():
        all_packages[package_name] = package
    for package_name, package in lock_info.packages.items():
        all_packages[package_name] = package

    annotations_data = {}
    for package_name, package in all_packages.items():
        annotations_data[package_name] = json.decode(package_annotation(
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
        default_build_dependencies_args = lock_info.default_build_dependencies,
        default_alias_single_version = lock_info.default_alias_single_version,
    )

    return {
        "packages": resolved_lock.packages,
        "pins": resolved_lock.pins,
        "remote_files": resolved_lock.remote_files,
        "cycle_groups": resolved_lock.cycle_groups,
        "variants": resolved_lock.variants,
    }

def _lock_impl(module_ctx):
    # Process all import tags to get lock repo configurations.
    result = process_import_tags(module_ctx)

    if not result.lock_repos:
        if bazel_features.external_deps.extension_metadata_has_reproducible:
            return module_ctx.extension_metadata(reproducible = True)
        return module_ctx.extension_metadata()

    # Run translators + resolver inline for each lock repo.
    resolved_locks = {}
    all_locks = {}
    for repo_name, repo_info in result.lock_repos.items():
        resolved_data = _resolve_lock_inline(
            module_ctx,
            repo_info,
            result.lock_model_structs[repo_name],
            result.workspace_packages,
        )
        resolved_locks[repo_info.repo_name] = resolved_data

        # Write the resolved lock JSON to a repo so downstream repo rules
        # (package_repo, thin_package_repo, sdist_repo) can reference it.
        lock_repo_name = "{}_lock_json".format(repo_info.repo_name)
        json_file_repo(
            name = lock_repo_name,
            content = json.encode(resolved_data),
        )

        # Pass as STRING (not Label). When the extension passes strings to
        # repo rule attr.label, Bazel resolves them in the extension's context
        # where sibling repos are visible.
        all_locks[repo_info.repo_name] = "@{}//:data.json".format(lock_repo_name)

    # Process the 'create' tag.
    create_tag = None
    for module in module_ctx.modules:
        for tag in module.tags.create:
            if module.name != "rules_pycross" and not module.is_root:
                _print_warn("Ignoring lock.create tag from non-root, non-pycross module {}".format(module.name))
                continue
            if create_tag == None:
                create_tag = tag

    if create_tag == None:
        fail("BUG: no repos.create tag found!")

    workspace_pypi_indexes = {}
    if create_tag.pypi_index:
        for ws in result.workspace_memberships.values():
            workspace_pypi_indexes[ws] = [create_tag.pypi_index]

    # Create all the actual repos.
    create_repos(
        module_ctx = module_ctx,
        all_locks = all_locks,
        workspace_memberships = result.workspace_memberships,
        workspace_build_repos = result.workspace_build_repos,
        repo_flags = result.repo_flags,
        repo_constraint_values = result.repo_constraint_values,
        repo_platforms = result.repo_platforms,
        repo_disallow_builds = result.repo_disallow_builds,
        workspace_pypi_indexes = workspace_pypi_indexes,
        resolved_locks = resolved_locks,
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(
            root_module_direct_deps = result.root_direct_deps,
            root_module_direct_dev_deps = [],
            reproducible = True,
        )
    return module_ctx.extension_metadata(
        root_module_direct_deps = result.root_direct_deps,
        root_module_direct_dev_deps = [],
    )

# Unified tag classes: all import tags + create tag.
_ALL_TAG_CLASSES = dict(IMPORT_TAG_CLASSES)
_ALL_TAG_CLASSES["create"] = CREATE_TAG_CLASS

lock = module_extension(
    implementation = _lock_impl,
    tag_classes = _ALL_TAG_CLASSES,
)
