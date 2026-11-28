"""Workspace control/state repository rule (`@<ws>__state`).

Holds workspace-wide, version-free control targets shared across all package
spokes and thin member repos:
- `BUILD.bazel`         - `_state`, `_variant_state`, `_resolver_*`, `_unselected_*`,
                          `_item_*`, and `is_<variant>` config_settings.
- `reset.bzl`           - Variant-reset transition and `pycross_resettable_wheel_library`
                          (emitted unconditionally whenever the workspace has variants).
- `_backend/<rule>.bzl` - Backend macros with pre-configured version-free tool defaults.
- Optional fallback `PACKAGE_REPO_HOOKS` with empty `package_repo_hook_subdir`.
"""

load("@pycross_backends//:package_repo_dispatch.bzl", "PACKAGE_REPO_HOOKS", "PACKAGE_REPO_HOOK_SUBDIRS")
load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS")
load("@pypackaging.bzl", "pypackaging")
load("//pycross/private/lock_render:reset_plan.bzl", "render_state_reset_bzl")
load("//pycross/private/thin_repo:metadata.bzl", "LEGACY_CARGO_HOOK_BACKENDS")
load(":build_text.bzl", "alias", "flag_setting")
load(
    ":lock_contract.bzl",
    "VARIANTS_PACKAGE",
    "VARIANT_STATE_TARGET",
    "constraint_setting_name",
    "cycle_node_key",
    "unselected_target_name",
    "variants_flag_label",
)
load(":override_helpers.bzl", "merge_backend_overrides")
load(":repo_slots.bzl", "assign_fork_slots")
load(":util.bzl", "base_package_key", "is_wheel_platform_specific", "parse_package_key", "underscore_name")
load(":variant_util.bzl", "variant_item_qname", "variant_set_suffix")

def _merge_package_entries(entries):
    merged = dict(entries[0])
    merged.pop("availability_markers", None)

    for pkg_data in entries[1:]:
        for field in ("site_paths", "bin_paths", "data_paths", "include_paths", "sdist_file"):
            if not merged.get(field) and pkg_data.get(field):
                merged[field] = pkg_data[field]

    # Merge marker_dependencies: union across workspace members, dedup by (key, marker).
    seen_marker_deps = {}  # (key, marker) -> entry
    for md in merged.get("marker_dependencies", []):
        marker = md.get("marker") or ""
        seen_marker_deps[(md["key"], marker)] = md
    for pkg_data in entries[1:]:
        for md in pkg_data.get("marker_dependencies", []):
            marker = md.get("marker") or ""
            dedupe_key = (md["key"], marker)
            if dedupe_key not in seen_marker_deps:
                seen_marker_deps[dedupe_key] = md
    merged["marker_dependencies"] = sorted(
        seen_marker_deps.values(),
        key = lambda m: (m["key"], m.get("marker") or ""),
    )

    # Merge wheel_candidates: union across members, dedup by filename.
    seen_candidates = {}  # filename -> entry
    for wc in merged.get("wheel_candidates", []):
        seen_candidates[wc["filename"]] = wc
    for pkg_data in entries[1:]:
        for wc in pkg_data.get("wheel_candidates", []):
            if wc["filename"] not in seen_candidates:
                seen_candidates[wc["filename"]] = wc
    merged["wheel_candidates"] = sorted(seen_candidates.values(), key = lambda w: w["filename"])

    return merged

