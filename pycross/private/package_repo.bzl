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
load("@pypackaging.bzl", "pypackaging")
load(":resolved_lock_renderer.bzl", "render_lock_bzl")
load(":util.bzl", "key_name", "parse_package_key", "underscore_name")

def _normalize_name(name):
    return pypackaging.utils.canonicalize_name(name)

def _underscore_name(name):
    return underscore_name(name)

def _merge_dependencies(first_data, entries):
    merged = dict(first_data)

    for _, pkg_data in entries[1:]:
        if not merged.get("site_paths") and pkg_data.get("site_paths"):
            merged["site_paths"] = pkg_data["site_paths"]
        if not merged.get("data_level_paths") and pkg_data.get("data_level_paths"):
            merged["data_level_paths"] = pkg_data["data_level_paths"]
        if not merged.get("sdist_file") and pkg_data.get("sdist_file"):
            merged["sdist_file"] = pkg_data["sdist_file"]

    # Merge marker_dependencies: union across workspace members, dedup by (key, marker).
    seen_marker_deps = {}  # (key, marker) -> entry
    for md in merged.get("marker_dependencies", []):
        seen_marker_deps[(md["key"], md.get("marker"))] = md
    for _, pkg_data in entries[1:]:
        for md in pkg_data.get("marker_dependencies", []):
            dedupe_key = (md["key"], md.get("marker"))
            if dedupe_key not in seen_marker_deps:
                seen_marker_deps[dedupe_key] = md
    merged["marker_dependencies"] = sorted(seen_marker_deps.values(), key = lambda m: (m["key"], m.get("marker", "")))

    # Merge wheel_candidates: union across members, dedup by filename.
    seen_candidates = {}  # filename -> entry
    for wc in merged.get("wheel_candidates", []):
        seen_candidates[wc["filename"]] = wc
    for _, pkg_data in entries[1:]:
        for wc in pkg_data.get("wheel_candidates", []):
            if wc["filename"] not in seen_candidates:
                seen_candidates[wc["filename"]] = wc
    merged["wheel_candidates"] = sorted(seen_candidates.values(), key = lambda w: w["filename"])

    return merged

