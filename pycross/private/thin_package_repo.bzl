"""A thin package repo that delegates to a workspace for shared resources.

Each user-facing repo is "thin": it only contains pin aliases,
requirements.bzl, and modules_mapping.json. The actual
pycross_wheel_library targets live in the shared workspace repo.

The file structure is:
- BUILD.bazel              - Root aliases (//:package).
- requirements.bzl         - Provides requirement(), all_requirements and all_testonly_requirements.
- modules_mapping.json     - Import-to-package mapping for Gazelle.
- <package>/BUILD.bazel    - Pin proxies pointing to @workspace//_lock targets.
- _variants/BUILD.bazel    - This repo's variant flags, is_<flag> config settings and no-variant errors.
"""

load("@pycross_backends//:package_repo_dispatch.bzl", "PACKAGE_REPO_HOOKS", "PACKAGE_REPO_HOOK_SUBDIRS")
load("//pycross/private/thin_repo:availability.bzl", "render_maybe_build")
load("//pycross/private/thin_repo:metadata.bzl", "LEGACY_CARGO_HOOK_BACKENDS", "emit_backend_files", "hook_subdir_build", "requirements_bzl")
load("//pycross/private/thin_repo:modules_mapping_deps.bzl", "modules_mapping_deps")
load("//pycross/private/thin_repo:pins.bzl", "append_root_aliases", "emit_pin_directories")
load("//pycross/private/thin_repo:selects.bzl", "variant_fallbacks")
load("//pycross/private/thin_repo:transition.bzl", "render_transition_bzl")
load("//pycross/private/thin_repo:variants.bzl", "collect_variants", "transition_settings", "variants_build")
load(":lock_contract.bzl", "variant_state_label")
load(":util.bzl", "base_packages_with_extras", "parse_package_key")

