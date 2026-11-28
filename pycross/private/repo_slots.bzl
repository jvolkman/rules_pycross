"""Deterministic, workspace-scoped, version-free repository slot naming.

Assigns stable fork slots (`""` for single-version packages, `"s0"`, `"s1"`, ...
for multi-version/multi-source packages) and maps wheels, sdist archives, and
sdist build repos to workspace-scoped, version-free Bazel repository names so
routine version bumps preserve the extension's repo mapping.
"""

load("@pypackaging.bzl", "pypackaging")
load(":util.bzl", "base_package_key", "hex_hash8", "parse_package_key", "sanitize_name", "underscore_name")

_MAX_TAG_ID_LEN = 48
_TRUNCATED_TAG_PREFIX_LEN = 39

def _version_sort_key(version):
    if not version:
        return ()
    return pypackaging.version.parse(version).key

def assign_fork_slots(packages):
    """Assign a deterministic version-free fork slot to every key in `packages`.

    Packages with a single locked `(version, tag)` get slot `""` so common
    packages have clean repo and target names. Packages with multiple versions
    or multiple `~<tag>` sources get `"s0"`, `"s1"`, ... ordered by
    `(tag, parsed_version, base_key)` so routine version bumps preserve slot
    order. Extra keys (`name[extra]@version[~tag]`) inherit their base key's
    fork slot.

    Args:
        packages: Dict mapping package key -> resolved package dict.

    Returns:
        Dict mapping every package key in `packages` to its fork slot string
        (`""`, `"s0"`, `"s1"`, ...).
    """
    bases_by_name = {}  # canonical_name -> {base_key: (tag, version)}
    for pkg_key in packages.keys():
        parts = parse_package_key(pkg_key)
        canon_name = pypackaging.utils.canonicalize_name(parts.name)
        bkey = base_package_key(pkg_key)
        bases_by_name.setdefault(canon_name, {})[bkey] = (parts.tag, parts.version)

    slot_by_base = {}
    for _canon_name, base_map in bases_by_name.items():
        if len(base_map) == 1:
            slot_by_base[base_map.keys()[0]] = ""
            continue
        ordered = sorted(
            base_map.items(),
            key = lambda item: (item[1][0], _version_sort_key(item[1][1]), item[0]),
        )
        for idx, (bkey, _tv) in enumerate(ordered):
            slot_by_base[bkey] = "s{}".format(idx)

    return {
        pkg_key: slot_by_base[base_package_key(pkg_key)]
        for pkg_key in packages.keys()
    }

def _wheel_raw_tag(filename):
    """Extract the version-free wheel compatibility tag string from a wheel filename."""
    lower = filename.lower()
    stem = filename[:-4] if lower.endswith(".whl") else filename
    parts = stem.split("-")
    if len(parts) == 5:
        return "{}-{}-{}".format(parts[2], parts[3], parts[4])
    if len(parts) == 6:
        return "{}__{}-{}-{}".format(parts[2], parts[3], parts[4], parts[5])
    return stem

def _disambiguate_repo_name(base_name, used_repo_names):
    if base_name not in used_repo_names:
        return base_name
    for idx in range(1, len(used_repo_names) + 2):
        cand = "{}__d{}".format(base_name, idx)
        if cand not in used_repo_names:
            return cand
    fail("Failed to assign unique repository name for {}".format(base_name))

def _slot_suffix(extra, slot):
    parts = []
    if extra:
        parts.append("e_" + underscore_name(extra))
    if slot:
        parts.append(slot)
    return ("__" + "__".join(parts)) if parts else ""

def sdist_slot_repo_name(workspace_name, pkg_key, slot = ""):
    """Return the workspace-scoped, version-free `pycross_sdist_repo` name for `pkg_key`.

    Uses `__` delimiters between canonical package name (`underscore_name`,
    which never contains `__`), optional extra (`__e_<extra>`), and optional
    fork slot (`__<slot>`) so cross-package collisions (e.g. `foo@s0` vs
    `foo-s0`) are impossible.

    Args:
        workspace_name: Workspace name.
        pkg_key: Package key in the lock.
        slot: Fork slot string (`""` or `"s0"`, `"s1"`, ...).

    Returns:
        Repository name string like `<ws>__sdist_<pkg>` or `<ws>__sdist_<pkg>__s0`.
    """
    parts = parse_package_key(pkg_key)
    return "{}__sdist_{}{}".format(
        workspace_name,
        underscore_name(parts.name),
        _slot_suffix(parts.extra, slot),
    )

