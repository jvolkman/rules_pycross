"""Select expression and variant fallback helpers for thin package repos."""

load(":common.bzl", "NO_MATCH_ERROR_TARGET", "NO_VARIANT_PREFIX", "aggregated_key")

def variant_fallbacks(sets_by_constraint):
    """Build the no-variant fallback info for this repo's selects.

    Args:
        sets_by_constraint: {constraint: [conflict set suffixes]} for each
            constraint that needs a variant.

    Returns:
        struct(sets, groups). `groups` collects the `_unselected_all_<hash>`
        targets that selects reference, for variants_build to emit.
    """
    return struct(sets = sets_by_constraint, groups = {})

def unselected_all_name(set_suffixes):
    """Return the deterministic `_unselected_all_<hash>` target name for `set_suffixes`."""
    return "_unselected_all_%x" % (hash("|".join(set_suffixes)) & 0xffffffff)

def unselected_branch(constraints, no_variant_fallbacks, workspace_repo):
    """The select() branch for "no variant selected", or None.

    It matches only when every conflict set that the constraints touch is
    unselected. An item can be in several sets (`[[cpu, gpu], [cpu, gpu-test]]`),
    and if any of them is selected, one of the select's own conditions decides.

    Args:
        constraints: The select's constraint keys.
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        workspace_repo: Name of the workspace (backing) repo.

    Returns:
        (condition label, conflict set for the error target), or None.
    """
    if not no_variant_fallbacks:
        return None
    counts = {}  # set suffix -> number of constraints in it
    for constraint in constraints:
        for set_suffix in no_variant_fallbacks.sets.get(constraint, []):
            counts[set_suffix] = counts.get(set_suffix, 0) + 1
    if not counts:
        return None
    set_suffixes = sorted(counts.keys())

    # The error names the flags of the set that covers most of the constraints.
    error_set = set_suffixes[0]
    for set_suffix in set_suffixes:
        if counts[set_suffix] > counts[error_set]:
            error_set = set_suffix
    if len(set_suffixes) == 1:
        return ("@{}//_lock:_unselected_{}".format(workspace_repo, error_set), error_set)
    name = unselected_all_name(set_suffixes)
    no_variant_fallbacks.groups[name] = set_suffixes
    return ("//_variants:" + name, error_set)

def target_select(target_dict, prefix, workspace_repo, is_aggregated = False, no_variant_fallbacks = None, all_target_dict = None, fallback_target = NO_MATCH_ERROR_TARGET, aggregated_keys = None):
    """Render a target label or `select({...})` mapping constraints to lock targets.

    Args:
        target_dict: Constraint -> package key mapping to render.
        prefix: Label prefix (e.g. `@ws//_lock:`).
        workspace_repo: Name of the workspace (backing) repo.
        is_aggregated: Whether to rewrite base keys to `[_all_]` aggregates.
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        all_target_dict: Full constraint dict when rendering a partial subset (e.g. sdists).
        fallback_target: Default target when a constraint is uncovered, or None.
        aggregated_keys: Set/dict of base keys that have extras, or None.

    Returns:
        Starlark expression string (encoded label or `select({...})`).
    """
    effective_all = all_target_dict if all_target_dict != None else target_dict
    if len(effective_all) == 1 and "" in effective_all and "" in target_dict:
        t = target_dict[""]
        if is_aggregated:
            t = aggregated_key(t, aggregated_keys)
        return json.encode(prefix + t)

    lines = ["select({"]
    for constraint in effective_all.keys():
        if constraint in target_dict:
            t_base = target_dict[constraint]
            if is_aggregated:
                # Only versions that actually have extras get an [_all_] target.
                t_base = aggregated_key(t_base, aggregated_keys)
            target_label = prefix + t_base
        elif fallback_target:
            target_label = fallback_target
        else:
            continue

        if constraint == "":
            lines.append('        "//conditions:default": {},'.format(json.encode(target_label)))
        else:
            lines.append("        {}: {},".format(json.encode("@{}//_lock:is_{}".format(workspace_repo, constraint)), json.encode(target_label)))

    # Add the uncovered-branch fallback (only if not already present via "").
    # When the select touches a conflict set, also add an explicit
    # _unselected_<set> condition -> _no_variant_<set> so unselected variants fail
    # clearly while platform-incompatible selected variants still fall through to default.
    # Variant defaults come from this repo's transition (`_default_<set>`), not from
    # //conditions:default.
    if "" not in effective_all:
        unselected = unselected_branch(effective_all.keys(), no_variant_fallbacks, workspace_repo)
        if unselected:
            lines.append("        {}: {},".format(json.encode(unselected[0]), json.encode(NO_VARIANT_PREFIX + unselected[1])))
        if fallback_target:
            lines.append('        "//conditions:default": {},'.format(json.encode(fallback_target)))

    lines.append("    })")
    return "\n".join(lines)

def proxy_actual(actual_lines, target_dict, prefix, workspace_repo, alias_name, actual_pkg_ref, has_transition = False, is_aggregated = False, no_variant_fallbacks = None, all_target_dict = None, fallback_target = NO_MATCH_ERROR_TARGET, aggregated_keys = None):
    """Emit an intermediate select alias if needed, return the actual expression for the proxy.

    When transitions are active (has_transition is True) and target_dict has variants
    or resolution-marker forks (would generate a select()), we emit an intermediate alias in the
    __actual/<pkg> package so the select() is evaluated in the transitioned configuration rather
    than before the transition applies.

    Args:
        actual_lines: Output list of BUILD lines for `__actual/<pkg>/BUILD.bazel`.
        target_dict: Constraint -> package key mapping.
        prefix: Label prefix (e.g. `@ws//_lock:`).
        workspace_repo: Name of the workspace (backing) repo.
        alias_name: Name of the intermediate alias in `__actual/<pkg>`.
        actual_pkg_ref: Package reference for `__actual/<pkg>`.
        has_transition: Whether the proxy rule applies a configuration transition.
        is_aggregated: Whether to rewrite base keys to `[_all_]` aggregates.
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        all_target_dict: Full constraint dict when rendering a partial subset.
        fallback_target: Default target when a constraint is uncovered, or None.
        aggregated_keys: Set/dict of base keys that have extras, or None.

    Returns:
        Starlark expression string (with trailing comma) for the proxy's `actual` attr.
    """
    effective_all = all_target_dict if all_target_dict != None else target_dict
    actual = target_select(
        target_dict,
        prefix,
        workspace_repo,
        is_aggregated = is_aggregated,
        no_variant_fallbacks = no_variant_fallbacks,
        all_target_dict = all_target_dict,
        fallback_target = fallback_target,
        aggregated_keys = aggregated_keys,
    )
    if has_transition and not (len(effective_all) == 1 and "" in effective_all and "" in target_dict):
        actual_lines.extend([
            "alias(",
            "    name = {},".format(json.encode(alias_name)),
            "    actual = {},".format(actual),
            ")",
            "",
        ])
        return "{},".format(json.encode("{}:{}".format(actual_pkg_ref, alias_name)))
    return "{},".format(actual)
