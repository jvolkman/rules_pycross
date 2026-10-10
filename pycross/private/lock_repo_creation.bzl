"""Shared repo creation logic for lock extensions.

This module contains the create_repos() function that creates all Bazel repos
(remote files, sdist repos, package repos, thin repos) from resolved lock data.
Used by the per-format lock extensions (uv, pdm, poetry, pylock).
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS", "BACKEND_TO_RULE", "DEFAULT_BACKEND", "OVERRIDE_FILES")
load("@pypackaging.bzl", "pypackaging")
load("@rules_pycross//pycross/private:override_helpers.bzl", "merge_backend_overrides")
load("@rules_pycross//pycross/private:sdist_repo.bzl", "pycross_sdist_repo")
load("//pycross/private:package_repo.bzl", "package_repo")
load("//pycross/private:pypi_file.bzl", "pypi_file")
load("//pycross/private:thin_package_repo.bzl", "thin_package_repo")
load("//pycross/private:util.bzl", "key_name", "parse_package_key", "sanitize_name", "sdist_builds_disallowed")
load("//pycross/private:wheel_file.bzl", "pycross_wheel_file")
load(":git_file.bzl", "pycross_git_file")

# Annotation fields that affect pycross_wheel_library targets.
_ANNOTATION_FIELDS = ["post_install_patches", "install_exclude_globs", "wheel_library_tags", "precompile"]

def _disallowed_sdist_repo_impl(rctx):
    fail(
        "Package '{}' requires building from source (sdist), ".format(rctx.attr.package_name) +
        "but its build_mode is \"never\" (lock import '{}'). ".format(rctx.attr.lock_name) +
        "Provide a pre-built wheel or set a different build_mode for this package.",
    )

pycross_disallowed_sdist_repo = repository_rule(
    implementation = _disallowed_sdist_repo_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
        "lock_name": attr.string(mandatory = True),
    },
)

sdist_builds_disallowed_for_testing = sdist_builds_disallowed

def _normalize_override_name(pkg_name, backend_name, workspace_name):
    """Normalize an override tag name ("*", "name", or "name@version") into its storage key.

    The package name is canonicalized; the version is kept as written and must match
    the locked version string.
    """
    if pkg_name == "*":
        return pkg_name
    name, sep, version = pkg_name.partition("@")
    if not name or name == "*" or (sep and not version):
        fail("{} override '{}' (workspace '{}'): expected a package name, 'name@version', or '*'".format(
            backend_name,
            pkg_name,
            workspace_name,
        ))
    name = pypackaging.utils.canonicalize_name(name)
    return "{}@{}".format(name, version) if sep else name

def _validate_override_packages(override_configs, all_resolved_locks, workspace_memberships):
    """Fail on backend overrides that name a package (or version) not present in their workspace.

    Workspaces that are not known here are skipped: they may belong to a different
    lock extension (e.g. a pdm workspace when running the uv extension).
    """
    workspace_versions = {}  # workspace_name -> {normalized package name -> {version -> True}}
    for repo_name, rlock in all_resolved_locks.items():
        names = workspace_versions.setdefault(workspace_memberships.get(repo_name, repo_name), {})
        for key in rlock.get("packages", {}):
            parts = parse_package_key(key)
            names.setdefault(pypackaging.utils.canonicalize_name(parts.name), {})[parts.version] = True

    for workspace_name, packages in override_configs.items():
        known_names = workspace_versions.get(workspace_name)
        if known_names == None:
            continue
        for override_key, backends in packages.items():
            if override_key == "*":
                continue
            pkg_name, _, version = override_key.partition("@")
            backend_names = ", ".join(sorted(backends.keys()))
            if pkg_name not in known_names:
                fail("{} override for package '{}' matches no package in workspace '{}'".format(
                    backend_names,
                    override_key,
                    workspace_name,
                ))
            if version and version not in known_names[pkg_name]:
                fail("{} override for '{}' matches no locked version of '{}' in workspace '{}'; available versions: {}".format(
                    backend_names,
                    override_key,
                    pkg_name,
                    workspace_name,
                    ", ".join(sorted(known_names[pkg_name].keys())),
                ))

def create_repos(
        module_ctx,
        all_locks,
        workspace_memberships,
        repo_flags,
        repo_constraint_values,
        repo_platforms,
        workspace_pypi_indexes = {},
        repo_settings = {},
        resolved_locks = None):
    """Create all Bazel repos from resolved lock data.

    Args:
        module_ctx: The module_ctx or similar context object (needs .path(), .read()).
        all_locks: Dict of repo_name -> lock file Label (pointing to lock.json).
        workspace_memberships: Dict of repo_name -> workspace_name.
        repo_flags: Dict of repo_name -> JSON-encoded flags list.
        repo_settings: Dict of repo_name -> {setting label: value} dict.
        repo_constraint_values: Dict of repo_name -> JSON-encoded constraint_values list.
        repo_platforms: Dict of repo_name -> platform string.
        workspace_pypi_indexes: Dict of workspace_name -> list of string index URLs.
        resolved_locks: Optional dict of repo_name -> parsed lock JSON dict. When provided,
            lock data is taken from this dict instead of reading from all_locks file labels.
            all_locks is still used for passing labels to package_repo/thin_package_repo.

    Returns:
        None. Creates repos as a side effect.
    """
    all_remote_files = {}

    # Build per-workspace, per-package override configs from registered override files.
    override_configs = {}
    for f in OVERRIDE_FILES:
        data = json.decode(module_ctx.read(f))
        for key, packages in data.items():
            for pkg_name, entry in packages.items():
                backend_name = entry.get("build_backend", "")
                backend_attrs = entry.get("backend_attrs", {})
                norm_pkg = _normalize_override_name(pkg_name, backend_name, key)
                override_configs.setdefault(key, {}).setdefault(norm_pkg, {})[backend_name] = backend_attrs

    # Pre-pathify all lock files to minimize restart time (only when reading from files).
    if not resolved_locks:
        for lock_file in all_locks.values():
            module_ctx.path(lock_file)

    # Serialize backend configs for passing to package_repo and sdist_repo.
    backend_configs_json = {name: json.encode(config) for name, config in BACKEND_CONFIGS.items()}
    backend_tool_packages = {
        name: list(config.get("tool_packages", []))
        for name, config in BACKEND_CONFIGS.items()
    }

    all_resolved_locks = {}
    for repo_name, lock_file in all_locks.items():
        if resolved_locks and repo_name in resolved_locks:
            all_resolved_locks[repo_name] = resolved_locks[repo_name]
        else:
            resolved_lock_file = module_ctx.path(lock_file)
            all_resolved_locks[repo_name] = json.decode(module_ctx.read(resolved_lock_file))

    known_packages_by_repo = {
        repo_name: [key_name(key) for key in rlock.get("packages", {})]
        for repo_name, rlock in all_resolved_locks.items()
    }

    _validate_override_packages(override_configs, all_resolved_locks, workspace_memberships)

    # Generate the lock repos and any remote package repos
    per_repo_data = {}  # repo_name -> struct(repo_map, sdist_map, lock_file)
    created_sdist_repos = {}  # sdist_repo_name -> True, for workspace-level dedup
    for repo_name, lock_file in all_locks.items():
        resolved_lock = all_resolved_locks[repo_name]

        repo_remote_files = {}
        workspace_name = workspace_memberships.get(repo_name)
        indexes = workspace_pypi_indexes.get(workspace_name, []) if workspace_name else []

        for key, file in resolved_lock.get("remote_files", {}).items():
            if key in all_remote_files:
                repo_remote_files[key] = all_remote_files[key]
                continue

            remote_file_repo = "pypi_{}".format(sanitize_name(key.replace("/", "_")))
            if file["name"].endswith(".whl"):
                remote_file_label = "@{}//:wheel".format(remote_file_repo)
            else:
                remote_file_label = "@{}//file:{}".format(remote_file_repo, file["name"])

            urls = file.get("urls", [])
            if urls:
                if file["name"].endswith(".whl"):
                    pycross_wheel_file(
                        name = remote_file_repo,
                        urls = urls,
                        sha256 = file["sha256"],
                        filename = file["name"],
                    )
                elif urls[0].startswith("git+"):
                    pycross_git_file(
                        name = remote_file_repo,
                        url = urls[0],
                        filename = file["name"],
                    )
                else:
                    http_file(
                        name = remote_file_repo,
                        urls = urls,
                        sha256 = file["sha256"],
                        downloaded_file_path = file["name"],
                    )
            else:
                pypi_file_attrs = dict(
                    name = remote_file_repo,
                    package_name = file["package_name"],
                    package_version = file["package_version"],
                    filename = file["name"],
                    sha256 = file["sha256"],
                )

                # A per-package index recorded in the lock takes priority over
                # the workspace's pypi_indexes.
                if file.get("index"):
                    pypi_file_attrs["indexes"] = [file["index"]]
                elif indexes:
                    pypi_file_attrs["indexes"] = indexes
                if file["name"].endswith(".whl"):
                    pycross_wheel_file(**pypi_file_attrs)
                else:
                    pypi_file(**pypi_file_attrs)

            repo_remote_files[key] = remote_file_label
            all_remote_files[key] = remote_file_label

        # Pre-calculate known packages in this lock file to filter sdist build_requires
        known_packages = known_packages_by_repo[repo_name]

        sdist_map = {}

        # Every repo has a workspace.
        workspace_name = workspace_memberships.get(repo_name, repo_name)

        lock_repo_for_deps = "{}__pkgs".format(workspace_name)

        # Instantiate sdist repos for packages requiring source builds.
        for pkg_key, pkg in resolved_lock.get("packages", {}).items():
            if pkg.get("build_target"):
                continue

            sdist_file = pkg.get("sdist_file")
            if not sdist_file:
                continue

            sdist_file_key = sdist_file["key"]
            sdist_label = repo_remote_files[sdist_file_key]

            sdist_repo_name = "{}_sdist_{}".format(
                lock_repo_for_deps,
                sanitize_name(pkg_key),
            )
            sdist_label_str = "@{}//:wheel".format(sdist_repo_name)
            sdist_map[sdist_file_key] = sdist_label_str

            if sdist_repo_name in created_sdist_repos:
                continue
            created_sdist_repos[sdist_repo_name] = True

            deps_set = {}

            for md in pkg.get("marker_dependencies", []):
                dep_label = "@{}//_lock:{}".format(lock_repo_for_deps, md["key"])
                deps_set[dep_label] = True

            parts = parse_package_key(pkg_key)
            pkg_name_part = parts.name
            pkg_version = parts.version
            whldir_norm_name = sanitize_name(pkg_name_part)
            whldir_name = "{}-{}.whldir".format(whldir_norm_name, pkg_version)

            if pkg.get("build_tools_repo") and pkg["build_tools_repo"] not in known_packages_by_repo:
                fail("Package '{}' sets build_tools_repo = '{}', which is not a repo created by this extension. Known repos: {}".format(
                    pkg_key,
                    pkg["build_tools_repo"],
                    ", ".join(sorted(known_packages_by_repo.keys())),
                ))
            thin_repo = pkg.get("build_tools_repo") or "{}__build".format(workspace_name)
            sdist_repo_attrs = {
                "name": sdist_repo_name,
                "sdist": sdist_label,
                "deps": sorted(deps_set.keys()),
                "known_packages": known_packages_by_repo.get(thin_repo, known_packages),
                "pin_versions_json": "@{}//:pin_versions.json".format(thin_repo),
                "lock_repo": lock_repo_for_deps,
                "thin_repo": thin_repo,
                "backend_to_rule": BACKEND_TO_RULE,
                "backend_tool_packages": backend_tool_packages,
                "default_backend": DEFAULT_BACKEND,
                "whldir_name": whldir_name,
            }
            if "extra_build_tools" in pkg and pkg["extra_build_tools"] != None:
                sdist_repo_attrs["extra_build_tools"] = pkg["extra_build_tools"]

            if pkg.get("source_dir"):
                sdist_repo_attrs["source_dir"] = pkg["source_dir"]

            for attr_name in ("build_backend", "pre_build_patches", "site_hooks"):
                if attr_name in pkg and pkg[attr_name] != None:
                    sdist_repo_attrs[attr_name] = pkg[attr_name]

            pkg_name = pypackaging.utils.canonicalize_name(parts.name)
            pkg_overrides = {}

            def _apply_scope_overrides(src_key):
                if src_key not in override_configs:
                    return
                merged = merge_backend_overrides(override_configs[src_key], pkg_name, pkg_version)
                for b_name, b_attrs in merged.items():
                    pkg_overrides.setdefault(b_name, {}).update(b_attrs)

            ws_key = workspace_name
            _apply_scope_overrides(ws_key)

            if pkg_overrides:
                sdist_repo_attrs["override_backend_configs"] = json.encode(pkg_overrides)

            if sdist_builds_disallowed(pkg):
                pycross_disallowed_sdist_repo(
                    name = sdist_repo_name,
                    package_name = pkg_key,
                    lock_name = repo_name,
                )
            else:
                pycross_sdist_repo(**sdist_repo_attrs)

        # Save per-repo data for workspace processing
        per_repo_data[repo_name] = struct(
            repo_map = repo_remote_files,
            sdist_map = sdist_map,
            lock_file = lock_file,
            resolved_lock = resolved_lock,
        )

    # Create workspace package repos and thin repos for all members.
    workspace_groups = {}  # workspace_name -> [repo_name, ...]
    for repo_name, uname in workspace_memberships.items():
        workspace_groups.setdefault(uname, []).append(repo_name)

    for workspace_name, member_repos in workspace_groups.items():
        workspace_repo_name = "{}__pkgs".format(workspace_name)

        # Merge repo_maps and sdist_maps from all members
        merged_repo_map = {}
        merged_sdist_map = {}

        for member in member_repos:
            data = per_repo_data[member]
            merged_repo_map.update(data.repo_map)
            merged_sdist_map.update(data.sdist_map)

        member_lock_files = {
            member: str(per_repo_data[member].lock_file)
            for member in member_repos
        }

        # Detect annotation conflicts using cached resolved lock data.
        member_packages = {}  # member -> {pkg_key -> pkg_data}
        for member in member_repos:
            member_packages[member] = per_repo_data[member].resolved_lock.get("packages", {})

        # Build a map of pkg_key -> [member, ...] for conflicting packages.
        all_pkg_keys = {}  # pkg_key -> list of (member, pkg_data)
        for member, pkgs in member_packages.items():
            for pkg_key, pkg_data in pkgs.items():
                all_pkg_keys.setdefault(pkg_key, []).append((member, pkg_data))

        conflicts = {}  # pkg_key -> [member_name, ...]
        for pkg_key, entries in all_pkg_keys.items():
            if len(entries) <= 1:
                continue
            _, first_data = entries[0]
            for _, other_data in entries[1:]:
                for field in _ANNOTATION_FIELDS:
                    if (first_data.get(field) or None) != (other_data.get(field) or None):
                        conflicts[pkg_key] = [m for m, _ in entries]
                        break
                if pkg_key in conflicts:
                    break

        # Compute per-package override configs for package and thin repo hooks.
        ws_overrides = {}  # pkg_name -> {backend_name -> backend_attrs}
        if workspace_name in override_configs:
            for pkg_name, backends in override_configs[workspace_name].items():
                for b_name, b_attrs in backends.items():
                    ws_overrides.setdefault(pkg_name, {})[b_name] = dict(b_attrs)
        ws_overrides_json = json.encode(ws_overrides) if ws_overrides else None

        package_repo_attrs = dict(
            name = workspace_repo_name,
            build_repo = "{}__build".format(workspace_name),
            repo_map = merged_repo_map,
            sdist_map = merged_sdist_map,
            backend_configs = backend_configs_json,
            member_lock_files = member_lock_files,
        )
        if ws_overrides_json:
            package_repo_attrs["override_configs"] = ws_overrides_json
        if resolved_locks:
            package_repo_attrs["member_lock_data"] = {
                member: json.encode(per_repo_data[member].resolved_lock)
                for member in member_repos
            }
        package_repo(**package_repo_attrs)

        # Create thin repos for each workspace member, passing conflict info.
        for member in member_repos:
            thin_repo_attrs = dict(
                name = member,
                resolved_lock_file = per_repo_data[member].lock_file,
                workspace_repo = workspace_repo_name,
                member_name = member,
                conflicts = conflicts,
                backend_configs = backend_configs_json,
            )
            thin_repo_attrs["default_build_tools_repo"] = workspace_repo_name
            thin_repo_attrs["generate_root_aliases"] = True

            if member in repo_flags:
                flags = repo_flags[member]
                thin_repo_attrs["flags"] = json.decode(flags) if type(flags) == "string" else flags
            if member in repo_settings:
                thin_repo_attrs["settings"] = repo_settings[member]
            if member in repo_constraint_values:
                constraints = repo_constraint_values[member]
                thin_repo_attrs["constraint_values"] = json.decode(constraints) if type(constraints) == "string" else constraints
            if member in repo_platforms:
                thin_repo_attrs["platform"] = repo_platforms[member]

            if ws_overrides_json:
                thin_repo_attrs["override_configs"] = ws_overrides_json

            thin_package_repo(**thin_repo_attrs)

# Visible for testing
validate_override_packages_for_testing = _validate_override_packages
normalize_override_name_for_testing = _normalize_override_name
