"""Shared repo creation logic for lock extensions.

This module contains the create_repos() function that creates all Bazel repos
(remote files, sdist repos, package repos, thin repos) from resolved lock data.
Used by the per-format lock extensions (uv, pdm, poetry, pylock).
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@pycross_backends//:package_repo_dispatch.bzl", "PACKAGE_REPO_HOOKS", "PACKAGE_REPO_HOOK_SUBDIRS")
load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS", "OVERRIDE_FILES")
load("@pypackaging.bzl", "pypackaging")
load("@rules_pycross//pycross/private:override_helpers.bzl", "canonicalize_override_key", "merge_backend_overrides")
load("@rules_pycross//pycross/private:sdist_repo.bzl", "pycross_sdist_repo")
load(
    "//pycross/private:lock_contract.bzl",
    "VARIANTS_PACKAGE",
    "VARIANTS_STRING_FLAG_TARGET",
    "build_repo_name",
    "lock_sdist_deps_label",
    "pkgs_repo_name",
    "sdist_repo_name",
    "whldir_name",
)
load("//pycross/private:package_repo.bzl", "merge_workspace_locks", "package_repo", "slim_member_lock", "slim_workspace_lock")
load("//pycross/private:pypi_file.bzl", "pypi_file")
load("//pycross/private:thin_package_repo.bzl", "thin_package_repo")
load("//pycross/private:util.bzl", "TRUE_FLAG_VALUES", "parse_flag_arg", "parse_package_key", "sanitize_name", "sdist_builds_disallowed")
load("//pycross/private:variant_util.bzl", "split_variant_tokens", "variant_item_qname", "variant_set_suffix")
load("//pycross/private:wheel_file.bzl", "pycross_wheel_file")
load("//pycross/private/thin_repo:metadata.bzl", "LEGACY_CARGO_HOOK_BACKENDS")
load(":git_file.bzl", "pycross_git_file")

sdist_builds_disallowed_for_testing = sdist_builds_disallowed

def _normalize_override_name(pkg_name, backend_name, workspace_name):
    """Normalize an override tag name ("*", "name", or "name@version") into its storage key.

    The package name is canonicalized; the version is kept as written and must match
    the locked version string.
    """
    norm = canonicalize_override_key(pkg_name)
    if norm == None:
        fail("{} override '{}' (workspace '{}'): expected a package name, 'name@version', or '*'".format(
            backend_name,
            pkg_name,
            workspace_name,
        ))
    return norm

def _validate_override_packages(override_configs, workspaces, resolved_locks):
    """Fail on backend overrides that name a package (or version) not present in their workspace.

    Workspaces that are not known here are skipped: they may belong to a different
    lock extension (e.g. a pdm workspace when running the uv extension).
    """
    workspace_versions = {}  # workspace_name -> {normalized package name -> {version -> True}}
    for ws_name, ws in workspaces.items():
        names = workspace_versions.setdefault(ws_name, {})
        for repo in ws.repos:
            for key in resolved_locks[repo.name].get("packages", {}):
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

def _remote_file_dedup_key_and_repo_name(key, file, indexes):
    """Return (dedup_key, repo_name) for a remote file.

    Filename-only entries (no explicit `urls` and no per-package `index`) resolve
    against the workspace's `pypi_indexes`, so different index lists must not
    deduplicate to the same remote file repository across workspaces.
    """
    base_repo = "pypi_{}".format(sanitize_name(key.replace("/", "_")))
    if file.get("urls") or file.get("index") or not indexes:
        return ((key, ()), base_repo)
    index_tuple = tuple(indexes)
    idx_hash = "%x" % (hash("|".join(indexes)) & 0xffffffff)
    return ((key, index_tuple), "{}_idx_{}".format(base_repo, idx_hash))

def _create_remote_file_repo(remote_file_repo, file, indexes):
    is_wheel = file["name"].endswith(".whl")
    remote_file_label = (
        "@{}//:wheel".format(remote_file_repo) if is_wheel else "@{}//file:{}".format(remote_file_repo, file["name"])
    )

    urls = file.get("urls", [])
    if urls:
        if is_wheel:
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
        elif file["sha256"]:
            http_file(
                name = remote_file_repo,
                urls = urls,
                sha256 = file["sha256"],
                downloaded_file_path = file["name"],
            )
        else:
            pypi_file(
                name = remote_file_repo,
                urls = urls,
                filename = file["name"],
                sha256 = "",
            )
        return remote_file_label

    pypi_file_attrs = dict(
        name = remote_file_repo,
        package_name = file["package_name"],
        filename = file["name"],
        sha256 = file["sha256"],
    )

    # A per-package index recorded in the lock takes priority over
    # the workspace's pypi_indexes.
    if file.get("index"):
        pypi_file_attrs["indexes"] = [file["index"]]
    elif indexes:
        pypi_file_attrs["indexes"] = indexes
    if is_wheel:
        pycross_wheel_file(**pypi_file_attrs)
    else:
        pypi_file(**pypi_file_attrs)
    return remote_file_label

def _variants_flag_ref(label):
    """Return (repo name, flag) if label is a generated repo's `//_variants` or `//_variants:<flag>`, else None."""
    repo, sep, target = label.partition("//")
    if not sep:
        return None
    if target == VARIANTS_PACKAGE:
        flag = VARIANTS_STRING_FLAG_TARGET
    elif target.startswith(VARIANTS_PACKAGE + ":"):
        flag = target[len(VARIANTS_PACKAGE) + 1:]
    else:
        return None
    if repo.startswith("@@"):
        # Canonical name, e.g. `@@rules_pycross++uv+lock_all`: the repo name follows the last `+`.
        repo = repo[2:].rpartition("+")[2]
    elif repo.startswith("@"):
        repo = repo[1:]
    else:
        return None
    return (repo, flag)