def _thin_package_repo_impl(rctx):
    workspace_repo = rctx.attr.workspace_repo
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock = json.decode(rctx.read(lock_json_path))
    packages = lock["packages"]
    pins = lock["pins"]
    testonly_pins_set = {p: True for p in lock.get("testonly_pins", [])}

    # Normalize pin values: bare strings (unconditional) become {"": value}.
    # Kept because hand-authored resolved-lock fixtures (e.g. tests/golden/fixtures/*.json)
    # pass bare string pins directly to thin_package_repo.
    for pin_name in pins.keys():
        if type(pins[pin_name]) == "string":
            pins[pin_name] = {"": pins[pin_name]}

    # This repo's variant flags and conflict sets. Every set gets an
    # _unselected_<set> -> _no_variant_<set> fallback in selects; defaults come
    # from this repo's transition (`d:<set>` in `//_lock:_state`), not //conditions:default.
    variant_info = collect_variants(lock.get("variants", []))
    sets_by_constraint = {}  # constraint -> [conflict set suffixes (sorted qnames joined by "_")]
    for set_suffix, vset in sorted(variant_info.sets.items()):
        for qname in vset.qnames:
            sets_by_constraint.setdefault(qname, []).append(set_suffix)

    # Only compound {variant, marker} constraints need a variant. A plain marker
    # constraint (an unconflicted edge that uv split by conflict markers) is
    # valid with no variant selected, e.g. `extra != '__variant_package_a'`.
    for cname, expr in lock.get("resolution_marker_exprs", {}).items():
        if type(expr) == "dict" and expr.get("variant") in sets_by_constraint:
            sets_by_constraint[cname] = sets_by_constraint[expr["variant"]]
    no_variant_fallbacks = variant_fallbacks(sets_by_constraint)

    rctx.file("REPO.bazel", "")
    rctx.file("requirements.bzl", requirements_bzl(rctx, pins, packages, testonly_pins_set))

    # Group pins by base package name to identify extras.
    grouped_pins = {}
    for pin_name, pin_target in pins.items():
        parts = parse_package_key(pin_name)
        if parts.name not in grouped_pins:
            grouped_pins[parts.name] = {"base_target": None, "extras": {}}
        if parts.extra:
            grouped_pins[parts.name]["extras"][parts.extra] = pin_target
        else:
            grouped_pins[parts.name]["base_target"] = pin_target

    root_build_lines = [
        'load("@rules_pycross//pycross/private:modules_mapping.bzl", "pycross_modules_mapping")',
        'load("@rules_python//python:defs.bzl", "py_library")',
        'package(default_visibility = ["//visibility:public"])',
        "",
        "# Empty library for _maybe_ targets on incompatible platforms.",
        'py_library(name = "_empty_library", visibility = ["//:__subpackages__"])',
        "",
    ]

    # Generate internal platform + transition if needed.
    target_platform = rctx.attr.platform
    settings = transition_settings(
        variant_info,
        rctx.attr.variant_pins,
        rctx.attr.member_name,
        has_other_flags = bool(rctx.attr.flags) or bool(rctx.attr.settings),
    )
    state_overrides = settings.state_overrides
    pins_by_set = settings.pins_by_set
    defaults_by_set = settings.defaults_by_set
    excluded = settings.excluded
    has_flags = bool(rctx.attr.flags) or bool(rctx.attr.settings) or bool(state_overrides)

    if not target_platform and rctx.attr.constraint_values:
        target_platform = "//:_internal_platform"
        root_build_lines.extend([
            "platform(",
            '    name = "_internal_platform",',
            "    constraint_values = [",
        ])
        for cv in rctx.attr.constraint_values:
            root_build_lines.append("        {},".format(json.encode(cv)))
        root_build_lines.extend([
            "    ],",
            ")",
            "",
        ])

    if has_flags:
        rctx.file(
            "_transition.bzl",
            render_transition_bzl(
                rctx.attr.member_name,
                rctx.attr.flags,
                rctx.attr.settings,
                variant_state_label = variant_state_label(workspace_repo) if state_overrides else "",
                variant_state_overrides = state_overrides,
            ),
        )

    unselected_groups = {}

    # Collect conditional deps and platform-specific packages for modules_mapping.
    mm = modules_mapping_deps(
        pins,
        packages,
        workspace_repo,
        variant_info = variant_info,
        no_variant_fallbacks = no_variant_fallbacks,
        pins_by_set = pins_by_set,
        defaults_by_set = defaults_by_set,
        excluded = excluded,
        resolution_marker_exprs = lock.get("resolution_marker_exprs", {}),
    )
    unselected_groups.update(mm.unselected_groups)
    if mm.needs_selects:
        root_build_lines.insert(0, 'load("@bazel_skylib//lib:selects.bzl", "selects")')

    if has_flags or target_platform:
        mapping_name = "_modules_mapping"
        if has_flags:
            root_build_lines.insert(0, 'load("//:_transition.bzl", "pycross_transitioning_file_proxy")')
        else:
            root_build_lines.insert(0, 'load("@rules_pycross//pycross/private:proxy.bzl", "pycross_transitioning_file_proxy")')
        root_build_lines.extend([
            "pycross_transitioning_file_proxy(",
            '    name = "modules_mapping",',
            '    actual = ":_modules_mapping",',
        ])
        if target_platform:
            root_build_lines.append("    platform = {},".format(json.encode(target_platform)))
        root_build_lines.extend([")", ""])
    else:
        mapping_name = "modules_mapping"

    root_build_lines.extend([
        'exports_files(["requirements.bzl"])',
        "",
    ])
    root_build_lines.extend(mm.extra_target_lines)
    root_build_lines.extend([
        "pycross_modules_mapping(",
        "    name = {},".format(json.encode(mapping_name)),
    ])
    root_build_lines.extend(mm.deps_lines)
    root_build_lines.extend([")", ""])

    if mm.maybe_mapping_targets:
        rctx.file("__maybe/BUILD.bazel", render_maybe_build(mm.maybe_mapping_targets, packages, workspace_repo))

    extras_by_base = base_packages_with_extras(packages)

    append_root_aliases(root_build_lines, grouped_pins, extras_by_base)
    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    unselected_groups.update(emit_pin_directories(
        rctx,
        grouped_pins,
        packages,
        extras_by_base,
        workspace_repo,
        no_variant_fallbacks,
        target_platform,
        has_flags,
        testonly_pins_set,
    ))
    emit_backend_files(rctx, rctx.attr.backend_configs, workspace_repo)

    hook_backends_by_subdir = {}
    for backend_name, subdir in sorted(PACKAGE_REPO_HOOK_SUBDIRS.items()):
        if subdir and backend_name in PACKAGE_REPO_HOOKS:
            hook_backends_by_subdir.setdefault(subdir, []).append(backend_name)
    for legacy_backend in LEGACY_CARGO_HOOK_BACKENDS:
        if legacy_backend in PACKAGE_REPO_HOOKS and legacy_backend not in PACKAGE_REPO_HOOK_SUBDIRS:
            hook_backends_by_subdir.setdefault("_cargo", []).append(legacy_backend)

    if rctx.attr.override_configs and hook_backends_by_subdir:
        override_configs = json.decode(rctx.attr.override_configs)
        for subdir, hook_backends in sorted(hook_backends_by_subdir.items()):
            hook_result = hook_subdir_build(
                grouped_pins,
                packages,
                override_configs,
                workspace_repo,
                no_variant_fallbacks = no_variant_fallbacks,
                hook_backends = hook_backends,
                subdir = subdir,
            )
            if hook_result:
                unselected_groups.update(hook_result.unselected_groups)
                rctx.file("{}/BUILD.bazel".format(subdir), hook_result.build)

    # _variants/ BUILD: this repo's variant flags (see variants_build), including
    # every `_unselected_all_*` group collected from the selects above.
    variants_content = variants_build(
        variant_info,
        workspace_repo,
        getattr(rctx, "original_name", "") or "<repo>",
        unselected_groups = unselected_groups,
        pins_by_set = pins_by_set,
        defaults_by_set = defaults_by_set,
        excluded = excluded,
        expose_variant_flags = rctx.attr.expose_variant_flags,
    )
    if variants_content:
        rctx.file("_variants/BUILD.bazel", variants_content)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