def merge_workspace_locks(member_locks, skip_variant_members = None):
    """Merge per-member resolved locks into a single workspace lock payload.

    `availability_markers` and `resolution_marker_exprs` stay strictly per-member
    (rendered in each thin repo's `_markers/BUILD.bazel`) and are intentionally
    excluded from the merged workspace lock.

    Args:
        member_locks: Ordered list of `(member_name, lock_dict)` pairs or a dict
            `{member_name: lock_dict}` preserving workspace repo order.
        skip_variant_members: Optional collection of member repo names whose
            `_variants` flags should not be wired into workspace resolvers or
            `reset.bzl` (e.g. auto-generated `<ws>__build`).

    Returns:
        Dict with `"packages"` and optional non-empty `"cycle_groups"`,
        `"variant_items"`, `"variant_sets"`, and `"member_variant_flags"`.
    """
    items = member_locks.items() if type(member_locks) == "dict" else member_locks
    skip_set = {m: True for m in (skip_variant_members or [])}

    all_pkg_keys = {}  # pkg_key -> [pkg_data, ...]
    cycle_groups = {}  # group_name -> [pkg_key, ...]
    variant_items = {}  # qualified_name -> True (dedup across members)
    variant_sets = []  # list of {"qnames": [...], "flags": {flag label: [qnames]}, "member_flags": {member: {flag: [qnames]}}}
    variant_sets_seen = {}  # sorted qnames key -> variant set (dedup across members)
    member_variant_flags = {}  # member -> {flag_name: True} (all valid flags for that member)

    for member, member_lock in items:
        skip_member_variants = member in skip_set
        for variant_set in member_lock.get("variants", []):
            set_qnames = []
            set_flags = {}  # "@<member>//_variants:<flag>" -> [qnames]
            set_member_flags = {}  # flag -> [qnames]
            for item in variant_set["items"]:
                qname = variant_item_qname(item)
                variant_items[qname] = True
                set_qnames.append(qname)
                if not skip_member_variants:
                    for flag in item.get("flags", []):
                        set_flags.setdefault(variants_flag_label(member, flag), []).append(qname)
                        set_member_flags.setdefault(flag, []).append(qname)
                        member_variant_flags.setdefault(member, {})[flag] = True
            set_key = "|".join(sorted(set_qnames))
            if set_key not in variant_sets_seen:
                variant_sets_seen[set_key] = {"qnames": set_qnames, "flags": {}, "member_flags": {}}
                variant_sets.append(variant_sets_seen[set_key])
            variant_sets_seen[set_key]["flags"].update(set_flags)
            if set_member_flags:
                variant_sets_seen[set_key]["member_flags"][member] = set_member_flags

        for pkg_key, pkg_data in member_lock.get("packages", {}).items():
            all_pkg_keys.setdefault(pkg_key, []).append(pkg_data)

        # Merge cycle groups (union across members).
        for group_name, group_members in member_lock.get("cycle_groups", {}).items():
            if group_name in cycle_groups and sorted(cycle_groups[group_name]) != sorted(group_members):
                fail("Cycle group {} conflicts between workspace members ({} vs {})".format(group_name, cycle_groups[group_name], group_members))
            cycle_groups[group_name] = group_members

    packages = {}
    for pkg_key, entries in all_pkg_keys.items():
        if len(entries) <= 1:
            entry = dict(entries[0])
            entry.pop("availability_markers", None)
            packages[pkg_key] = entry
        else:
            packages[pkg_key] = _merge_package_entries(entries)

    result = {"packages": packages}
    if cycle_groups:
        result["cycle_groups"] = cycle_groups
    if variant_items:
        result["variant_items"] = variant_items
    if variant_sets:
        result["variant_sets"] = variant_sets
    if member_variant_flags:
        result["member_variant_flags"] = member_variant_flags
    return result

def spoke_hook_backend_subdirs(hooks = None, hook_subdirs = None):
    """Map each spoke-scoped hook backend name to its target subdirectory name.

    Args:
        hooks: Optional dict of `{backend_name: hook_fn}` (defaults to `PACKAGE_REPO_HOOKS`).
        hook_subdirs: Optional dict of `{backend_name: subdir}` (defaults to `PACKAGE_REPO_HOOK_SUBDIRS`).

    Returns:
        Dict mapping spoke-scoped `backend_name -> subdir` (e.g. `{"maturin_build": "_cargo"}`).
    """
    hooks = PACKAGE_REPO_HOOKS if hooks == None else hooks
    subdirs = PACKAGE_REPO_HOOK_SUBDIRS if hook_subdirs == None else hook_subdirs
    result = {}
    for backend_name in sorted(hooks.keys()):
        subdir = subdirs.get(backend_name)
        if subdir:
            result[backend_name] = subdir
        elif backend_name in LEGACY_CARGO_HOOK_BACKENDS and backend_name not in subdirs:
            result[backend_name] = "_cargo"
    return result

