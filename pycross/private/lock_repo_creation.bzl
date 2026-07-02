"""Shared repo creation logic for lock extensions.

This module contains the create_repos() function that creates all Bazel repos
(remote files, sdist repos, package repos, thin repos) from resolved lock data.
Used by both the legacy lock_repos extension and the unified locks extension.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS", "BACKEND_TO_RULE", "DEFAULT_BACKEND", "OVERRIDE_FILES")
load("@pypackaging.bzl", "pypackaging")
load("@rules_pycross//pycross/private:sdist_repo.bzl", "pycross_sdist_repo")
load("//pycross/private:package_repo.bzl", "package_repo")
load("//pycross/private:pypi_file.bzl", "pypi_file")
load("//pycross/private:thin_package_repo.bzl", "thin_package_repo")
load("//pycross/private:util.bzl", "key_name", "parse_package_key", "sanitize_name")
load("//pycross/private:wheel_file.bzl", "pycross_wheel_file")
load(":git_file.bzl", "pycross_git_file")

# Annotation fields that affect pycross_wheel_library targets.
_ANNOTATION_FIELDS = ["post_install_patches", "install_exclude_globs"]

def _disallowed_sdist_repo_impl(rctx):
    fail(
        "Package '{}' requires building from source (sdist), ".format(rctx.attr.package_name) +
        "but builds are disallowed for lock import '{}'. ".format(rctx.attr.lock_name) +
        "Provide a pre-built wheel or remove disallow_builds.",
    )

pycross_disallowed_sdist_repo = repository_rule(
    implementation = _disallowed_sdist_repo_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
        "lock_name": attr.string(mandatory = True),
    },
)

def create_repos(
        module_ctx,
        all_locks,
        workspace_memberships,
        workspace_build_repos,
        repo_flags,
        repo_constraint_values,
        repo_platforms,
        repo_disallow_builds = {},
        workspace_pypi_indexes = {},
        resolved_locks = None):
    """Create all Bazel repos from resolved lock data.

    Args:
        module_ctx: The module_ctx or similar context object (needs .path(), .read()).
        all_locks: Dict of repo_name -> lock file Label (pointing to lock.json).
        workspace_memberships: Dict of repo_name -> workspace_name.
        workspace_build_repos: Dict of workspace_name -> build_repo.
        repo_flags: Dict of repo_name -> JSON-encoded flags list.
        repo_constraint_values: Dict of repo_name -> JSON-encoded constraint_values list.
        repo_platforms: Dict of repo_name -> platform string.
        repo_disallow_builds: Dict of repo_name -> boolean indicating if builds are disallowed.
        workspace_pypi_indexes: Dict of workspace_name -> list of string index URLs.
        resolved_locks: Optional dict of repo_name -> parsed lock JSON dict. When provided,
            lock data is taken from this dict instead of reading from all_locks file labels.
            all_locks is still used for passing labels to package_repo/thin_package_repo.

    Returns:
        None. Creates repos as a side effect.
    """
    all_remote_files = {}

    # Build per-repo, per-package override configs from registered override files.
    override_configs = {}
    for f in OVERRIDE_FILES:
        data = json.decode(module_ctx.read(f))
        for key, packages in data.items():
            for pkg_name, entry in packages.items():
                backend_name = entry.get("build_backend", "")
                backend_attrs = entry.get("backend_attrs", {})
                norm_pkg = pypackaging.utils.canonicalize_name(pkg_name)
                override_configs.setdefault(key, {}).setdefault(norm_pkg, {})[backend_name] = backend_attrs

    # Validate that repo: overrides don't target workspace members.
    for key in override_configs:
        if key.startswith("repo:"):
            repo_name = key[len("repo:"):]
            ws = workspace_memberships.get(repo_name)
            if ws and ws != repo_name:
                fail(
                    "Build system override targets repo '{}' which is a member of workspace '{}'. ".format(repo_name, ws) +
                    "Use workspace = '{}' instead.".format(ws),
                )

    # Pre-pathify all lock files to minimize restart time (only when reading from files).
    if not resolved_locks:
        for lock_file in all_locks.values():
            module_ctx.path(lock_file)

    # Serialize backend configs for passing to package_repo.
    backend_configs_json = {name: json.encode(config) for name, config in BACKEND_CONFIGS.items()}

    # Generate the lock repos and any remote package repos
    per_repo_data = {}  # repo_name -> struct(repo_map, sdist_map, lock_file)
    created_sdist_repos = {}  # sdist_repo_name -> True, for workspace-level dedup
    for repo_name, lock_file in all_locks.items():
        if resolved_locks:
            resolved_lock = resolved_locks[repo_name]
        else:
            resolved_lock_file = module_ctx.path(lock_file)
            resolved_lock = json.decode(module_ctx.read(resolved_lock_file))

        repo_remote_files = {}
        workspace_name = workspace_memberships.get(repo_name)
        indexes = workspace_pypi_indexes.get(workspace_name, []) if workspace_name else []
        pypi_index = indexes[0] if indexes else None

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
                if pypi_index:
                    pypi_file_attrs["index"] = pypi_index
                elif file.get("index"):
                    pypi_file_attrs["index"] = file["index"]
                if file["name"].endswith(".whl"):
                    pycross_wheel_file(**pypi_file_attrs)
                else:
                    pypi_file(**pypi_file_attrs)

            repo_remote_files[key] = remote_file_label
            all_remote_files[key] = remote_file_label

        # Pre-calculate known packages in this lock file to filter sdist build_requires
        known_packages = [key_name(key) for key in resolved_lock.get("packages", {})]

        sdist_map = {}

        # Every repo has a workspace.
        workspace_name = workspace_memberships.get(repo_name, repo_name)

        ws_build_repo = workspace_build_repos.get(workspace_name)
        if ws_build_repo:
            lock_repo_for_deps = "{}__pkgs".format(workspace_memberships.get(ws_build_repo, ws_build_repo))
        else:
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

            pkg_build_repo = pkg.get("build_repo") or ws_build_repo
            if pkg_build_repo:
                pkg_lock_repo_for_deps = "{}__pkgs".format(workspace_memberships.get(pkg_build_repo, pkg_build_repo))
            else:
                pkg_lock_repo_for_deps = "{}__pkgs".format(workspace_name)

            sdist_repo_attrs = {
                "name": sdist_repo_name,
                "sdist": sdist_label,
                "deps": sorted(deps_set.keys()),
                "known_packages": known_packages,
                "lock_json": lock_file,
                "lock_repo": pkg_lock_repo_for_deps,
                "thin_repo": repo_name,
                "backend_to_rule": BACKEND_TO_RULE,
                "default_backend": DEFAULT_BACKEND,
                "whldir_name": whldir_name,
            }
            if "build_dependencies" in pkg and pkg["build_dependencies"] != None:
                sdist_repo_attrs["build_dependencies"] = pkg["build_dependencies"]

            for attr_name in ("build_backend", "pre_build_patches", "site_hooks"):
                if attr_name in pkg and pkg[attr_name] != None:
                    sdist_repo_attrs[attr_name] = pkg[attr_name]

            pkg_name = key_name(pkg_key)
            pkg_overrides = {}

            def _apply_scope_overrides(src_key):
                if src_key not in override_configs:
                    return
                scope = override_configs[src_key]
                source = scope.get(pkg_name, scope.get("*"))
                if source:
                    for b_name, b_attrs in source.items():
                        pkg_overrides[b_name] = dict(b_attrs)

            ws_key = "workspace:" + workspace_name
            _apply_scope_overrides(ws_key)

            repo_key = "repo:" + repo_name
            _apply_scope_overrides(repo_key)

            if pkg_overrides:
                sdist_repo_attrs["override_backend_configs"] = json.encode(pkg_overrides)

            if repo_disallow_builds.get(repo_name, False):
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
                    if first_data.get(field, []) != other_data.get(field, []):
                        conflicts[pkg_key] = [m for m, _ in entries]
                        break
                if pkg_key in conflicts:
                    break

        # Compute per-package override configs for package repo hooks.
        ws_overrides = {}  # pkg_name -> {backend_name -> backend_attrs}
        keys = ["workspace:" + workspace_name] + ["repo:" + member for member in member_repos]
        for key in keys:
            if key in override_configs:
                for pkg_name, backends in override_configs[key].items():
                    for b_name, b_attrs in backends.items():
                        ws_overrides.setdefault(pkg_name, {})[b_name] = dict(b_attrs)

        package_repo_attrs = dict(
            name = workspace_repo_name,
            resolved_lock_file = per_repo_data[member_repos[0]].lock_file,
            repo_map = merged_repo_map,
            sdist_map = merged_sdist_map,
            backend_configs = backend_configs_json,
            member_lock_files = member_lock_files,
        )
        if ws_overrides:
            package_repo_attrs["override_configs"] = json.encode(ws_overrides)
        if resolved_locks:
            package_repo_attrs["member_lock_data"] = {
                member: json.encode(per_repo_data[member].resolved_lock)
                for member in member_repos
            }
        package_repo(**package_repo_attrs)

        # Create thin repos for each workspace member, passing conflict info.
        thin_build_repo = workspace_build_repos.get(workspace_name)
        for member in member_repos:
            thin_repo_attrs = dict(
                name = member,
                resolved_lock_file = per_repo_data[member].lock_file,
                workspace_repo = workspace_repo_name,
                member_name = member,
                conflicts = conflicts,
                backend_configs = backend_configs_json,
            )
            if thin_build_repo:
                thin_repo_attrs["workspace_build_repo"] = "{}__pkgs".format(workspace_memberships.get(thin_build_repo, thin_build_repo))

            if member in repo_flags:
                flags = repo_flags[member]
                thin_repo_attrs["flags"] = json.decode(flags) if type(flags) == "string" else flags
            if member in repo_constraint_values:
                constraints = repo_constraint_values[member]
                thin_repo_attrs["constraint_values"] = json.decode(constraints) if type(constraints) == "string" else constraints
            if member in repo_platforms:
                thin_repo_attrs["platform"] = repo_platforms[member]

            # Compute per-member override configs for thin repo hooks.
            member_overrides = {}  # pkg_name -> {backend_name -> backend_attrs}
            ws_key = "workspace:" + workspace_name
            if ws_key in override_configs:
                for pkg_name, backends in override_configs[ws_key].items():
                    for b_name, b_attrs in backends.items():
                        member_overrides.setdefault(pkg_name, {})[b_name] = dict(b_attrs)
            repo_key = "repo:" + member
            if repo_key in override_configs:
                for pkg_name, backends in override_configs[repo_key].items():
                    for b_name, b_attrs in backends.items():
                        member_overrides.setdefault(pkg_name, {})[b_name] = dict(b_attrs)
            if member_overrides:
                thin_repo_attrs["override_configs"] = json.encode(member_overrides)

            thin_package_repo(**thin_repo_attrs)