def _compute_variant_pins(member, flags, settings, resolved_locks):
    """Compute the variants a repo's `flags`/`settings` select, for its transition's `p:<set>` entry in `//_lock:_state`.

    Args:
        member: The repo name.
        flags: The repo's flags (`--<label>[=<value>]` strings).
        settings: The repo's settings ({label: value}).
        resolved_locks: {repo name: resolved lock dict} for all repos of the workspace.

    Returns:
        {conflict set suffix: qualified name}.
    """

    # Last value wins per flag, across shorthand (`@repo//_variants`), explicit
    # (`@repo//_variants:_variants`), and canonical (`@@...`) spellings.
    values = {}  # (repo_name, flag_name) -> (label, value)
    for f in flags:
        parsed = parse_flag_arg(f)
        ref = _variants_flag_ref(parsed.label)
        if ref and ref[0] in resolved_locks:
            values[ref] = (parsed.label, parsed.value)
    for label, value in settings.items():
        ref = _variants_flag_ref(label)
        if ref and ref[0] in resolved_locks:
            values[ref] = (label, value)

    # repo -> {flag: [(set suffix, qname)]}, built lazily per referenced repo.
    index = {}
    selected = {}  # set suffix -> {qname: True}
    for (repo_name, flag_name), (label, value) in sorted(values.items()):
        if flag_name == VARIANTS_STRING_FLAG_TARGET:
            tokens = split_variant_tokens(value)
            if not tokens:
                continue
        else:
            if value not in TRUE_FLAG_VALUES:
                continue
            tokens = [flag_name]

        if repo_name not in index:
            repo_index = {}
            for variant_set in resolved_locks[repo_name].get("variants", []):
                qnames = [variant_item_qname(item) for item in variant_set["items"]]
                set_suffix = variant_set_suffix(qnames)
                for item in variant_set["items"]:
                    for flag in item.get("flags", []):
                        repo_index.setdefault(flag, []).append((set_suffix, variant_item_qname(item)))
            index[repo_name] = repo_index

        repo_index = index[repo_name]
        for token in tokens:
            if flag_name == VARIANTS_STRING_FLAG_TARGET and token not in repo_index:
                if repo_index:
                    detail = "expected one of: " + ", ".join(sorted(repo_index.keys()))
                else:
                    detail = "@{} has no variants".format(repo_name)
                fail("repo '{}': {} selects unknown variant '{}' ({})".format(
                    member,
                    label,
                    token,
                    detail,
                ))
            for set_suffix, qname in repo_index.get(token, []):
                selected.setdefault(set_suffix, {})[qname] = True

    pins = {}
    for set_suffix, qnames in selected.items():
        if len(qnames) > 1:
            fail("repo '{}': its flags/settings select conflicting variants {}. Select one of them.".format(
                member,
                " and ".join(sorted(qnames.keys())),
            ))
        pins[set_suffix] = qnames.keys()[0]
    return pins

# Visible for testing
compute_variant_pins_for_testing = _compute_variant_pins

def _known_packages_from_lock(resolved_lock):
    """Return sorted unique canonical package names pinned in a resolved lock.

    Using sorted deduplicated pin names (rather than raw versioned `packages` keys)
    keeps `pycross_sdist_repo.known_packages` invariant across version bumps, extra
    additions, and dict ordering changes, and matches the targets actually present
    in the thin build-tools repo. Note that adding or removing a pin in the build-tools
    repo (including any package in `<ws>__build`) still changes this list.
    """
    return sorted({
        pypackaging.utils.canonicalize_name(parse_package_key(pin_name).name): True
        for pin_name in resolved_lock.get("pins", {})
    }.keys())