def slim_member_lock(
        member_lock,
        merged_packages,
        fork_slots = None,
        ws_overrides = None,
        spoke_hook_subdirs = None):
    """Build the minimal, version-free per-member manifest needed by `thin_package_repo`.

    Rewrites every pin target key to a version-free `slot_key` (`foo`, `foo@s0`,
    `foo[extra]@s1`), keeps only pinned keys and their base packages, filters
    `resolution_marker_exprs` to member-referenced constraints, and precomputes
    version-free `hook_subdirs` from workspace overrides so routine version bumps
    leave the member repo's inputs byte-identical.

    Args:
        member_lock: Resolved lock dict for one workspace member.
        merged_packages: Merged `"packages"` dict from `merge_workspace_locks`.
        fork_slots: Optional precomputed fork slots dict from `assign_fork_slots`.
        ws_overrides: Optional workspace override configs dict (`{override_key: {backend: attrs}}`).
        spoke_hook_subdirs: Optional `{backend_name: subdir}` dict from `spoke_hook_backend_subdirs`.

    Returns:
        Version-free slimmed dict suitable for `json.encode()` into `thin_package_repo.lock_data`.
    """
    slots = fork_slots if fork_slots != None else assign_fork_slots(merged_packages)
    raw_pins = member_lock.get("pins", {})
    pins = {}
    kept_pkg_keys = {}
    for pin_name in sorted(raw_pins.keys()):
        pin_val = raw_pins[pin_name]
        if type(pin_val) == "string":
            kept_pkg_keys[pin_val] = True
            kept_pkg_keys[base_package_key(pin_val)] = True
            pins[pin_name] = cycle_node_key(pin_val, slots.get(pin_val, ""))
        else:
            mapped = {}
            for cname in sorted(pin_val.keys()):
                pkg_key = pin_val[cname]
                kept_pkg_keys[pkg_key] = True
                kept_pkg_keys[base_package_key(pkg_key)] = True
                mapped[cname] = cycle_node_key(pkg_key, slots.get(pkg_key, ""))
            pins[pin_name] = mapped

    member_packages = member_lock.get("packages", {})
    slim_packages = {}
    for pkg_key in sorted(kept_pkg_keys.keys()):
        member_pkg = member_packages.get(pkg_key, {})
        merged_pkg = merged_packages.get(pkg_key, member_pkg)
        parts = parse_package_key(pkg_key)
        slot_key = cycle_node_key(pkg_key, slots.get(pkg_key, ""))
        slim_pkg = {}
        if is_wheel_platform_specific(merged_pkg):
            slim_pkg["wheel_platform_specific"] = True
        if parts.extra and merged_pkg.get("wheel_candidates"):
            slim_pkg["extras_proxy"] = False
        if merged_pkg.get("sdist_file"):
            slim_pkg["sdist_file"] = True
        if member_pkg.get("availability_markers"):
            slim_pkg["availability_markers"] = member_pkg["availability_markers"]
        if not parts.extra and merged_pkg.get("sdist_file") and ws_overrides and spoke_hook_subdirs:
            pkg_name = pypackaging.utils.canonicalize_name(parts.name)
            matched_backends = merge_backend_overrides(ws_overrides, pkg_name, parts.version)
            matched_subdirs = sorted({
                spoke_hook_subdirs[b]: True
                for b in matched_backends
                if b in spoke_hook_subdirs
            }.keys())
            if matched_subdirs:
                slim_pkg["hook_subdirs"] = matched_subdirs
        slim_packages[slot_key] = slim_pkg

    slim = {
        "packages": slim_packages,
        "pins": pins,
    }
    raw_res_exprs = member_lock.get("resolution_marker_exprs")
    if raw_res_exprs:
        referenced = {}
        for pin_val in raw_pins.values():
            if type(pin_val) != "dict":
                continue
            for cname in pin_val.keys():
                if cname and cname in raw_res_exprs:
                    referenced[cname] = True
                    entry = raw_res_exprs[cname]
                    if type(entry) == "dict" and entry.get("marker") in raw_res_exprs:
                        referenced[entry["marker"]] = True
        if referenced:
            slim["resolution_marker_exprs"] = {c: raw_res_exprs[c] for c in sorted(referenced.keys())}
    for key in ("variants", "testonly_pins"):
        val = member_lock.get(key)
        if val:
            slim[key] = val
    return slim

