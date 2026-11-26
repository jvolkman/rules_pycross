"""Availability conditions and `:maybe` / `__maybe` alias generation."""

load("//pycross/private:build_text.bzl", "alias", "config_setting_group", "select_expr")
load(
    "//pycross/private:lock_contract.bzl",
    "is_extras_proxy",
    "lock_constraint_label",
    "lock_marker_match_label",
    "lock_wheel_available_label",
)
load("//pycross/private:util.bzl", "base_package_key", "is_wheel_platform_specific", "marker_evaluator_name", "sanitize_name")
load(":common.bzl", "NO_VARIANT_PREFIX")
load(":selects.bzl", "unselected_branch")

def _maybe_select_alias(name, avail_cond, target):
    """Emit an `alias` selecting `target` when `avail_cond` matches, else `//:_empty_library`."""
    return alias(
        name,
        select_expr([(avail_cond, target)], default = "//:_empty_library", indent = 1),
        actual_is_expr = True,
    )

def availability_condition(lines, helper_prefix, lock_key, packages, workspace_repo, used = None):
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
        used: Optional dict where `"selects"` is set to True when `selects.config_setting_group` is emitted.

    Returns:
        Config setting label string that matches when `lock_key` is available.
    """
    if packages == None:
        return lock_wheel_available_label(workspace_repo, lock_key)

    pkg = packages.get(lock_key, {})
    extras_proxy = is_extras_proxy(lock_key, pkg)
    base_pkg_key = base_package_key(lock_key) if extras_proxy else None
    base_pkg = packages.get(base_pkg_key, {}) if base_pkg_key else {}

    all_conditions = []
    seen = {}

    def _add_cond(cond):
        if cond not in seen:
            seen[cond] = True
            all_conditions.append(cond)

    wheel_pkg = base_pkg if extras_proxy else pkg
    wheel_lock_key = base_pkg_key if extras_proxy else lock_key
    if is_wheel_platform_specific(wheel_pkg):
        _add_cond(lock_wheel_available_label(workspace_repo, wheel_lock_key))

    key_san = sanitize_name(lock_key)
    marker_groups = []
    if extras_proxy and base_pkg.get("availability_markers"):
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
            _add_cond(lock_marker_match_label(workspace_repo, unique_evals[0]))
        elif len(unique_evals) > 1:
            group_name = "{}_markers_{}_{}".format(helper_prefix, tag, key_san)
            lines.extend(config_setting_group(
                group_name,
                "match_any",
                [lock_marker_match_label(workspace_repo, ev) for ev in unique_evals],
            ))
            if used != None:
                used["selects"] = True
            _add_cond(":{}".format(group_name))

    if not all_conditions:
        # Unreachable for callers that filter on is_platform_specific(); kept as
        # a defensive fallback for unit tests passing a synthetic packages dict.
        return lock_wheel_available_label(workspace_repo, lock_key)
    if len(all_conditions) == 1:
        return all_conditions[0]

    combined_name = "{}_avail_{}".format(helper_prefix, key_san)
    lines.extend(config_setting_group(combined_name, "match_all", all_conditions))
    if used != None:
        used["selects"] = True
    return ":{}".format(combined_name)

def emit_maybe_alias(lines, maybe_name, pkg_target, target_dict, available_keys, workspace_repo, no_variant_fallbacks = None, helper_prefix = "_maybe", packages = None, used = None):
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
        used: Optional dict tracking emitted helper loads (`"selects"`).

    Returns:
        Dict of `{group_name: set_suffixes}` for any `_unselected_all_*` groups referenced.
    """
    available_set = {k: True for k in (available_keys or [])}
    if not target_dict or (not available_set and "" in target_dict):
        return {}

    if len(target_dict) == 1 and "" in target_dict:
        only_key = target_dict[""]
        if only_key not in available_set:
            fail("Single-branch target '{}' not found in available_keys {}".format(only_key, available_keys))
        avail_cond = availability_condition(lines, helper_prefix, only_key, packages, workspace_repo, used = used)
        lines.extend(_maybe_select_alias(maybe_name, avail_cond, pkg_target))
        return {}

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
            avail_cond = availability_condition(lines, helper_prefix, pkg_key, packages, workspace_repo, used = used)
            lines.extend(_maybe_select_alias(helper_name, avail_cond, pkg_target))
        branch_targets[constraint] = ":{}".format(emitted_helpers[pkg_key])

    branches = []
    for constraint, branch_target in branch_targets.items():
        if constraint == "":
            branches.append(("//conditions:default", branch_target))
        else:
            branches.append((lock_constraint_label(workspace_repo, constraint), branch_target))

    default_target = None
    unselected_groups = {}
    if "" not in branch_targets:
        unselected = unselected_branch(branch_targets.keys(), no_variant_fallbacks, workspace_repo)
        if unselected:
            branches.append((unselected.condition, NO_VARIANT_PREFIX + unselected.error_set))
            unselected_groups.update(unselected.unselected_groups)
        default_target = "//:_empty_library"

    lines.extend(alias(
        maybe_name,
        select_expr(branches, default = default_target, indent = 1),
        actual_is_expr = True,
    ))
    return unselected_groups

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
    used = {}
    for maybe_name, (pkg_key, lock_label) in sorted(maybe_mapping_targets.items()):
        avail_cond = availability_condition(maybe_body_lines, "_maybe", pkg_key, packages, workspace_repo, used = used)
        maybe_body_lines.extend(_maybe_select_alias(maybe_name, avail_cond, lock_label))
    maybe_header_lines = []
    if used.get("selects"):
        maybe_header_lines.extend([
            'load("@bazel_skylib//lib:selects.bzl", "selects")',
            "",
        ])
    maybe_header_lines.extend([
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])
    return "\n".join(maybe_header_lines + maybe_body_lines)