def _extra_build_tool_names(extra_build_tools):
    """Return sorted unique canonical package names from resolved `extra_build_tools` keys.

    Stripping versions prevents unrelated tool version bumps from invalidating
    `pycross_sdist_repo` (which only uses the package name to construct `@<thin_repo>//<pkg>:pkg`).
    """
    return sorted({
        pypackaging.utils.canonicalize_name(parse_package_key(key).name): True
        for key in extra_build_tools
    }.keys())

def _filter_package_repo_overrides(ws_overrides, package_repo_hooks):
    """Retain only override entries whose backend has a registered package_repo hook."""
    if not ws_overrides or not package_repo_hooks:
        return {}
    filtered = {}
    for pkg_spec in sorted(ws_overrides.keys()):
        backends = ws_overrides[pkg_spec]
        kept = {
            backend_name: backends[backend_name]
            for backend_name in sorted(backends.keys())
            if backend_name in package_repo_hooks
        }
        if kept:
            filtered[pkg_spec] = kept
    return filtered

def _slim_thin_repo_overrides(ws_overrides, package_repo_hooks, hook_subdirs):
    """Retain only hook-subdir backend presence (`{backend: {}}`) for `thin_package_repo`.

    Thin repos only check whether a package has a matching hook-backed override
    to decide whether to emit `<subdir>/BUILD.bazel` aliases; stripping attribute
    values keeps thin repos invariant across override flag or attribute edits.
    """
    if not ws_overrides or not package_repo_hooks:
        return {}
    subdir_backends = {
        backend_name: True
        for backend_name in package_repo_hooks
        if hook_subdirs.get(backend_name) or (
            backend_name in LEGACY_CARGO_HOOK_BACKENDS and backend_name not in hook_subdirs
        )
    }
    if not subdir_backends:
        return {}
    slimmed = {}
    for pkg_spec in sorted(ws_overrides.keys()):
        kept = {
            backend_name: {}
            for backend_name in sorted(ws_overrides[pkg_spec].keys())
            if backend_name in subdir_backends
        }
        if kept:
            slimmed[pkg_spec] = kept
    return slimmed