def normalize_workspace_variants(variant_sets):
    """Normalize deduplicated workspace variant sets once for state rendering.

    Computes sorted set suffixes, consolidated bool/string flag maps, and
    resolver/item lookups in a single pass.

    Args:
        variant_sets: List of deduplicated workspace variant set dicts from
            `merge_workspace_locks`.

    Returns:
        Struct with `sets_by_suffix`, `all_flags`, `member_flag_maps`, and
        `qname_to_resolvers`.
    """
    sets_by_suffix = {}  # set_suffix -> sorted [qname, ...]
    all_flags = {}  # flag_label -> [unique qnames]
    member_flag_maps = {}  # member -> {flag -> [unique qnames]}
    qname_to_resolvers = {}  # qname -> [resolver_name, ...]
    for vset in variant_sets:
        sorted_qnames = sorted(vset["qnames"])
        set_suffix = variant_set_suffix(sorted_qnames)
        sets_by_suffix[set_suffix] = sorted_qnames
        resolver_name = "_resolver_" + set_suffix
        for qname in sorted_qnames:
            resolvers = qname_to_resolvers.setdefault(qname, [])
            if resolver_name not in resolvers:
                resolvers.append(resolver_name)
        for flag_label, qnames in vset["flags"].items():
            dest = all_flags.setdefault(flag_label, [])
            for q in qnames:
                if q not in dest:
                    dest.append(q)
        for member, fmap in vset.get("member_flags", {}).items():
            m_dest = member_flag_maps.setdefault(member, {})
            for flag, qnames in fmap.items():
                dest = m_dest.setdefault(flag, [])
                for q in qnames:
                    if q not in dest:
                        dest.append(q)
    return struct(
        sets_by_suffix = sets_by_suffix,
        all_flags = all_flags,
        member_flag_maps = member_flag_maps,
        qname_to_resolvers = qname_to_resolvers,
    )

def backend_tool_deps_labels(tool_packages, known_base_packages, build_repo):
    """Resolve backend `tool_packages` to `@<build_repo>//<pkg>:pkg` labels.

    Args:
        tool_packages: Iterable of package names requested by the backend config.
        known_base_packages: Iterable (or dict) of canonical base package names
            present in the workspace.
        build_repo: Apparent name of the workspace's build-tools thin repo.

    Returns:
        List of `@<build_repo>//<pkg>:pkg` label strings.
    """
    known = (
        known_base_packages if type(known_base_packages) == "dict" else {
            pypackaging.utils.canonicalize_name(p): True
            for p in known_base_packages
        }
    )
    labels = []
    for pkg in tool_packages:
        if pypackaging.utils.canonicalize_name(pkg) in known:
            labels.append("@{}//{}:pkg".format(build_repo, underscore_name(pkg)))
    return labels

def is_spoke_hook_backend(backend_name, hook_subdirs = None):
    """Return True if `backend_name` declares a spoke-scoped hook subdirectory.

    Args:
        backend_name: Registered build backend rule name.
        hook_subdirs: Optional dict overriding `PACKAGE_REPO_HOOK_SUBDIRS`.

    Returns:
        Bool indicating whether this backend's hook runs inside each spoke repo.
    """
    subdirs = PACKAGE_REPO_HOOK_SUBDIRS if hook_subdirs == None else hook_subdirs
    if subdirs.get(backend_name):
        return True
    return backend_name in LEGACY_CARGO_HOOK_BACKENDS and backend_name not in subdirs

def run_package_repo_hooks(hooks, packages_info, override_configs):
    """Run registered package_repo hooks, deduplicating backends that share a hook function.

    Args:
        hooks: Dict mapping backend_name -> hook_fn.
        packages_info: Dict of normalized_name -> `{"versions": [struct(...)]}`.
        override_configs: Dict of pkg_spec -> `{backend_name: backend_attrs}`.

    Returns:
        Dict mapping relative output path (`"dir/filename"`) -> file content.
    """
    grouped_hooks = []  # list of (hook_fn, [backend_names])
    for backend_name, hook_fn in sorted(hooks.items()):
        found = False
        for idx, entry in enumerate(grouped_hooks):
            if entry[0] == hook_fn:
                grouped_hooks[idx] = (entry[0], entry[1] + [backend_name])
                found = True
                break
        if not found:
            grouped_hooks.append((hook_fn, [backend_name]))

    hook_files = {}  # "dir/filename" -> [content, ...]
    for hook_fn, backend_names in grouped_hooks:
        backend_overrides = {}
        for pkg_spec, backends in override_configs.items():
            merged_attrs = {}
            matched = False
            for backend_name in backend_names:
                if backend_name in backends:
                    matched = True
                    merged_attrs.update(backends[backend_name])
            if matched:
                backend_overrides[pkg_spec] = merged_attrs

        if not backend_overrides:
            continue

        results = hook_fn(packages_info, backend_overrides)
        for result in results:
            for filename, content in result.files.items():
                path = "{}/{}".format(result.dir, filename)
                hook_files.setdefault(path, []).append(content)

    return {path: "\n".join(contents) for path, contents in hook_files.items()}

