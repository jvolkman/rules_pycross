"""The lock_repos extension."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@lock_import_repos_hub//:locks.bzl", lock_import_locks = "locks")
load("@lock_import_repos_hub//:workspaces.bzl", "repo_constraint_values", "repo_flags", "repo_platforms", "root_repos", "workspace_build_repos", "workspace_memberships")
load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS", "BACKEND_TO_RULE", "DEFAULT_BACKEND", "OVERRIDE_FILES")
load("@rules_pycross//pycross/private:sdist_repo.bzl", "pycross_sdist_repo")
load("//pycross/private:package_repo.bzl", "package_repo")
load("//pycross/private:pypi_file.bzl", "pypi_file")
load("//pycross/private:thin_package_repo.bzl", "thin_package_repo")
load("//pycross/private:util.bzl", "key_name", "parse_package_key", "sanitize_name")
load("//pycross/private:wheel_file.bzl", "pycross_wheel_file")
load(":git_file.bzl", "pycross_git_file")
load(":lock_attrs.bzl", "CREATE_REPOS_ATTRS")

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _lock_repos_impl(module_ctx):
    all_locks = lock_import_locks  # Some day there may be others.
    all_remote_files = {}

    # Build per-repo, per-package override configs from registered override files.
    # override_configs[key][pkg_name][backend_name] = {backend_attrs dict}
    # Keys are prefixed with "repo:" or "workspace:" to distinguish scope.
    override_configs = {}
    for f in OVERRIDE_FILES:
        data = json.decode(module_ctx.read(f))
        for key, packages in data.items():
            for pkg_name, entry in packages.items():
                backend_name = entry.get("build_backend", "")
                backend_attrs = entry.get("backend_attrs", {})
                override_configs.setdefault(key, {}).setdefault(pkg_name, {})[backend_name] = backend_attrs

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

    # Pre-pathify all lock files to minimize restart time.
    for lock_file in all_locks.values():
        module_ctx.path(lock_file)

    create_tag = None
    for module in module_ctx.modules:
        for tag in module.tags.create:
            if module.name != "rules_pycross" and not module.is_root:
                _print_warn("Ignoring repos.create tag from non-root, non-pycross module {}".format(module.name))
                continue

            # Root module has precedence
            if create_tag == None:
                create_tag = tag

    if create_tag == None:
        # This shouldn't happen since rules_pycross registers a default tag.
        fail("BUG: no repos.create tag found!")

    # Serialize backend configs for passing to package_repo.
    backend_configs_json = {name: json.encode(config) for name, config in BACKEND_CONFIGS.items()}

    # Generate the lock repos and any remote package repos
    per_repo_data = {}  # repo_name -> struct(repo_map, sdist_map)
    created_sdist_repos = {}  # sdist_repo_name -> True, for workspace-level dedup
    for repo_name, lock_file in all_locks.items():
        resolved_lock_file = module_ctx.path(lock_file)
        resolved_lock = json.decode(module_ctx.read(resolved_lock_file))

        repo_remote_files = {}
        for key, file in resolved_lock.get("remote_files", {}).items():
            if key in all_remote_files:
                # We already have an entry for this key, so use that.
                # TODO: add some preference for http entries vs. pypi_file entries.
                repo_remote_files[key] = all_remote_files[key]
                continue

            # Use the key as our repo name, but replace its / with _ and sanitize for Bazel
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
                if create_tag.pypi_index:
                    pypi_file_attrs["index"] = create_tag.pypi_index
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

        # build_repo is a workspace name (the 'name' param of import_uv_workspace or
        # import_uv). workspace_memberships maps repo_name -> workspace_name, so if
        # build_repo isn't found as a repo key we use it directly as a workspace name.
        ws_build_repo = workspace_build_repos.get(workspace_name)
        if ws_build_repo:
            lock_repo_for_deps = "{}__pkgs".format(workspace_memberships.get(ws_build_repo, ws_build_repo))
        else:
            lock_repo_for_deps = "{}__pkgs".format(workspace_name)

        # Instantiate sdist repos for packages requiring source builds.
        # Sdist repos are shared at the workspace level: all members in the
        # same workspace share a single sdist build per package@version.
        for pkg_key, pkg in resolved_lock.get("packages", {}).items():
            if pkg.get("build_target"):
                # User provided a custom build target; skip auto-generating an sdist repo.
                continue

            sdist_file = pkg.get("sdist_file")
            if not sdist_file:
                continue

            sdist_file_key = sdist_file["key"]
            sdist_label = repo_remote_files[sdist_file_key]

            # Name sdist repos at the workspace level for deduplication.
            sdist_repo_name = "{}_sdist_{}".format(
                lock_repo_for_deps,
                sanitize_name(pkg_key),
            )
            sdist_label_str = "@{}//:wheel".format(sdist_repo_name)
            sdist_map[sdist_file_key] = sdist_label_str

            # Skip if another member in this workspace already created this sdist repo.
            if sdist_repo_name in created_sdist_repos:
                continue
            created_sdist_repos[sdist_repo_name] = True

            deps_set = {}

            # Marker path: collect all deps from marker_dependencies.
            for md in pkg.get("marker_dependencies", []):
                dep_label = "@{}//_lock:{}".format(lock_repo_for_deps, md["key"])
                deps_set[dep_label] = True

            # Compute the output whldir name: {normalized_name}-{version}.whldir
            parts = parse_package_key(pkg_key)
            pkg_name_part = parts.name
            pkg_version = parts.version
            whldir_norm_name = sanitize_name(pkg_name_part)
            whldir_name = "{}-{}.whldir".format(whldir_norm_name, pkg_version)

            # Recompute lock_repo_for_deps for this specific package if it has an override
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

            # Helper: apply overrides from a scope. A specific package entry
            # fully replaces the wildcard for that scope.
            def _apply_scope_overrides(src_key):
                if src_key not in override_configs:
                    return
                scope = override_configs[src_key]
                source = scope.get(pkg_name, scope.get("*"))
                if source:
                    for b_name, b_attrs in source.items():
                        pkg_overrides[b_name] = dict(b_attrs)

            # Workspace overrides first, then repo overrides take precedence.
            ws_key = "workspace:" + workspace_name
            _apply_scope_overrides(ws_key)

            repo_key = "repo:" + repo_name
            _apply_scope_overrides(repo_key)

            if pkg_overrides:
                sdist_repo_attrs["override_backend_configs"] = json.encode(pkg_overrides)

            # Invoke the generic sdist repo rule. Hooks will be applied dynamically inside it.
            pycross_sdist_repo(**sdist_repo_attrs)

        # Save per-repo data for workspace processing
        per_repo_data[repo_name] = struct(
            repo_map = repo_remote_files,
            sdist_map = sdist_map,
            lock_file = lock_file,
        )

    # Create workspace package repos and thin repos for all members.
    # Every repo belongs to a workspace (defaulting to its own name).
    workspace_groups = {}  # workspace_name -> [repo_name, ...]
    for repo_name, uname in workspace_memberships.items():
        workspace_groups.setdefault(uname, []).append(repo_name)

    # Annotation fields that affect pycross_wheel_library targets.
    _ANNOTATION_FIELDS = ["post_install_patches", "install_exclude_globs"]

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

        # Detect annotation conflicts by reading the resolved lock JSON
        # for each member and comparing annotation fields.
        member_packages = {}  # member -> {pkg_key -> pkg_data}
        for member in member_repos:
            lock_label = per_repo_data[member].lock_file
            member_lock = json.decode(module_ctx.read(lock_label))
            member_packages[member] = member_lock.get("packages", {})

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

        package_repo(
            name = workspace_repo_name,
            resolved_lock_file = per_repo_data[member_repos[0]].lock_file,
            repo_map = merged_repo_map,
            sdist_map = merged_sdist_map,
            backend_configs = backend_configs_json,
            member_lock_files = member_lock_files,
        )

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
                thin_repo_attrs["flags"] = repo_flags[member]
            if member in repo_constraint_values:
                thin_repo_attrs["constraint_values"] = repo_constraint_values[member]
            if member in repo_platforms:
                thin_repo_attrs["platform"] = repo_platforms[member]
            thin_repo_attrs["generate_root_aliases"] = True

            thin_package_repo(**thin_repo_attrs)

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(
            root_module_direct_deps = root_repos,
            root_module_direct_dev_deps = [],
            reproducible = True,
        )
    return module_ctx.extension_metadata(
        root_module_direct_deps = root_repos,
        root_module_direct_dev_deps = [],
    )

# Tag classes
_create_tag = tag_class(
    doc = "Create declared Pycross repos.",
    attrs = CREATE_REPOS_ATTRS,
)

lock_repos = module_extension(
    implementation = _lock_repos_impl,
    tag_classes = dict(
        create = _create_tag,
    ),
)