def create_repos(
        module_ctx,
        workspaces,
        resolved_locks):
    """Create all Bazel repos from resolved lock data.

    Args:
        module_ctx: The module_ctx or similar context object (needs .path(), .read()).
        workspaces: Dict of workspace_name -> `struct(name, pypi_indexes, repos)` from `process_workspaces()`.
        resolved_locks: Dict of repo_name -> resolved lock dict.

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

    backend_names = sorted(BACKEND_CONFIGS.keys())

    known_packages_by_repo = {
        repo.name: _known_packages_from_lock(resolved_locks[repo.name])
        for ws in workspaces.values()
        for repo in ws.repos
    }

    _validate_override_packages(override_configs, workspaces, resolved_locks)

    for workspace_name, ws in workspaces.items():
        workspace_repo_name = pkgs_repo_name(workspace_name)
        indexes = ws.pypi_indexes
        merged_repo_map = {}
        merged_remote_files = {}

        for repo in ws.repos:
            resolved_lock = resolved_locks[repo.name]
            for key, file in resolved_lock.get("remote_files", {}).items():
                dedup_key, remote_file_repo = _remote_file_dedup_key_and_repo_name(key, file, indexes)
                if dedup_key not in all_remote_files:
                    all_remote_files[dedup_key] = _create_remote_file_repo(remote_file_repo, file, indexes)
                merged_repo_map[key] = all_remote_files[dedup_key]
                if key not in merged_remote_files:
                    merged_remote_files[key] = file

        skip_variant_members = [repo.name for repo in ws.repos if repo.is_auto_build_repo]
        merged_lock = merge_workspace_locks(
            [(repo.name, resolved_locks[repo.name]) for repo in ws.repos],
            skip_variant_members = skip_variant_members,
        )
        merged_packages = merged_lock["packages"]

        # Instantiate sdist repos once per workspace package requiring source builds.
        default_known_packages = known_packages_by_repo[ws.repos[0].name] if ws.repos else []
        for pkg_key, pkg in sorted(merged_packages.items()):
            if pkg.get("build_target") or sdist_builds_disallowed(pkg):
                continue

            sdist_file = pkg.get("sdist_file")
            if not sdist_file:
                continue

            sdist_file_key = sdist_file["key"]
            sdist_label = merged_repo_map[sdist_file_key]
            pkg_sdist_repo = sdist_repo_name(workspace_repo_name, pkg_key)

            sdist_deps = (
                [lock_sdist_deps_label(workspace_repo_name, pkg_key)] if pkg.get("marker_dependencies") else []
            )

            parts = parse_package_key(pkg_key)
            pkg_version = parts.version

            if pkg.get("build_tools_repo") and pkg["build_tools_repo"] not in known_packages_by_repo:
                fail("Package '{}' sets build_tools_repo = '{}', which is not a repo created by this extension. Known repos: {}".format(
                    pkg_key,
                    pkg["build_tools_repo"],
                    ", ".join(sorted(known_packages_by_repo.keys())),
                ))
            thin_repo = pkg.get("build_tools_repo") or build_repo_name(workspace_name)
            sdist_repo_attrs = {
                "name": pkg_sdist_repo,
                "sdist": sdist_label,
                "deps": sdist_deps,
                "known_packages": known_packages_by_repo.get(thin_repo, default_known_packages),
                "thin_repo": thin_repo,
                "whldir_name": whldir_name(pkg_key),
            }
            remote_file = merged_remote_files.get(sdist_file_key, {})
            is_git_sdist = bool(remote_file.get("urls") and remote_file["urls"][0].startswith("git+"))
            if remote_file.get("sha256") and not is_git_sdist:
                sdist_repo_attrs["sdist_sha256"] = remote_file["sha256"]
            if "extra_build_tools" in pkg and pkg["extra_build_tools"] != None:
                sdist_repo_attrs["extra_build_tools"] = _extra_build_tool_names(pkg["extra_build_tools"])

            if pkg.get("source_dir"):
                sdist_repo_attrs["source_dir"] = pkg["source_dir"]

            for attr_name in ("build_backend", "pre_build_patches", "site_hooks"):
                if attr_name in pkg and pkg[attr_name] != None:
                    sdist_repo_attrs[attr_name] = pkg[attr_name]

            pkg_name = pypackaging.utils.canonicalize_name(parts.name)
            if workspace_name in override_configs:
                pkg_overrides = merge_backend_overrides(override_configs[workspace_name], pkg_name, pkg_version)
                if pkg_overrides:
                    sdist_repo_attrs["override_backend_configs"] = json.encode(pkg_overrides)

            pycross_sdist_repo(**sdist_repo_attrs)

        # Compute filtered override configs for package and thin repo hooks.
        ws_overrides = override_configs.get(workspace_name)
        pkg_repo_overrides = _filter_package_repo_overrides(ws_overrides, PACKAGE_REPO_HOOKS)
        thin_repo_overrides = _slim_thin_repo_overrides(ws_overrides, PACKAGE_REPO_HOOKS, PACKAGE_REPO_HOOK_SUBDIRS)
        thin_repo_overrides_json = json.encode(thin_repo_overrides) if thin_repo_overrides else None

        package_repo_attrs = dict(
            name = workspace_repo_name,
            build_repo = build_repo_name(workspace_name),
            repo_map = merged_repo_map,
            backend_names = backend_names,
            lock_data = json.encode(slim_workspace_lock(merged_lock)),
        )
        if pkg_repo_overrides:
            package_repo_attrs["override_configs"] = json.encode(pkg_repo_overrides)
        package_repo(**package_repo_attrs)

        # Create thin repos for each workspace member.
        ws_resolved_locks = {repo.name: resolved_locks[repo.name] for repo in ws.repos}
        for repo in ws.repos:
            transition = repo.transition
            thin_repo_attrs = dict(
                name = repo.name,
                lock_data = json.encode(slim_member_lock(resolved_locks[repo.name], merged_packages)),
                workspace_repo = workspace_repo_name,
                member_name = repo.name,
                backend_names = backend_names,
            )
            if repo.is_auto_build_repo:
                thin_repo_attrs["expose_variant_flags"] = False

            if transition.flags:
                thin_repo_attrs["flags"] = transition.flags
            if transition.settings:
                thin_repo_attrs["settings"] = transition.settings
            pins = _compute_variant_pins(
                repo.name,
                transition.flags,
                transition.settings,
                ws_resolved_locks,
            )
            if pins:
                thin_repo_attrs["variant_pins"] = pins
            if transition.constraint_values:
                thin_repo_attrs["constraint_values"] = transition.constraint_values
            if transition.platform:
                thin_repo_attrs["platform"] = transition.platform

            if thin_repo_overrides_json:
                thin_repo_attrs["override_configs"] = thin_repo_overrides_json

            thin_package_repo(**thin_repo_attrs)

# Visible for testing
validate_override_packages_for_testing = _validate_override_packages
normalize_override_name_for_testing = _normalize_override_name
remote_file_dedup_key_and_repo_name_for_testing = _remote_file_dedup_key_and_repo_name
known_packages_from_lock_for_testing = _known_packages_from_lock
extra_build_tool_names_for_testing = _extra_build_tool_names
filter_package_repo_overrides_for_testing = _filter_package_repo_overrides
slim_thin_repo_overrides_for_testing = _slim_thin_repo_overrides