def plan_workspace_remote_slots(workspace_name, merged_packages, merged_remote_files, fork_slots = None):
    """Map every remote file key in a workspace to a version-free repository name.

    Wheel repos use `<ws>__whl_<pkg>[__e_<extra>][__<slot>]__t_<tag_id>`, where
    `<tag_id>` is the sanitized PEP 427 `{build}__py-abi-plat` (hashed to keep
    names <= 48 chars and prevent sanitization collisions). Sdist archive repos
    use `<ws>__sdistfile_<pkg>[__e_<extra>][__<slot>]`. Using `__` field
    delimiters and distinct `__sdist_` / `__sdistfile_` / `__whl_` prefixes
    prevents any cross-package collision (such as `foo@s0` vs `foo-s0`,
    `foo` + `py2.py3-none-any` vs `foo-py2` + `py3-none-any`, or `file-foo`
    sdist repo vs `foo` sdist archive).

    Args:
        workspace_name: Workspace name.
        merged_packages: Merged workspace packages dict (`{pkg_key: pkg_dict}`).
        merged_remote_files: Workspace remote files dict (`{file_key: file_dict}`).
        fork_slots: Optional precomputed fork slots dict from `assign_fork_slots`.

    Returns:
        Dict mapping `file_key -> repo_name` for every entry in `merged_remote_files`.
    """
    slots = fork_slots if fork_slots != None else assign_fork_slots(merged_packages)
    file_key_to_repo = {}
    used_repo_names = {}

    # Order packages by version-free (canonical_name, slot, extra) so routine
    # version bumps never change iteration order.
    ordered_pkg_keys = sorted(
        merged_packages.keys(),
        key = lambda k: (
            pypackaging.utils.canonicalize_name(parse_package_key(k).name),
            slots.get(k, ""),
            parse_package_key(k).extra,
            k,
        ),
    )

    # 1. Wheel candidates: deterministic tag-based slots per (package, extra, fork_slot).
    for pkg_key in ordered_pkg_keys:
        pkg = merged_packages[pkg_key]
        candidates = pkg.get("wheel_candidates", [])
        if not candidates:
            continue
        parts = parse_package_key(pkg_key)
        us_pkg = underscore_name(parts.name)
        suffix = _slot_suffix(parts.extra, slots.get(pkg_key, ""))

        pending = []
        san_to_raws = {}
        for cand in candidates:
            file_key = cand.get("file_reference", {}).get("key")
            if not file_key or file_key not in merged_remote_files or file_key in file_key_to_repo:
                continue
            filename = merged_remote_files[file_key]["name"]
            raw_tag = _wheel_raw_tag(filename)
            san_tag = sanitize_name(raw_tag)
            san_to_raws.setdefault(san_tag, {})[raw_tag] = True
            pending.append((raw_tag, filename, file_key, san_tag))

        for raw_tag, _filename, file_key, san_tag in sorted(pending):
            if file_key in file_key_to_repo:
                continue
            if len(san_tag) > _MAX_TAG_ID_LEN or len(san_to_raws[san_tag]) > 1:
                tag_id = "{}_{}".format(san_tag[:_TRUNCATED_TAG_PREFIX_LEN], hex_hash8(raw_tag))
            else:
                tag_id = san_tag
            base_repo = "{}__whl_{}{}__t_{}".format(workspace_name, us_pkg, suffix, tag_id)
            repo_name = _disambiguate_repo_name(base_repo, used_repo_names)
            file_key_to_repo[file_key] = repo_name
            used_repo_names[repo_name] = True

    # 2. Sdist archive files: one version-free slot per (package, extra, fork_slot).
    for pkg_key in ordered_pkg_keys:
        sdist_file = merged_packages[pkg_key].get("sdist_file")
        if not sdist_file:
            continue
        file_key = sdist_file.get("key")
        if not file_key or file_key not in merged_remote_files or file_key in file_key_to_repo:
            continue
        parts = parse_package_key(pkg_key)
        us_pkg = underscore_name(parts.name)
        suffix = _slot_suffix(parts.extra, slots.get(pkg_key, ""))
        base_repo = "{}__sdistfile_{}{}".format(workspace_name, us_pkg, suffix)
        repo_name = _disambiguate_repo_name(base_repo, used_repo_names)
        file_key_to_repo[file_key] = repo_name
        used_repo_names[repo_name] = True

    # 3. Defensive fallback for any remote file not referenced by merged_packages.
    for file_key in sorted(merged_remote_files.keys()):
        if file_key in file_key_to_repo:
            continue
        filename = merged_remote_files[file_key]["name"]
        prefix = "whl" if filename.lower().endswith(".whl") else "sdistfile"
        base_repo = "{}__{}__unreferenced_{}".format(workspace_name, prefix, hex_hash8(file_key))
        repo_name = _disambiguate_repo_name(base_repo, used_repo_names)
        file_key_to_repo[file_key] = repo_name
        used_repo_names[repo_name] = True

    return file_key_to_repo