def render_state_build(variant_items, normalized_variants, member_variant_flags, qname_to_resolvers = None):
    """Render root `BUILD.bazel` for a workspace `@<ws>__state` repository.

    Args:
        variant_items: Dict of active variant qualified names (`{qname: True}`).
        normalized_variants: Struct from `normalize_workspace_variants`.
        member_variant_flags: Dict mapping member repo name -> `{flag_name: True}`.
        qname_to_resolvers: Optional override map `{qname: [resolver_name, ...]}`.

    Returns:
        Generated `BUILD.bazel` string.
    """
    qname_to_resolvers = qname_to_resolvers if qname_to_resolvers != None else normalized_variants.qname_to_resolvers
    lines = []

    sets_by_suffix = normalized_variants.sets_by_suffix
    needs_item_projection = any([len(resolvers) > 1 for resolvers in qname_to_resolvers.values()])
    if variant_items:
        lines.append('load("@bazel_skylib//rules:common_settings.bzl", "string_flag")')
        if needs_item_projection:
            lines.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_item_projection", "variant_set_projection", "variant_state")')
        else:
            lines.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_set_projection", "variant_state")')
        lines.append("")

    lines.extend([
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])

    if sets_by_suffix:
        lines.extend([
            'exports_files(["reset.bzl"])',
            "",
            "string_flag(",
            '    name = "{}",'.format(VARIANT_STATE_TARGET),
            '    build_setting_default = "",',
            ")",
            "",
            "variant_state(",
            '    name = "_variant_state",',
            '    state = ":{}",'.format(VARIANT_STATE_TARGET),
            "    sets = {",
        ])
        for set_suffix, qnames in sorted(sets_by_suffix.items()):
            lines.append('        "{}": {},'.format(set_suffix, json.encode(qnames)))
        lines.extend([
            "    },",
            "    flags = {",
        ])
        for flag_label, qnames in sorted(normalized_variants.all_flags.items()):
            lines.append('        "{}": "{}|{}",'.format(flag_label, flag_label, " ".join(qnames)))
        lines.append("    },")
        if member_variant_flags:
            lines.append("    string_flags = {")
            for member in sorted(member_variant_flags.keys()):
                flag_map = normalized_variants.member_flag_maps.get(member, {})
                spec = {
                    "display": "@{}//{}".format(member, VARIANTS_PACKAGE),
                    "map": {k: v for k, v in sorted(flag_map.items())},
                }
                lines.append('        "{}": {},'.format(variants_flag_label(member), json.encode(json.encode(spec))))
            lines.append("    },")
        lines.extend([
            ")",
            "",
        ])

        for set_suffix in sorted(sets_by_suffix.keys()):
            resolver_name = "_resolver_" + set_suffix
            lines.extend([
                "variant_set_projection(",
                '    name = "{}",'.format(resolver_name),
                '    state = ":_variant_state",',
                '    set_key = "{}",'.format(set_suffix),
                ")",
                "",
            ])
            lines.extend(flag_setting(unselected_target_name(set_suffix), ":" + resolver_name, "", inline = True))

    for qname in sorted(variant_items.keys()):
        resolvers = qname_to_resolvers.get(qname, [])
        if len(resolvers) == 1:
            lines.extend(flag_setting(constraint_setting_name(qname), ":" + resolvers[0], qname, inline = True))
        elif len(resolvers) > 1:
            item_proj_name = "_item_" + qname
            lines.extend([
                "variant_item_projection(",
                '    name = "{}",'.format(item_proj_name),
                '    state = ":_variant_state",',
                '    item = "{}",'.format(qname),
                ")",
                "",
            ])
            lines.extend(flag_setting(constraint_setting_name(qname), ":" + item_proj_name, "true", inline = True))

    return "\n".join(lines)

def render_backend_macro_bzl(macro_name, rule_bzl, tool_deps_labels):
    """Render `_backend/<macro_name>.bzl` with pre-configured tool defaults.

    Args:
        macro_name: Backend rule/macro name.
        rule_bzl: Label string of the backend rule `.bzl` file.
        tool_deps_labels: Resolved list of `@<build_repo>//<pkg>:pkg` labels.

    Returns:
        Generated `.bzl` file content string.
    """
    lines = [
        '"""Backend macro with pre-configured tool defaults for this lock repo."""',
        "",
        'load("{rule_bzl}", _{macro_name} = "{macro_name}")'.format(
            rule_bzl = rule_bzl,
            macro_name = macro_name,
        ),
        "",
        "def {macro_name}(name, **kwargs):".format(macro_name = macro_name),
    ]
    if tool_deps_labels:
        lines.append('    if "tool_deps" not in kwargs:')
        lines.append('        kwargs["tool_deps"] = [')
        for label in tool_deps_labels:
            lines.append('            Label("{}"),'.format(label))
        lines.append("        ]")
    lines.extend([
        "    _{macro_name}(name = name, **kwargs)".format(macro_name = macro_name),
        "",
    ])
    return "\n".join(lines)

