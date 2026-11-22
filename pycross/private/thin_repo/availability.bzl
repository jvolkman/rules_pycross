"""Availability conditions and `:maybe` / `__maybe` alias generation."""

load("//pycross/private:util.bzl", "is_wheel_platform_specific", "marker_evaluator_name", "parse_package_key", "sanitize_name")
load(":common.bzl", "NO_VARIANT_PREFIX")
load(":selects.bzl", "unselected_branch")

def availability_condition(lines, helper_prefix, lock_key, packages, workspace_repo):
    """Return a config_setting label for a package's availability in this thin repo.

    Composes this member's own `availability_markers` (via `@ws//_lock:<eval>_match`)
    with `@ws//_lock:_wheel_available_<pkg>` when wheel selection is platform-specific,
    so different workspace members with different root platform markers never clobber
    each other in the shared `@ws//_lock` package.

    Args:
        lines: Output list of BUILD lines for helper `config_setting_group` targets.
        helper_prefix: Target name prefix for generated helper groups.
        lock_key: Package key in the lock.
        packages: Lock packages dict, or None for legacy test callers.
        workspace_repo: Name of the workspace (backing) repo.

    Returns:
        Config setting label string that matches when `lock_key` is available.
    """
    if packages == None:
        return "@{}//_lock:_wheel_available_{}".format(workspace_repo, lock_key)

    pkg = packages.get(lock_key, {})
    parts = parse_package_key(lock_key)
    is_extras_proxy = not pkg.get("wheel_candidates") and bool(parts.extra)
    base_pkg_key = "{}@{}".format(parts.name, parts.version) if is_extras_proxy else None
    base_pkg = packages.get(base_pkg_key, {}) if base_pkg_key else {}

    all_conditions = []
    seen = {}

    def _add_cond(cond):
        if cond not in seen:
            seen[cond] = True
            all_conditions.append(cond)

    wheel_pkg = base_pkg if is_extras_proxy else pkg
    wheel_lock_key = base_pkg_key if is_extras_proxy else lock_key
    if is_wheel_platform_specific(wheel_pkg):
        _add_cond("@{}//_lock:_wheel_available_{}".format(workspace_repo, wheel_lock_key))

    key_san = sanitize_name(lock_key)
    marker_groups = []
    if is_extras_proxy and base_pkg.get("availability_markers"):
        marker_groups.append(("base", base_pkg["availability_markers"]))
    if pkg.get("availability_markers"):
        marker_groups.append(("own", pkg["availability_markers"]))

    for tag, markers in marker_groups:
        unique_evals = []
        seen_evals = {}
        for m in markers:
            ev = marker_evaluator_name(m, "")
            if ev not in seen_evals:
                seen_evals[ev] = True
                unique_evals.append(ev)
        if len(unique_evals) == 1:
            _add_cond("@{}//_lock:{}_match".format(workspace_repo, unique_evals[0]))
        elif len(unique_evals) > 1:
            group_name = "{}_markers_{}_{}".format(helper_prefix, tag, key_san)
            lines.extend([
                "selects.config_setting_group(",
                '    name = "{}",'.format(group_name),
                "    match_any = [",
            ])
            for ev in unique_evals:
                lines.append('        "@{}//_lock:{}_match",'.format(workspace_repo, ev))
            lines.extend([
                "    ],",
                ")",
                "",
            ])
            _add_cond(":{}".format(group_name))

    if not all_conditions:
        # Unreachable for callers that filter on is_platform_specific(); kept as
        # a defensive fallback for unit tests passing a synthetic packages dict.
        return "@{}//_lock:_wheel_available_{}".format(workspace_repo, lock_key)
    if len(all_conditions) == 1:
        return all_conditions[0]

    combined_name = "{}_avail_{}".format(helper_prefix, key_san)
    lines.extend([
        "selects.config_setting_group(",
        '    name = "{}",'.format(combined_name),
        "    match_all = [",
    ])
    for cond in all_conditions:
        lines.append('        "{}",'.format(cond))
    lines.extend([
        "    ],",
        ")",
        "",
    ])
    return ":{}".format(combined_name)

