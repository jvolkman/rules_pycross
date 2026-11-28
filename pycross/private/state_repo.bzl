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
load(":build_text.bzl", "flag_setting")
load(
    ":lock_contract.bzl",
    "VARIANTS_PACKAGE",
    "VARIANT_STATE_TARGET",
    "constraint_setting_name",
    "unselected_target_name",
    "variants_flag_label",
)
load(":util.bzl", "underscore_name")
load(":variant_util.bzl", "variant_set_suffix")

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
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    sets_by_suffix = normalized_variants.sets_by_suffix
    needs_item_projection = any([len(resolvers) > 1 for resolvers in qname_to_resolvers.values()])
    if variant_items:
        lines.append('load("@bazel_skylib//rules:common_settings.bzl", "string_flag")')
        if needs_item_projection:
            lines.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_item_projection", "variant_set_projection", "variant_state")')
        else:
            lines.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "variant_set_projection", "variant_state")')
        lines.append("")

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
        for path, content in run_package_repo_hooks(fallback_hooks, packages_info, override_configs).items():
            rctx.file(path, content)

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
