"""The lock_import extension."""

load("@bazel_features//:features.bzl", "bazel_features")
load("//pycross/private:lock_attrs.bzl", "package_annotation")
load("//pycross/private:pdm_lock_model.bzl", "lock_repo_model_pdm")
load("//pycross/private:poetry_lock_model.bzl", "lock_repo_model_poetry")
load("//pycross/private:resolved_lock_repo.bzl", "resolved_lock_repo")
load("//pycross/private:uv_lock_model.bzl", "lock_repo_model_uv")
load(":lock_hub_repo.bzl", "lock_hub_repo")
load(":tag_attrs.bzl", "CMAKE_OVERRIDE_ATTRS", "COMMON_ATTRS", "COMMON_IMPORT_ATTRS", "MATURIN_OVERRIDE_ATTRS", "MESON_OVERRIDE_ATTRS", "PACKAGE_ATTRS", "PDM_IMPORT_ATTRS", "POETRY_IMPORT_ATTRS", "SETUPTOOLS_OVERRIDE_ATTRS", "UV_IMPORT_ATTRS")

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
            build_backend = package.build_backend,
            backend_attrs = package.backend_attrs,
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
        default_build_dependencies = tag.default_build_dependencies,
        packages = {},
    )

def _make_package_info(tag, build_backend, build_target, backend_attrs):
    """Build a normalized package info struct from common tag attrs."""
    return struct(
        always_build = tag.always_build,
        build_dependencies = tag.build_dependencies,
        build_target = build_target,
        ignore_dependencies = tag.ignore_dependencies,
        install_exclude_globs = tag.install_exclude_globs,
        post_install_patches = tag.post_install_patches,
        build_backend = build_backend,
        backend_attrs = backend_attrs,
    )

def _normalize_package_tag(tag):
    """Normalize a generic package tag (has build_target and backend_attrs)."""
    return _make_package_info(tag, None, tag.build_target, dict(tag.backend_attrs))

def _normalize_override_tag(tag, build_backend):
    """Normalize a backend-specific override tag (has typed build-system attrs)."""
    backend_attrs = {}
    if tag.copts:
        backend_attrs["copts"] = json.encode(tag.copts)
    if tag.linkopts:
        backend_attrs["linkopts"] = json.encode(tag.linkopts)
    if tag.native_deps:
        backend_attrs["native_deps"] = json.encode([str(dep) for dep in tag.native_deps])
    if tag.config_settings:
        backend_attrs["config_settings"] = json.encode(tag.config_settings)
    if tag.tool_deps:
        backend_attrs["tool_deps"] = json.encode(tag.tool_deps)

    # cargo_lock is maturin-specific; other override tags don't have it.
    if hasattr(tag, "cargo_lock") and tag.cargo_lock:
        backend_attrs["cargo_lock"] = json.encode(str(tag.cargo_lock))

    return _make_package_info(tag, build_backend, None, backend_attrs)

def _lock_import_impl(module_ctx):
    lock_owners = {}
    lock_repos = {}
    lock_model_structs = {}
    resolved_lock_files = {}

    # A first pass initialize lock structures and make sure none of the repo names are duplicated.
    for module in module_ctx.modules:
        for tag in module.tags.import_pdm + module.tags.import_poetry + module.tags.import_uv:
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

    # Add package attributes
    for module in module_ctx.modules:
        for tag in module.tags.package:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = _normalize_package_tag(tag)

        for tag in module.tags.meson_override:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = _normalize_override_tag(tag, "meson_build")

        for tag in module.tags.setuptools_override:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = _normalize_override_tag(tag, "setuptools_build")

        for tag in module.tags.cmake_override:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = _normalize_override_tag(tag, "cmake_build")

        for tag in module.tags.maturin_override:
            _check_proper_package_repo(lock_owners, module, tag)
            repo_info = lock_repos[tag.repo]
            _check_package_entry_not_set(lock_owners, repo_info, tag)
            repo_info.packages[tag.name] = _normalize_override_tag(tag, "maturin_build")

    # Read external override sources (from backend extensions)
    for module in module_ctx.modules:
        for tag in module.tags.override_source:
            overrides_json = module_ctx.read(tag.file)
            external_overrides = json.decode(overrides_json)
            for key, override in external_overrides.items():
                repo_name, _, pkg_name = key.partition(":")
                if repo_name not in lock_repos:
                    fail("Override source references unknown lock repo '{}'".format(repo_name))
                repo_info = lock_repos[repo_name]
                if pkg_name in repo_info.packages:
                    fail("Duplicate package override for '{}' in lock repo '{}'".format(pkg_name, repo_name))
                repo_info.packages[pkg_name] = struct(
                    always_build = override.get("always_build", False),
                    build_dependencies = override.get("build_dependencies", []),
                    build_target = override.get("build_target"),
                    ignore_dependencies = override.get("ignore_dependencies", []),
                    install_exclude_globs = override.get("install_exclude_globs", []),
                    post_install_patches = override.get("post_install_patches", []),
                    build_backend = override.get("build_backend"),
                    backend_attrs = override.get("backend_attrs", {}),
                )

    # Generate the resolved lock repos
    for repo_name, repo_info in lock_repos.items():
        resolved_lock_repo_file = _generate_resolved_lock_repo(repo_info, lock_model_structs[repo_name])
        resolved_lock_files[repo_info.repo_name] = resolved_lock_repo_file

    lock_hub_repo(
        name = "lock_import_repos_hub",
        repo_files = resolved_lock_files,
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
_package_tag = tag_class(
    doc = "Specify package-specific settings.",
    attrs = PACKAGE_ATTRS | COMMON_ATTRS,
)
_meson_override_tag = tag_class(
    doc = "Specify meson-specific overrides.",
    attrs = MESON_OVERRIDE_ATTRS | COMMON_ATTRS,
)
_setuptools_override_tag = tag_class(
    doc = "Specify setuptools-specific overrides.",
    attrs = SETUPTOOLS_OVERRIDE_ATTRS | COMMON_ATTRS,
)
_cmake_override_tag = tag_class(
    doc = "Specify cmake-specific overrides.",
    attrs = CMAKE_OVERRIDE_ATTRS | COMMON_ATTRS,
)
_maturin_override_tag = tag_class(
    doc = "Specify maturin-specific overrides.",
    attrs = MATURIN_OVERRIDE_ATTRS | COMMON_ATTRS,
)
_override_source_tag = tag_class(
    doc = "Register an external override source (JSON file from a backend extension).",
    attrs = {
        "file": attr.label(
            doc = "Label of the overrides JSON file generated by a backend extension.",
            mandatory = True,
            allow_single_file = [".json"],
        ),
    },
)

lock_import = module_extension(
    implementation = _lock_import_impl,
    tag_classes = dict(
        import_pdm = _import_pdm_tag,
        import_poetry = _import_poetry_tag,
        import_uv = _import_uv_tag,
        package = _package_tag,
        override_source = _override_source_tag,
        meson_override = _meson_override_tag,
        setuptools_override = _setuptools_override_tag,
        cmake_override = _cmake_override_tag,
        maturin_override = _maturin_override_tag,
    ),
)
