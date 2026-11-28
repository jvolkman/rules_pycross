"""Availability conditions and `:maybe` / `__maybe` alias generation."""

load("//pycross/private:build_text.bzl", "alias", "config_setting_group", "select_expr")
load(
    "//pycross/private:lock_contract.bzl",
    "is_extras_proxy",
    "member_constraint_label",
    "member_marker_match_label",
    "spoke_slot_label",
    "state_repo_name",
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

def markers_condition(lines, group_name, markers, used = None):
    """Return a config_setting label matching when any marker in `markers` holds, or None.

    Args:
        lines: Output list of BUILD lines for a helper `match_any` group when needed.
        group_name: Target name for the `config_setting_group` when >1 unique markers exist.
        markers: Iterable of PEP 508 marker strings, or None.
        used: Optional dict where `"selects"` is set to True when `selects.config_setting_group` is emitted.

    Returns:
        Config setting label string, or None when `markers` is empty.
    """
    unique_evals = []
    seen_evals = {}
    for m in markers or []:
        ev = marker_evaluator_name(m, "")
        if ev not in seen_evals:
            seen_evals[ev] = True
            unique_evals.append(ev)
    if not unique_evals:
        return None
    if len(unique_evals) == 1:
        return member_marker_match_label(unique_evals[0])
    lines.extend(config_setting_group(
        group_name,
        "match_any",
        [member_marker_match_label(ev) for ev in unique_evals],
    ))
    if used != None:
        used["selects"] = True
    return ":{}".format(group_name)

def availability_condition(lines, helper_prefix, slot_key, packages, workspace_name, used = None):
    """Return a config_setting label for a package's availability in this thin repo.

    Composes this member's local `availability_markers` (via `//_markers:<eval>_match`)
    with `@<ws>__pkg_<name>//:_wheel_available[_<slot>]` when wheel selection is
    platform-specific.

    Args:
        lines: Output list of BUILD lines for helper `config_setting_group` targets.
        helper_prefix: Target name prefix for generated helper groups.
        slot_key: Version-free slot key (`foo`, `foo@s0`, `foo[extra]@s1`).
        packages: Slimmed member packages dict keyed by slot key, or None.
        workspace_name: Workspace name.
        used: Optional dict where `"selects"` is set to True when `selects.config_setting_group` is emitted.

    Returns:
        Config setting label string that matches when `slot_key` is available.
    """
    if packages == None:
        return spoke_slot_label(workspace_name, slot_key, "wheel_available")

    pkg = packages.get(slot_key, {})
    extras_proxy = is_extras_proxy(slot_key, pkg)
    base_slot_key = base_package_key(slot_key) if extras_proxy else None
    base_pkg = packages.get(base_slot_key, {}) if base_slot_key else {}

    all_conditions = []
    seen = {}

    def _add_cond(cond):
        if cond not in seen:
            seen[cond] = True
            all_conditions.append(cond)

    wheel_pkg = base_pkg if extras_proxy else pkg
    wheel_slot_key = base_slot_key if extras_proxy else slot_key
    if is_wheel_platform_specific(wheel_pkg):
        _add_cond(spoke_slot_label(workspace_name, wheel_slot_key, "wheel_available"))

    key_san = sanitize_name(slot_key)
    marker_groups = []
    if extras_proxy and base_pkg.get("availability_markers"):
        marker_groups.append(("base", base_pkg["availability_markers"]))
    if pkg.get("availability_markers"):
        marker_groups.append(("own", pkg["availability_markers"]))

    for tag, markers in marker_groups:
        cond = markers_condition(
            lines,
            "{}_markers_{}_{}".format(helper_prefix, tag, key_san),
            markers,
            used = used,
        )
        if cond:
            _add_cond(cond)

    if not all_conditions:
        return spoke_slot_label(workspace_name, slot_key, "wheel_available")
    if len(all_conditions) == 1:
        return all_conditions[0]

    combined_name = "{}_avail_{}".format(helper_prefix, key_san)
    lines.extend(config_setting_group(combined_name, "match_all", all_conditions))
    if used != None:
        used["selects"] = True
    return ":{}".format(combined_name)

def emit_maybe_alias(
        lines,
        maybe_name,
        pkg_target,
        target_dict,
        available_keys,
        workspace_name,
        state_repo = None,
        no_variant_fallbacks = None,
        helper_prefix = "_maybe",
        packages = None,
        used = None,
        resolution_marker_exprs = None):
    """Emit a `:maybe` or `:[extra]_maybe` alias supporting both single-branch and multi-branch pins.

    Args:
        lines: Output list of BUILD lines.
        maybe_name: Name of the emitted maybe alias target.
        pkg_target: Target label selected when the package is available.
        target_dict: Constraint -> slot key mapping for the pin.
        available_keys: List of slot keys that need availability gating.
        workspace_name: Workspace name.
        state_repo: Optional apparent name of `@<ws>__state` (defaults to `state_repo_name(workspace_name)`).
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        helper_prefix: Prefix for intermediate helper targets.
        packages: Slimmed member packages dict, or None.
        used: Optional dict tracking emitted helper loads (`"selects"`).
        resolution_marker_exprs: Optional member `resolution_marker_exprs` dict.

    Returns:
        Dict of `{group_name: set_suffixes}` for any `_unselected_all_*` groups referenced.
    """
    state_repo = state_repo or state_repo_name(workspace_name)
    available_set = {k: True for k in (available_keys or [])}
    if not target_dict or (not available_set and "" in target_dict):
        return {}

    if len(target_dict) == 1 and "" in target_dict:
        only_key = target_dict[""]
        if only_key not in available_set:
            fail("Single-branch target '{}' not found in available_keys {}".format(only_key, available_keys))
        avail_cond = availability_condition(lines, helper_prefix, only_key, packages, workspace_name, used = used)
        lines.extend(_maybe_select_alias(maybe_name, avail_cond, pkg_target))
        return {}

    emitted_helpers = {}
    branch_targets = {}
    for constraint, slot_key in target_dict.items():
        if slot_key not in available_set:
            branch_targets[constraint] = pkg_target
            continue
        helper_name = "{}_{}".format(
            helper_prefix,
            sanitize_name(slot_key),
        )
        if slot_key not in emitted_helpers:
            emitted_helpers[slot_key] = helper_name
            avail_cond = availability_condition(lines, helper_prefix, slot_key, packages, workspace_name, used = used)
            lines.extend(_maybe_select_alias(helper_name, avail_cond, pkg_target))
        branch_targets[constraint] = ":{}".format(emitted_helpers[slot_key])

    branches = []
    for constraint, branch_target in branch_targets.items():
        if constraint == "":
            branches.append(("//conditions:default", branch_target))
        else:
            branches.append((member_constraint_label(state_repo, constraint, resolution_marker_exprs), branch_target))

    default_target = None
    unselected_groups = {}
    if "" not in branch_targets:
        unselected = unselected_branch(branch_targets.keys(), no_variant_fallbacks, state_repo)
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

def render_maybe_build(maybe_mapping_targets, packages, workspace_name):
    """Render `__maybe/BUILD.bazel` with platform-specific aliases reusing `//:_empty_library`.

    Args:
        maybe_mapping_targets: Dict mapping maybe target name -> `(slot_key, spoke_raw_label)`.
        packages: Slimmed member packages dict.
        workspace_name: Workspace name.

    Returns:
        Generated `__maybe/BUILD.bazel` file content.
    """
    maybe_body_lines = []
    used = {}
    for maybe_name, (slot_key, spoke_label) in sorted(maybe_mapping_targets.items()):
        avail_cond = availability_condition(maybe_body_lines, "_maybe", slot_key, packages, workspace_name, used = used)
        maybe_body_lines.extend(_maybe_select_alias(maybe_name, avail_cond, spoke_label))
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