thin_package_repo = repository_rule(
    implementation = _thin_package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "workspace_repo": attr.string(
            mandatory = True,
            doc = "Name of the workspace package_repo that contains the shared _lock/ targets.",
        ),
        "member_name": attr.string(
            mandatory = True,
            doc = "User-facing repo name for this member (used in transition rules and diagnostics).",
        ),
        "backend_configs": attr.string_dict(
            doc = "Map of rule names to JSON-encoded config dicts.",
        ),
        "flags": attr.string_list(
            doc = "Normalized `--<label>[=<value>]` flags applied by the repo transition.",
            default = [],
        ),
        "settings": attr.string_dict(
            doc = "Canonical build setting label -> value, applied by the repo transition.",
            default = {},
        ),
        "constraint_values": attr.string_list(
            doc = "List of constraint values to apply to the generated platform.",
            default = [],
        ),
        "platform": attr.string(
            doc = "Existing platform target to use directly.",
        ),
        "variant_pins": attr.string_dict(
            doc = "Conflict set suffix -> qualified name of the variant this repo's flags/settings select. " +
                  "Its transition merges `p:<set>` into the workspace repo's `//_lock:_state`.",
        ),
        "override_configs": attr.string(
            doc = "JSON-encoded dict of pkg_name -> {backend_name -> backend_attrs} for package repo hooks.",
        ),
        "expose_variant_flags": attr.bool(
            doc = "Whether to emit user-facing `_variants` flags in this thin repo.",
            default = True,
        ),
    },
)
