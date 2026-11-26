"""A pure-Starlark workspace repository rule that wraps a pycross lock structure.

A workspace repo is the shared backing store for one or more user-facing
"thin" package repos. It contains the actual pycross_wheel_library targets
and artifact references, while thin repos provide pin aliases and
user-facing convenience targets.

The file structure is as follows:
- REPO.bazel               - The repository root marker.
- BUILD.bazel              - Minimal root build file.
- _lock/lock.bzl           - Generated Starlark with all package targets.
- _lock/BUILD.bazel        - Loads lock.bzl and calls targets().
- _wheel/BUILD.bazel       - Versioned wheel aliases.
- _sdist/BUILD.bazel       - Versioned sdist aliases.
- _backend/<rule>.bzl      - Backend macros with pre-configured tool deps.
"""

load("@pycross_backends//:package_repo_dispatch.bzl", "PACKAGE_REPO_HOOKS")
load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS")
load("@pypackaging.bzl", "pypackaging")
load(":build_text.bzl", "alias", "flag_setting")
load(
    ":lock_contract.bzl",
    "VARIANTS_PACKAGE",
    "VARIANT_STATE_TARGET",
    "constraint_setting_name",
    "local_lock_target_label",
    "sdist_target_name",
    "unselected_target_name",
    "variants_flag_label",
    "wheel_target_name",
    "whldir_name",
)
load(":resolved_lock_renderer.bzl", "render_lock_bzl_with_meta", "render_reset_bzl")
load(":util.bzl", "format_package_key", "is_wheel_platform_specific", "parse_package_key", "underscore_name")
load(":variant_util.bzl", "variant_item_qname", "variant_set_suffix")

def _normalize_name(name):
    return pypackaging.utils.canonicalize_name(name)

def _backend_tool_deps_labels(tool_packages, packages, build_repo):
    """Resolve backend tool_packages to `@<build_repo>//<pkg>:pkg` labels for packages present in `packages`.

    Ignores extra keys (`pkg[extra]@version`).
    Pointing at `@<build_repo>//<pkg>:pkg` ensures the macro default follows
    resolution-marker forks and variants via the build thin repo's `select()`.
    """
    known_base_packages = {}
    for k in packages.keys():
        parts = parse_package_key(k)
        if parts.extra:
            continue
        known_base_packages[_normalize_name(parts.name)] = True

    labels = []
    for pkg in tool_packages:
        if _normalize_name(pkg) in known_base_packages:
            labels.append("@{}//{}:pkg".format(build_repo, underscore_name(pkg)))
    return labels

# Visible for testing
backend_tool_deps_labels_for_testing = _backend_tool_deps_labels

def _merge_package_entries(entries):
    merged = dict(entries[0])

    for pkg_data in entries[1:]:
        for field in ("site_paths", "bin_paths", "data_paths", "include_paths", "sdist_file"):
            if not merged.get(field) and pkg_data.get(field):
                merged[field] = pkg_data[field]

    # Merge marker_dependencies: union across workspace members, dedup by (key, marker).
    seen_marker_deps = {}  # (key, marker) -> entry
    for md in merged.get("marker_dependencies", []):
        seen_marker_deps[(md["key"], md.get("marker"))] = md
    for pkg_data in entries[1:]:
        for md in pkg_data.get("marker_dependencies", []):
            dedupe_key = (md["key"], md.get("marker"))
            if dedupe_key not in seen_marker_deps:
                seen_marker_deps[dedupe_key] = md
    merged["marker_dependencies"] = sorted(seen_marker_deps.values(), key = lambda m: (m["key"], m.get("marker", "")))

    # Merge wheel_candidates: union across members, dedup by filename.
    seen_candidates = {}  # filename -> entry
    for wc in merged.get("wheel_candidates", []):
        seen_candidates[wc["filename"]] = wc
    for pkg_data in entries[1:]:
        for wc in pkg_data.get("wheel_candidates", []):
            if wc["filename"] not in seen_candidates:
                seen_candidates[wc["filename"]] = wc
    merged["wheel_candidates"] = sorted(seen_candidates.values(), key = lambda w: w["filename"])

    # Merge availability_markers: union across workspace members so _lock emits
    # marker evaluators for every member's conditional root dependencies.
    seen_avail = {m: True for m in merged.get("availability_markers", [])}
    for pkg_data in entries[1:]:
        for m in pkg_data.get("availability_markers", []):
            seen_avail[m] = True
    if seen_avail:
        merged["availability_markers"] = sorted(seen_avail.keys())

    return merged