def emit_maybe_alias(lines, maybe_name, pkg_target, target_dict, available_keys, workspace_repo, no_variant_fallbacks = None, helper_prefix = "_maybe", packages = None):
    """Emit a `:maybe` or `:[extra]_maybe` alias supporting both single-branch and multi-branch pins.

    Args:
        lines: Output list of BUILD lines.
        maybe_name: Name of the emitted maybe alias target.
        pkg_target: Target label selected when the package is available.
        target_dict: Constraint -> package key mapping for the pin.
        available_keys: List of package keys that need availability gating.
        workspace_repo: Name of the workspace (backing) repo.
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        helper_prefix: Prefix for intermediate helper targets.
        packages: Lock packages dict, or None.
    """
    available_set = {k: True for k in (available_keys or [])}
    if not target_dict or (not available_set and "" in target_dict):
        return

    if len(target_dict) == 1 and "" in target_dict:
        only_key = target_dict[""]
        if only_key not in available_set:
            fail("Single-branch target '{}' not found in available_keys {}".format(only_key, available_keys))
        avail_cond = availability_condition(lines, helper_prefix, only_key, packages, workspace_repo)
        lines.extend([
            "alias(",
            '    name = "{}",'.format(maybe_name),
            "    actual = select({",
            '        "{}": "{}",'.format(avail_cond, pkg_target),
            '        "//conditions:default": "//:_empty_library",',
            "    }),",
            ")",
            "",
        ])
        return

    emitted_helpers = {}
    branch_targets = {}
    for constraint, pkg_key in target_dict.items():
        if pkg_key not in available_set:
            branch_targets[constraint] = pkg_target
            continue
        helper_name = "{}_{}".format(
            helper_prefix,
            sanitize_name(pkg_key),
        )
        if pkg_key not in emitted_helpers:
            emitted_helpers[pkg_key] = helper_name
            avail_cond = availability_condition(lines, helper_prefix, pkg_key, packages, workspace_repo)
            lines.extend([
                "alias(",
                '    name = "{}",'.format(helper_name),
                "    actual = select({",
                '        "{}": "{}",'.format(avail_cond, pkg_target),
                '        "//conditions:default": "//:_empty_library",',
                "    }),",
                ")",
                "",
            ])
        branch_targets[constraint] = ":{}".format(emitted_helpers[pkg_key])

    lines.extend([
        "alias(",
        '    name = "{}",'.format(maybe_name),
        "    actual = select({",
    ])
    for constraint, branch_target in branch_targets.items():
        if constraint == "":
            lines.append('        "//conditions:default": "{}",'.format(branch_target))
        else:
            lines.append('        "@{}//_lock:is_{}": "{}",'.format(workspace_repo, constraint, branch_target))

    if "" not in branch_targets:
        unselected = unselected_branch(branch_targets.keys(), no_variant_fallbacks, workspace_repo)
        if unselected:
            lines.append('        "{}": "{}{}",'.format(unselected[0], NO_VARIANT_PREFIX, unselected[1]))
        lines.append('        "//conditions:default": "//:_empty_library",')

    lines.extend([
        "    }),",
        ")",
        "",
    ])

def render_maybe_build(maybe_mapping_targets, packages, workspace_repo):
    """Render `__maybe/BUILD.bazel` with platform-specific aliases reusing `//:_empty_library`.

    Args:
        maybe_mapping_targets: Dict mapping maybe target name -> `(pkg_key, lock_label)`.
        packages: Lock packages dict.
        workspace_repo: Name of the workspace (backing) repo.

    Returns:
        Generated `__maybe/BUILD.bazel` file content.
    """
    maybe_body_lines = []
    for maybe_name, (pkg_key, lock_label) in sorted(maybe_mapping_targets.items()):
        avail_cond = availability_condition(maybe_body_lines, "_maybe", pkg_key, packages, workspace_repo)
        maybe_body_lines.extend([
            "alias(",
            "    name = {},".format(json.encode(maybe_name)),
            "    actual = select({",
            "        {}: {},".format(json.encode(avail_cond), json.encode(lock_label)),
            '        "//conditions:default": "//:_empty_library",',
            "    }),",
            ")",
            "",
        ])
    maybe_header_lines = []
    if any(["selects.config_setting_group(" in line for line in maybe_body_lines]):
        maybe_header_lines.extend([
            'load("@bazel_skylib//lib:selects.bzl", "selects")',
            "",
        ])
    maybe_header_lines.extend([
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])
    return "\n".join(maybe_header_lines + maybe_body_lines)