def _state_repo_impl(rctx):
    state_data = json.decode(rctx.attr.state_data) if rctx.attr.state_data else {}
    variant_items = state_data.get("variant_items", {})
    variant_sets = state_data.get("variant_sets", [])
    member_variant_flags = state_data.get("member_variant_flags", {})
    normalized_variants = normalize_workspace_variants(variant_sets)

    rctx.file("REPO.bazel", "")
    rctx.file(
        "BUILD.bazel",
        render_state_build(variant_items, normalized_variants, member_variant_flags),
    )

    if normalized_variants.sets_by_suffix:
        rctx.file(
            "reset.bzl",
            render_state_reset_bzl(
                normalized_variants.all_flags.keys(),
                string_flag_labels = [variants_flag_label(m) for m in sorted(member_variant_flags.keys())],
            ),
        )

    # _backend/ macros (version-free: depend only on canonical base package names).
    rctx.file("_backend/BUILD.bazel", "exports_files(glob(['*.bzl']))\n")
    known_base_set = {p: True for p in rctx.attr.known_base_packages}
    build_repo = rctx.attr.build_repo
    for macro_name in sorted(rctx.attr.backend_names):
        config = BACKEND_CONFIGS.get(macro_name)
        if config == None:
            fail("Unknown build backend '{}' in state_repo '{}'. Registered backends: {}".format(
                macro_name,
                rctx.name,
                ", ".join(sorted(BACKEND_CONFIGS.keys())),
            ))
        tool_deps_labels = backend_tool_deps_labels(config["tool_packages"], known_base_set, build_repo)
        rctx.file(
            "_backend/{}.bzl".format(macro_name),
            render_backend_macro_bzl(macro_name, config["rule_bzl"], tool_deps_labels),
        )

    # Fallback hooks that register an empty package_repo_hook_subdir.
    fallback_hooks = {
        b: fn
        for b, fn in PACKAGE_REPO_HOOKS.items()
        if not is_spoke_hook_backend(b)
    }
    if fallback_hooks and rctx.attr.override_configs and rctx.attr.fallback_hook_packages:
        override_configs = json.decode(rctx.attr.override_configs)
        raw_pkgs_info = json.decode(rctx.attr.fallback_hook_packages)
        packages_info = {
            norm_name: {
                "versions": [
                    struct(
                        version = v["version"],
                        package_key = v["package_key"],
                        has_sdist = v["has_sdist"],
                    )
                    for v in entry["versions"]
                ],
            }
            for norm_name, entry in raw_pkgs_info.items()
        }
        hook_files = run_package_repo_hooks(fallback_hooks, packages_info, override_configs)
        for path, content in hook_files.items():
            rctx.file(path, content)
        if hook_files:
            sdist_lines = ['package(default_visibility = ["//visibility:public"])', ""]
            has_sdist_shim = False
            for norm_name in sorted(raw_pkgs_info.keys()):
                for v in raw_pkgs_info[norm_name]["versions"]:
                    if v.get("sdist_label"):
                        sdist_lines.extend(alias(v["package_key"], v["sdist_label"]))
                        has_sdist_shim = True
            if has_sdist_shim:
                rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_lines) + "\n")

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

state_repo = repository_rule(
    implementation = _state_repo_impl,
    attrs = {
        "build_repo": attr.string(
            doc = "Name of the default build tools thin repo (e.g. 'uv__build').",
            mandatory = True,
        ),
        "backend_names": attr.string_list(
            doc = "Registered backend rule names to emit `_backend/<name>.bzl` macros for.",
        ),
        "known_base_packages": attr.string_list(
            doc = "Sorted canonical base package names present in the workspace (version-free).",
        ),
        "state_data": attr.string(
            doc = "JSON-encoded workspace variant metadata (`variant_items`, `variant_sets`, `member_variant_flags`).",
        ),
        "override_configs": attr.string(
            doc = "Optional JSON-encoded override configs for fallback hooks with empty package_repo_hook_subdir.",
        ),
        "fallback_hook_packages": attr.string(
            doc = "Optional JSON-encoded packages_info for fallback hooks with empty package_repo_hook_subdir.",
        ),
    },
)