def merge_workspace_locks(member_locks, skip_variant_members = None):
    """Merge per-member resolved locks into a single workspace lock payload.

    Args:
        member_locks: Ordered list of `(member_name, lock_dict)` pairs or a dict
            `{member_name: lock_dict}` preserving workspace repo order.
        skip_variant_members: Optional collection of member repo names whose
            `_variants` flags should not be wired into workspace resolvers or
            `reset.bzl` (e.g. auto-generated `<ws>__build`).

    Returns:
        Dict with `"packages"` and optional non-empty `"cycle_groups"`,
        `"resolution_marker_exprs"`, `"variant_items"`, `"variant_sets"`, and
        `"member_variant_flags"`.
    """
    items = member_locks.items() if type(member_locks) == "dict" else member_locks
    skip_set = {m: True for m in (skip_variant_members or [])}

    all_pkg_keys = {}  # pkg_key -> [pkg_data, ...]
    cycle_groups = {}  # group_name -> [pkg_key, ...]
    resolution_marker_exprs = {}  # constraint_name -> marker_expr or compound dict
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

        # Merge resolution-marker expressions (union across members).
        for cname, expr in member_lock.get("resolution_marker_exprs", {}).items():
            if cname in resolution_marker_exprs and resolution_marker_exprs[cname] != expr:
                fail("Resolution marker '{}' conflicts between workspace members ({} vs {})".format(cname, resolution_marker_exprs[cname], expr))
            resolution_marker_exprs[cname] = expr

    packages = {}
    for pkg_key, entries in all_pkg_keys.items():
        if len(entries) <= 1:
            packages[pkg_key] = dict(entries[0])
        else:
            packages[pkg_key] = _merge_package_entries(entries)

    result = {"packages": packages}
    if cycle_groups:
        result["cycle_groups"] = cycle_groups
    if resolution_marker_exprs:
        result["resolution_marker_exprs"] = resolution_marker_exprs
    if variant_items:
        result["variant_items"] = variant_items
    if variant_sets:
        result["variant_sets"] = variant_sets
    if member_variant_flags:
        result["member_variant_flags"] = member_variant_flags
    return result

# Package fields read by package_repo.bzl and lock_render/*.bzl.
# Kept only when non-empty/truthy; `build_mode` is handled separately so its
# default ("auto") is omitted while explicit overrides ("never"/"always") remain.
_PACKAGE_REPO_PKG_FIELDS = (
    "marker_dependencies",
    "wheel_candidates",
    "sdist_file",
    "availability_markers",
    "cycle_group",
    "build_target",
    "site_paths",
    "bin_paths",
    "data_paths",
    "include_paths",
    "install_exclude_globs",
    "post_install_patches",
    "wheel_library_tags",
    "precompile",
)

def slim_workspace_lock(merged_lock):
    """Build the minimal merged workspace lock payload needed by `package_repo`.

    Drops sdist-repo-only fields (`extra_build_tools`, `build_backend`,
    `build_tools_repo`, `pre_build_patches`, `site_hooks`, `source_dir`),
    redundant fields (`name`, `version`), and default-empty values so changes
    that only affect `pycross_sdist_repo` do not invalidate `package_repo`.

    Args:
        merged_lock: Merged workspace lock dict from `merge_workspace_locks()`.

    Returns:
        Slimmed dict suitable for `json.encode()` into `package_repo.lock_data`.
    """
    slim_packages = {}
    for pkg_key, pkg in merged_lock.get("packages", {}).items():
        slim_pkg = {}
        for field in _PACKAGE_REPO_PKG_FIELDS:
            val = pkg.get(field)
            if val:
                slim_pkg[field] = val
        build_mode = pkg.get("build_mode")
        if build_mode and build_mode != "auto":
            slim_pkg["build_mode"] = build_mode
        slim_packages[pkg_key] = slim_pkg

    slim = dict(merged_lock)
    slim["packages"] = slim_packages
    return slim