def _package_repo_impl(rctx):
    # Workspace repos always have member_lock_files — even single-lock repos
    # are wrapped in a workspace with one member.
    packages = {}
    packages = {}

    # Annotation fields that affect pycross_wheel_library targets.
    # If these differ between members for the same pkg_key, the package
    # is "conflicting" and gets per-member variant targets.
    _ANNOTATION_FIELDS = ["post_install_patches", "install_exclude_globs"]

    # First pass: collect per-member package data, environment names, and cycle groups.
    member_packages = {}  # member_name -> {pkg_key -> pkg_data}
    cycle_groups = {}  # group_name -> [pkg_key, ...]
    variant_items = {}  # qualified_name -> True (dedup across members)
    variant_sets = []  # list of {"qnames": [...], "default": "..."}
    variant_sets_seen = {}  # frozenset key -> True (dedup across members)
    for member in rctx.attr.member_lock_files.keys():
        if hasattr(rctx.attr, "member_lock_data") and rctx.attr.member_lock_data and member in rctx.attr.member_lock_data:
            member_lock = json.decode(rctx.attr.member_lock_data[member])
        else:
            lock_label = rctx.attr.member_lock_files[member]
            member_lock = json.decode(rctx.read(rctx.path(Label(lock_label))))

        for variant_set in member_lock.get("variants", []):
            set_qnames = []
            set_default = ""
            for item in variant_set["items"]:
                if item["kind"] == "project":
                    qname = "package_{}".format(item["package"])
                else:
                    qname = "{}_{}".format(item["kind"], item["name"])
                variant_items[qname] = True
                set_qnames.append(qname)
                if item.get("default", False):
                    set_default = qname
            set_key = "|".join(sorted(set_qnames))
            if set_key not in variant_sets_seen:
                variant_sets_seen[set_key] = True
                variant_sets.append({"qnames": set_qnames, "default": set_default})

        member_packages[member] = member_lock.get("packages", {})

        # Merge cycle groups (union across members).
        for group_name, group_members in member_lock.get("cycle_groups", {}).items():
            if group_name in cycle_groups and sorted(cycle_groups[group_name]) != sorted(group_members):
                fail("Cycle group {} conflicts between workspace members ({} vs {})".format(group_name, cycle_groups[group_name], group_members))
            cycle_groups[group_name] = group_members

    # Second pass: detect conflicts and build merged package set.
    # conflicts maps pkg_key -> [member_name, ...] for packages with
    # differing annotations across members.
    conflicts = {}
    all_pkg_keys = {}  # pkg_key -> list of (member, pkg_data)
    for member, pkgs in member_packages.items():
        for pkg_key, pkg_data in pkgs.items():
            all_pkg_keys.setdefault(pkg_key, []).append((member, pkg_data))

    for pkg_key, entries in all_pkg_keys.items():
        if len(entries) <= 1:
            # Only in one member — no conflict possible.
            packages[pkg_key] = dict(entries[0][1])
            continue

        # Check annotation fields for differences.
        _, first_data = entries[0]
        has_annotation_conflict = False
        for _, other_data in entries[1:]:
            for field in _ANNOTATION_FIELDS:
                if first_data.get(field, []) != other_data.get(field, []):
                    has_annotation_conflict = True
                    break
            if has_annotation_conflict:
                break

        if has_annotation_conflict:
            # Conflicting annotations: create per-member variant packages.
            conflicts[pkg_key] = [member for member, _ in entries]
            for member, pkg_data in entries:
                variant_key = "{}__via_{}".format(pkg_key, member)
                packages[variant_key] = dict(pkg_data)
        else:
            packages[pkg_key] = _merge_dependencies(first_data, entries)

    # Workspace repos have no pins — each thin repo has its own.
    lock = {
        "packages": packages,
        "pins": {},
        "cycle_groups": cycle_groups,
    }

    repo_map = rctx.attr.repo_map
    sdist_map = rctx.attr.sdist_map

    rctx.file("REPO.bazel", "")

    # 1. Render _lock/lock.bzl and _lock/BUILD.bazel
    rctx.file("_lock/lock.bzl", render_lock_bzl(lock, repo_map, sdist_map, rctx.name))

    lock_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'load(":lock.bzl", "targets")',
        "",
    ]
    if variant_items:
        lock_build_lines.extend([
            'load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")',
            'load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_resolver")',
            "",
        ])

    # Map each variant item to the resolver(s) it participates in.
    qname_to_resolvers = {}  # qname -> [resolver_name, ...]
    resolver_names = []  # ordered list of resolver target names
    for vset in variant_sets:
        resolver_name = "_resolver_" + "_".join(sorted(vset["qnames"]))
        resolver_names.append(resolver_name)
        for qname in vset["qnames"]:
            qname_to_resolvers.setdefault(qname, []).append(resolver_name)

    # Check if we need config_setting_group for items in multiple sets.
    needs_config_setting_group = False
    for qname, resolvers in qname_to_resolvers.items():
        if len(resolvers) > 1:
            needs_config_setting_group = True
            break
    if needs_config_setting_group:
        lock_build_lines.extend([
            'load("@bazel_skylib//lib:selects.bzl", "selects")',
            "",
        ])

    lock_build_lines.extend([
        "targets()",
        "",
    ])

    # Emit bool_flags (user-facing UX, unchanged).
    for qname in sorted(variant_items.keys()):
        lock_build_lines.extend([
            "bool_flag(",
            '    name = "{}",'.format(qname),
            "    build_setting_default = False,",
            ")",
            "",
        ])

    # Emit variant_resolver targets (one per conflict set).
    for vset in variant_sets:
        resolver_name = "_resolver_" + "_".join(sorted(vset["qnames"]))
        lock_build_lines.extend([
            "variant_resolver(",
            '    name = "{}",'.format(resolver_name),
            "    flags = [",
        ])
        for qname in vset["qnames"]:
            lock_build_lines.append('        ":{}",'.format(qname))
        lock_build_lines.extend([
            "    ],",
            "    names = [",
        ])
        for qname in vset["qnames"]:
            lock_build_lines.append('        "{}",'.format(qname))
        lock_build_lines.extend([
            "    ],",
        ])
        if vset["default"]:
            lock_build_lines.append('    default = "{}",'.format(vset["default"]))
        lock_build_lines.extend([
            ")",
            "",
        ])

    # Emit config_settings referencing the resolver(s).
    for qname in sorted(variant_items.keys()):
        resolvers = qname_to_resolvers.get(qname, [])
        if len(resolvers) == 1:
            # Simple case: item is in exactly one conflict set.
            lock_build_lines.extend([
                "config_setting(",
                '    name = "is_{}",'.format(qname),
                '    flag_values = {{":{resolver}": "{value}"}},'.format(
                    resolver = resolvers[0],
                    value = qname,
                ),
                ")",
                "",
            ])
        elif len(resolvers) > 1:
            # Item appears in multiple conflict sets: OR them together.
            for j, resolver in enumerate(resolvers):
                lock_build_lines.extend([
                    "config_setting(",
                    '    name = "_is_{}_via_{}",'.format(qname, j),
                    '    flag_values = {{":{resolver}": "{value}"}},'.format(
                        resolver = resolver,
                        value = qname,
                    ),
                    ")",
                    "",
                ])
            lock_build_lines.extend([
                "selects.config_setting_group(",
                '    name = "is_{}",'.format(qname),
                "    match_any = [",
            ])
            for j in range(len(resolvers)):
                lock_build_lines.append('        ":_is_{}_via_{}",'.format(qname, j))
            lock_build_lines.extend([
                "    ],",
                ")",
                "",
            ])

    rctx.file("_lock/BUILD.bazel", "\n".join(lock_build_lines))

    # 2. Root BUILD.bazel
    root_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    if lock.get("legacy_create_root_aliases"):
        for pkg_key in sorted(packages.keys()):
            if "__via_" in pkg_key:
                continue
            parts = parse_package_key(pkg_key)
            if parts.extra:
                continue
            pkg_name = _normalize_name(parts.name)

            # The canonical name is the user-facing name for the root alias (e.g. 'absl-py')
            canonical = parts.name
            root_build_lines.extend([
                "alias(",
                '    name = "{}",'.format(canonical),
                '    actual = "//{}:pkg",'.format(pkg_name),
                ")",
                "",
            ])

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
        # Skip variant packages (they use __via_ suffix for conflict resolution)
        if "__via_" in pkg_key:
            continue
        parts = parse_package_key(pkg_key)

        # Skip extra packages (e.g. foo[test]@1.0.0). They do not have their
        # own wheels or sdists; they share the base package's artifacts.
        if parts.extra:
            continue
        pkg_name_part = parts.name
        pkg_version = parts.version
        norm_name = _normalize_name(pkg_name_part)
        us_name = _underscore_name(pkg_name_part)
        whldir_name = "{}-{}.whldir".format(us_name, pkg_version)

        # Versioned target: _wheel:name@version -> pycross_wheel_dir wrapping //_lock:_wheel_{key}
        wheel_lines.extend([
            "pycross_wheel_dir(",
            '    name = "{}@{}",'.format(norm_name, pkg_version),
            '    src = "//_lock:_wheel_{}",'.format(pkg_key),
            '    whldir_name = "{}",'.format(whldir_name),
            ")",
            "",
        ])

        sdist_file = packages[pkg_key].get("sdist_file")
        if sdist_file:
            sdist_lines.extend([
                "alias(",
                '    name = "{}@{}",'.format(norm_name, pkg_version),
                '    actual = "//_lock:_sdist_{}",'.format(pkg_key),
                ")",
                "",
            ])

    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_lines) + "\n")
    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_lines) + "\n")

    # 4. _backend/ directory
    rctx.file(
        "_backend/BUILD.bazel",
        "exports_files(glob(['*.bzl']))\n",
    )

    backend_configs = {}
    for name, config_json in rctx.attr.backend_configs.items():
        backend_configs[name] = json.decode(config_json)

    for macro_name, config in backend_configs.items():
        rule_bzl = config["rule_bzl"]

        tool_deps_labels = []
        for pkg in config["tool_packages"]:
            norm_pkg = _normalize_name(pkg)

            # Find a matching package in the lockfile
            matching = [k for k in packages.keys() if _normalize_name(key_name(k)) == norm_pkg]
            if matching:
                # Use the first match. For cycle groups, the name is _raw_{pkg_key}.
                # But here we just need the dependency, so pointing to //_lock:{pkg_key} is fine.
                tool_deps_labels.append("//_lock:{}".format(matching[0]))

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
            if "__via_" in pkg_key:
                continue
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

        # Collect all hook results, merging files for the same path.
        hook_files = {}  # "dir/filename" -> [content, ...]
        for backend_name, hook_fn in PACKAGE_REPO_HOOKS.items():
            # Filter overrides for this backend.
            backend_overrides = {}
            for pkg_name, backends in override_configs.items():
                if backend_name in backends:
                    backend_overrides[pkg_name] = backends[backend_name]

            if not backend_overrides:
                continue

            results = hook_fn(packages_info, backend_overrides)
            for result in results:
                for filename, content in result.files.items():
                    path = "{}/{}".format(result.dir, filename)
                    hook_files.setdefault(path, []).append(content)

        for path, contents in hook_files.items():
            rctx.file(path, "\n".join(contents))

package_repo = repository_rule(
    implementation = _package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "repo_map": attr.string_dict(
            doc = "Maps file keys to their repository label strings (e.g. 'foo_wheel' -> '@pypi_foo//:wheel').",
        ),
        "sdist_map": attr.string_dict(
            doc = "Maps sdist file keys to their built wheel label strings (e.g. 'foo_sdist' -> '@foo_sdist_repo//:wheel').",
        ),
        "backend_configs": attr.string_dict(
            doc = "Maps pycross rule names to JSON-encoded config dicts with 'rule_bzl' and 'tool_packages'.",
        ),
        "member_lock_files": attr.string_dict(
            doc = "Maps member repo names to their resolved lock file labels.",
            mandatory = True,
        ),
        "member_lock_data": attr.string_dict(
            doc = "Maps member repo names to their lock JSON content directly. When set, bypasses file reads for those members.",
        ),
        "override_configs": attr.string(
            doc = "JSON-encoded dict of pkg_name -> {backend_name -> backend_attrs} for package repo hooks.",
        ),
    },
)
