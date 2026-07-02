"""The lock_import extension (V1 compatibility).

This is the legacy two-extension pattern: lock_import defines lock repos,
lock_repos creates them. For new projects, use the per-format extensions
(uv.bzl, pdm.bzl, poetry.bzl, pylock.bzl) instead.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load("//pycross/private:resolved_lock_repo.bzl", "resolved_lock_repo")
load(
    ":lock_attrs.bzl",
    "COMMON_IMPORT_ATTRS",
    "PACKAGE_ATTRS",
    "PDM_IMPORT_ATTRS",
    "POETRY_IMPORT_ATTRS",
    "PYLOCK_IMPORT_ATTRS",
    "REPO_ATTR",
    "UV_IMPORT_ATTRS",
)
load(
    ":lock_common.bzl",
    "check_proper_package_repo",
    "check_unique_repo_name",
    "normalize_package_tag",
    "package_annotation",
    "validate_transition_attrs",
)
load(":lock_workspace_repo.bzl", "lock_workspace_repo")

def _generate_resolved_lock_repo(lock_info, serialized_lock_model):
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

    for package_name, package in lock_info.packages.items():
        args["annotations"][package_name] = package_annotation(
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

def _lock_struct(tag):
    return struct(
        repo_name = tag.repo,
        default_alias_single_version = tag.default_alias_single_version,
        local_wheels = tag.local_wheels,
        disallow_builds = tag.disallow_builds,
        default_build_dependencies = tag.default_build_dependencies,
        build_repo = tag.build_repo,
        packages = {},
        flags = getattr(tag, "flags", []),
        constraint_values = getattr(tag, "constraint_values", []),
        platform = getattr(tag, "platform", None),
    )

def _lock_import_impl(module_ctx):
    lock_owners = {}
    lock_repos = {}
    root_direct_deps = []
    lock_model_structs = {}
    resolved_lock_files = {}

    # First pass: initialize lock structures and check for duplicate repo names.
    for module in module_ctx.modules:
        for tag_name in ("import_uv", "import_pdm", "import_poetry", "import_pylock"):
            for tag in getattr(module.tags, tag_name):
                validate_transition_attrs(tag, tag_name)
                check_unique_repo_name(lock_owners, module.name, tag.repo)
                lock_repos[tag.repo] = _lock_struct(tag)
                if module.is_root:
                    root_direct_deps.append(tag.repo)

    # Second pass: create lock models.
    for module in module_ctx.modules:
        for tag in module.tags.import_pdm:
            lock_model_structs[tag.repo] = json.encode(dict(
                model_type = "pdm",
                lock_file = str(tag.lock_file),
                project_file = str(tag.project_file) if tag.project_file else "",
                default_group = tag.default_group,
                optional_groups = tag.optional_groups,
                all_optional_groups = tag.all_optional_groups,
                development_groups = tag.development_groups,
                all_development_groups = tag.all_development_groups,
            ))
        for tag in module.tags.import_poetry:
            lock_model_structs[tag.repo] = json.encode(dict(
                model_type = "poetry",
                lock_file = str(tag.lock_file),
                project_file = str(tag.project_file) if tag.project_file else "",
                default_group = tag.default_group,
                optional_groups = tag.optional_groups,
                all_optional_groups = tag.all_optional_groups,
            ))
        for tag in module.tags.import_uv:
            lock_model_structs[tag.repo] = json.encode(dict(
                model_type = "uv",
                lock_file = str(tag.lock_file),
                project_file = str(tag.project_file) if tag.project_file else "",
                default_group = tag.default_group,
                optional_groups = tag.optional_groups,
                all_optional_groups = tag.all_optional_groups,
                development_groups = tag.development_groups,
                all_development_groups = tag.all_development_groups,
                require_static_urls = tag.require_static_urls,
            ))
        for tag in module.tags.import_pylock:
            lock_model_structs[tag.repo] = json.encode(dict(
                model_type = "pylock",
                lock_file = str(tag.lock_file),
                project_file = str(tag.project_file) if tag.project_file else "",
                default_group = tag.default_group,
                optional_groups = tag.optional_groups,
                all_optional_groups = tag.all_optional_groups,
                development_groups = tag.development_groups,
                all_development_groups = tag.all_development_groups,
            ))

    # Add package attributes.
    for module in module_ctx.modules:
        for tag in module.tags.package:
            check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            if tag.name in repo_info.packages:
                fail("Multiple package entries for package '{}' in repo '{}'".format(tag.name, tag.repo))
            repo_info.packages[tag.name] = normalize_package_tag(tag)

    # Generate the resolved lock repos.
    workspace_memberships = {}
    workspace_build_repos = {}
    repo_flags = {}
    repo_constraint_values = {}
    repo_platforms = {}

    for repo_name, repo_info in lock_repos.items():
        resolved_lock_repo_file = _generate_resolved_lock_repo(repo_info, lock_model_structs[repo_name])
        resolved_lock_files[repo_info.repo_name] = resolved_lock_repo_file
        workspace_memberships[repo_info.repo_name] = repo_info.repo_name
        if repo_info.build_repo:
            workspace_build_repos[repo_info.repo_name] = repo_info.build_repo

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

# V1 package tag — repo only, no workspace scoping.
_PACKAGE_ATTRS_V1 = dict(PACKAGE_ATTRS)
_PACKAGE_ATTRS_V1["repo"] = attr.string(
    doc = "The repository name.",
    mandatory = True,
)

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
_package_tag = tag_class(
    doc = "Specify package-specific settings.",
    attrs = _PACKAGE_ATTRS_V1,
)

lock_import = module_extension(
    implementation = _lock_import_impl,
    tag_classes = dict(
        import_pdm = _import_pdm_tag,
        import_poetry = _import_poetry_tag,
        import_uv = _import_uv_tag,
        import_pylock = _import_pylock_tag,
        package = _package_tag,
    ),
)