def slim_member_lock(member_lock, merged_packages):
    """Build the minimal per-member manifest needed by `thin_package_repo`.

    Keeps the exact package keys present in `member_lock` (preserving
    `base_packages_with_extras` per member) while resolving shared wheel/sdist
    and cycle metadata against `merged_packages` so thin repos and
    `package_repo` never disagree. `availability_markers` remain strictly
    per-member.

    Args:
        member_lock: Resolved lock dict for one workspace member.
        merged_packages: Merged `"packages"` dict from `merge_workspace_locks`.

    Returns:
        Slimmed dict suitable for `json.encode()` into `thin_package_repo.lock_data`.
    """
    slim_packages = {}
    for pkg_key, member_pkg in member_lock.get("packages", {}).items():
        merged_pkg = merged_packages.get(pkg_key, member_pkg)
        slim_pkg = {}
        if is_wheel_platform_specific(merged_pkg):
            slim_pkg["wheel_platform_specific"] = True
        if parse_package_key(pkg_key).extra and merged_pkg.get("wheel_candidates"):
            slim_pkg["extras_proxy"] = False
        if merged_pkg.get("sdist_file"):
            slim_pkg["sdist_file"] = True
        if merged_pkg.get("cycle_group"):
            slim_pkg["cycle_group"] = merged_pkg["cycle_group"]
        if member_pkg.get("availability_markers"):
            slim_pkg["availability_markers"] = member_pkg["availability_markers"]
        slim_packages[pkg_key] = slim_pkg

    slim = {
        "packages": slim_packages,
        "pins": member_lock.get("pins", {}),
    }
    for key in ("variants", "resolution_marker_exprs", "testonly_pins"):
        val = member_lock.get(key)
        if val:
            slim[key] = val
    return slim

