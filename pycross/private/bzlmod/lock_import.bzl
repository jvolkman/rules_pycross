"""The lock_import extension."""

load("//pycross/private:pdm_lock_model.bzl", "pkg_repo_model_pdm")
load("//pycross/private:poetry_lock_model.bzl", "pkg_repo_model_poetry")
load("//pycross/private:resolved_lock_repo.bzl", "resolved_lock_repo")
load(":lock_hub_repo.bzl", "lock_hub_repo")
load(":tag_attrs.bzl", "COMMON_ATTRS", "COMMON_IMPORT_ATTRS", "PACKAGE_ATTRS", "PDM_IMPORT_ATTRS", "POETRY_IMPORT_ATTRS")

def _generate_resolved_lock_repo(lock_info, serialized_lock_model):
    repo_name = lock_info.repo_name
    args = {
        "name": repo_name,
        "lock_model": serialized_lock_model,
        "target_environments": lock_info.environments,
        "default_alias_single_version": lock_info.default_alias_single_version,
        "disallow_builds": lock_info.disallow_builds,
        "local_wheels": lock_info.local_wheels,
        "build_target_overrides": {},
        "always_build_packages": [],
        "package_build_dependencies": {},
        "package_ignore_dependencies": {},
    }

    for package_name, package in lock_info.packages.items():
        if package.build_target:
            args["build_target_overrides"][package_name] = str(package.build_target)
        if package.always_build:
            args["always_build_packages"].append(package_name)
        if package.build_dependencies:
            args["package_build_dependencies"][package_name] = package.build_dependencies
        if package.ignore_dependencies:
            args["package_ignore_dependencies"][package_name] = package.ignore_dependencies

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
            "{} declared by module '{}' attached to lock repo '{}' owned by other module '{}".format(
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
        default_alias_single_version = tag.default_alias_single_version,
        environments = environment_files,
        local_wheels = tag.local_wheels,
        disallow_builds = tag.disallow_builds,
        packages = {},
    )

def _lock_import_impl(module_ctx):
    lock_owners = {}
    lock_repos = {}
    lock_model_structs = {}
    resolved_lock_files = {}

    # A first pass initialize lock structures and make sure none of the repo names are duplicated.
    for module in module_ctx.modules:
        for tag in module.tags.import_pdm_lock + module.tags.import_poetry_lock:
            _check_unique_lock_repo(lock_owners, module, tag)
            lock_repos[tag.repo] = _lock_struct(module_ctx, tag)

    # Iterate over the various from_pdm and from_poetry tags and create lock models
    for module in module_ctx.modules:
        for tag in module.tags.import_pdm_lock:
            lock_model_structs[tag.repo] = pkg_repo_model_pdm(**{attr: getattr(tag, attr) for attr in PDM_IMPORT_ATTRS})
        for tag in module.tags.import_poetry_lock:
            lock_model_structs[tag.repo] = pkg_repo_model_poetry(**{attr: getattr(tag, attr) for attr in POETRY_IMPORT_ATTRS})

    # Add package attributes
    for module in module_ctx.modules:
        for tag in module.tags.package:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = tag

    # Generate the resolved lock repos
    for repo_name, repo_info in lock_repos.items():
        resolved_lock_repo_file = _generate_resolved_lock_repo(repo_info, lock_model_structs[repo_name])
        resolved_lock_files[repo_info.repo_name] = resolved_lock_repo_file

    lock_hub_repo(
        name = "lock_import_repos_hub",
        repo_files = resolved_lock_files,
    )

# Tag classes
_import_pdm_lock_tag = tag_class(
    doc = "Import a PDM lock file.",
    attrs = PDM_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | COMMON_ATTRS,
)
_import_poetry_lock_tag = tag_class(
    doc = "Import a Poetry lock file.",
    attrs = POETRY_IMPORT_ATTRS | COMMON_IMPORT_ATTRS | COMMON_ATTRS,
)
_package_tag = tag_class(
    doc = "Specify package-specific settings.",
    attrs = PACKAGE_ATTRS | COMMON_ATTRS,
)

lock_import = module_extension(
    implementation = _lock_import_impl,
    tag_classes = dict(
        import_pdm_lock = _import_pdm_lock_tag,
        import_poetry_lock = _import_poetry_lock_tag,
        package = _package_tag,
    ),
)