def _normalize_workspace_variants(variant_sets):
    """Normalize deduplicated workspace variant sets once for lock rendering.

    Computes sorted set suffixes, consolidated bool/string flag maps, and
    resolver/item lookups in a single pass.
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

def _render_lock_build(variant_items, normalized_variants, member_variant_flags, qname_to_resolvers = None):
    """Render `_lock/BUILD.bazel` for a workspace package repo."""
    qname_to_resolvers = qname_to_resolvers if qname_to_resolvers != None else normalized_variants.qname_to_resolvers
    lock_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'load(":lock.bzl", "targets")',
        "",
    ]

    needs_item_projection = any([len(resolvers) > 1 for resolvers in qname_to_resolvers.values()])
    if variant_items:
        lock_build_lines.append('load("@bazel_skylib//rules:common_settings.bzl", "string_flag")')
        if needs_item_projection:
            lock_build_lines.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_item_projection", "variant_set_projection", "variant_state")')
        else:
            lock_build_lines.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_set_projection", "variant_state")')
        lock_build_lines.append("")

    lock_build_lines.extend([
        "targets()",
        "",
    ])

    sets_by_suffix = normalized_variants.sets_by_suffix
    if sets_by_suffix:
        # There are no static defaults here: thin repos select variants. Their
        # `_variants` bool_flags and string_flags feed `_variant_state` once,
        # and their transitions merge per-set pins, defaults, and usable
        # narrowing into the canonical `:_state` setting.
        lock_build_lines.extend([
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
            lock_build_lines.append('        "{}": {},'.format(set_suffix, json.encode(qnames)))
        lock_build_lines.extend([
            "    },",
            "    flags = {",
        ])
        for flag_label, qnames in sorted(normalized_variants.all_flags.items()):
            lock_build_lines.append('        "{}": "{}|{}",'.format(flag_label, flag_label, " ".join(qnames)))
        lock_build_lines.append("    },")
        if member_variant_flags:
            lock_build_lines.append("    string_flags = {")
            for member in sorted(member_variant_flags.keys()):
                flag_map = normalized_variants.member_flag_maps.get(member, {})
                spec = {
                    "display": "@{}//{}".format(member, VARIANTS_PACKAGE),
                    "map": {k: v for k, v in sorted(flag_map.items())},
                }
                lock_build_lines.append('        "{}": {},'.format(variants_flag_label(member), json.encode(json.encode(spec))))
            lock_build_lines.append("    },")
        lock_build_lines.extend([
            ")",
            "",
        ])

        for set_suffix in sorted(sets_by_suffix.keys()):
            resolver_name = "_resolver_" + set_suffix
            lock_build_lines.extend([
                "variant_set_projection(",
                '    name = "{}",'.format(resolver_name),
                '    state = ":_variant_state",',
                '    set_key = "{}",'.format(set_suffix),
                ")",
                "",
            ])
            lock_build_lines.extend(flag_setting(unselected_target_name(set_suffix), ":" + resolver_name, "", inline = True))

    # Emit config_settings referencing the per-set or per-item projection.
    for qname in sorted(variant_items.keys()):
        resolvers = qname_to_resolvers.get(qname, [])
        if len(resolvers) == 1:
            # Simple case: item is in exactly one conflict set.
            lock_build_lines.extend(flag_setting(constraint_setting_name(qname), ":" + resolvers[0], qname, inline = True))
        elif len(resolvers) > 1:
            # Item appears in multiple conflict sets: project directly from `_variant_state`.
            item_proj_name = "_item_" + qname
            lock_build_lines.extend([
                "variant_item_projection(",
                '    name = "{}",'.format(item_proj_name),
                '    state = ":_variant_state",',
                '    item = "{}",'.format(qname),
                ")",
                "",
            ])
            lock_build_lines.extend(flag_setting(constraint_setting_name(qname), ":" + item_proj_name, "true", inline = True))

    return "\n".join(lock_build_lines)

def _render_lock_build_for_testing(variant_items, variant_sets, qname_to_resolvers, member_variant_flags):
    return _render_lock_build(
        variant_items,
        _normalize_workspace_variants(variant_sets),
        member_variant_flags,
        qname_to_resolvers = qname_to_resolvers,
    )

# Visible for testing
render_lock_build_for_testing = _render_lock_build_for_testing

def _run_package_repo_hooks(hooks, packages_info, override_configs):
    """Run registered package_repo hooks, deduplicating backends that share a hook function."""

    # Group backends sharing the same hook function (e.g. maturin_build and
    # setuptools_rust_build) so each hook runs once with merged overrides
    # instead of concatenating duplicate load()/package() headers.
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

    # Collect all hook results, merging files for the same path.
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

# Visible for testing
run_package_repo_hooks_for_testing = _run_package_repo_hooks

def _package_repo_impl(rctx):
    merged = json.decode(rctx.attr.lock_data)
    packages = merged.get("packages", {})
    cycle_groups = merged.get("cycle_groups", {})
    resolution_marker_exprs = merged.get("resolution_marker_exprs", {})
    variant_items = merged.get("variant_items", {})
    variant_sets = merged.get("variant_sets", [])
    member_variant_flags = merged.get("member_variant_flags", {})

    # Workspace repos have no pins — each thin repo has its own.
    lock = {
        "packages": packages,
        "cycle_groups": cycle_groups,
        "resolution_marker_exprs": resolution_marker_exprs,
    }

    rctx.file("REPO.bazel", "")

    # Normalize deduplicated workspace variant sets once for lock.bzl, reset.bzl, and _lock/BUILD.bazel.
    normalized_variants = _normalize_workspace_variants(variant_sets)

    # 1. Render _lock/lock.bzl and _lock/BUILD.bazel
    lock_result = render_lock_bzl_with_meta(
        lock,
        rctx.attr.repo_map,
        rctx.name,
        has_variants = bool(normalized_variants.sets_by_suffix),
        reset_conflict_sets = normalized_variants.sets_by_suffix.values(),
    )
    rctx.file("_lock/lock.bzl", lock_result.content)
    if lock_result.has_reset:
        rctx.file(
            "_lock/reset.bzl",
            render_reset_bzl(
                normalized_variants.all_flags.keys(),
                string_flag_labels = [variants_flag_label(m) for m in sorted(member_variant_flags.keys())],
            ),
        )

    rctx.file(
        "_lock/BUILD.bazel",
        _render_lock_build(variant_items, normalized_variants, member_variant_flags),
    )

    # 2. Root BUILD.bazel
    root_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # 3. _wheel/ and _sdist/ directories for versioned artifact access
    wheel_lines = [
        'load("@rules_pycross//pycross/private:wheel_dir.bzl", "pycross_wheel_dir")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    sdist_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    for pkg_key in sorted(packages.keys()):
        parts = parse_package_key(pkg_key)

        # Skip extra packages (e.g. foo[test]@1.0.0). They do not have their
        # own wheels or sdists; they share the base package's artifacts.
        if parts.extra:
            continue
        norm_name = _normalize_name(parts.name)
        target_name = format_package_key(norm_name, parts.version, tag = parts.tag)

        # Versioned target: _wheel:name@version[~tag] -> pycross_wheel_dir wrapping //_lock:_wheel_{key}
        wheel_lines.extend([
            "pycross_wheel_dir(",
            '    name = "{}",'.format(target_name),
            '    src = "{}",'.format(local_lock_target_label(wheel_target_name(pkg_key))),
            '    whldir_name = "{}",'.format(whldir_name(pkg_key)),
            ")",
            "",
        ])

        sdist_file = packages[pkg_key].get("sdist_file")
        if sdist_file:
            sdist_lines.extend(alias(target_name, local_lock_target_label(sdist_target_name(pkg_key))))

    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_lines) + "\n")
    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_lines) + "\n")

    # 4. _backend/ directory
    rctx.file(
        "_backend/BUILD.bazel",
        "exports_files(glob(['*.bzl']))\n",
    )

    build_repo = rctx.attr.build_repo

    for macro_name in sorted(rctx.attr.backend_names):
        config = BACKEND_CONFIGS.get(macro_name)
        if config == None:
            fail("Unknown build backend '{}' in package_repo '{}'. Registered backends: {}".format(
                macro_name,
                rctx.name,
                ", ".join(sorted(BACKEND_CONFIGS.keys())),
            ))
        rule_bzl = config["rule_bzl"]
        tool_deps_labels = _backend_tool_deps_labels(config["tool_packages"], packages, build_repo)

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
            lines.append("    if \"tool_deps\" not in kwargs:")
            lines.append("        kwargs[\"tool_deps\"] = [")
            for label in tool_deps_labels:
                lines.append("            Label(\"{}\"),".format(label))
            lines.append("        ]")

        lines.extend([
            "    _{macro_name}(name = name, **kwargs)".format(macro_name = macro_name),
            "",
        ])

        rctx.file("_backend/{}.bzl".format(macro_name), "\n".join(lines))

    # Package repo hooks: let backends contribute sub-directories.
    if PACKAGE_REPO_HOOKS:
        override_configs = {}
        if rctx.attr.override_configs:
            override_configs = json.decode(rctx.attr.override_configs)

        # Build the packages info dict for hooks, keyed by normalized name.
        # Include version and sdist info so hooks can generate versioned targets.
        packages_info = {}
        for pkg_key in sorted(packages.keys()):
            parts = parse_package_key(pkg_key)
            if parts.extra:
                continue
            norm_name = _normalize_name(parts.name)
            has_sdist = bool(packages[pkg_key].get("sdist_file"))
            versions = packages_info.get(norm_name, {"versions": []})
            versions["versions"].append(struct(
                version = parts.version,
                package_key = pkg_key,
                has_sdist = has_sdist,
            ))
            packages_info[norm_name] = versions

        for path, content in _run_package_repo_hooks(PACKAGE_REPO_HOOKS, packages_info, override_configs).items():
            rctx.file(path, content)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

package_repo = repository_rule(
    implementation = _package_repo_impl,
    attrs = {
        "build_repo": attr.string(
            doc = "Name of the default build tools thin repo (e.g. 'uv__build').",
            mandatory = True,
        ),
        "repo_map": attr.string_dict(
            doc = "Maps file keys to their repository label strings (e.g. 'foo_wheel' -> '@pypi_foo//:wheel').",
        ),
        "backend_names": attr.string_list(
            doc = "Registered backend rule names to emit `_backend/<name>.bzl` macros for.",
        ),
        "lock_data": attr.string(
            doc = "JSON-encoded slimmed merged workspace lock payload from slim_workspace_lock().",
            mandatory = True,
        ),
        "override_configs": attr.string(
            doc = "JSON-encoded dict of pkg_name -> {backend_name -> backend_attrs} for package repo hooks.",
        ),
    },
)
