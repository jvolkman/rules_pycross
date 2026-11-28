"""Select expression and variant fallback helpers for thin package repos."""

load("//pycross/private:build_text.bzl", "alias", "select_expr")
load("//pycross/private:lock_contract.bzl", "lock_constraint_label", "lock_unselected_label")
load(":common.bzl", "NO_MATCH_ERROR_TARGET", "NO_VARIANT_PREFIX")

def variant_fallbacks(sets_by_constraint):
    """Build the no-variant fallback info for this repo's selects.

    Args:
        sets_by_constraint: {constraint: [conflict set suffixes]} for each
            constraint that needs a variant.

    Returns:
        `struct(sets)` mapping each variant-gated constraint to its conflict set suffixes.
    """
    return struct(sets = sets_by_constraint)

def unselected_all_name(set_suffixes):
    """Return the deterministic `_unselected_all_<hash>` target name for `set_suffixes`."""
    return "_unselected_all_%x" % (hash("|".join(set_suffixes)) & 0xffffffff)

def unselected_condition(set_suffixes, workspace_repo, local_prefix = "//_variants:"):
    """Return the condition label matching when every conflict set in `set_suffixes` is unselected.

    For a single set, points directly at `@<workspace_repo>//_lock:_unselected_<set>`.
    For multiple sets, returns a `_unselected_all_<hash>` label under `local_prefix`
    alongside the `{group_name: set_suffixes}` dict for `variants_build` to emit.

    Args:
        set_suffixes: Sorted non-empty list of conflict set suffixes.
        workspace_repo: Name of the workspace (backing) repo.
        local_prefix: Label prefix for multi-set `_unselected_all_*` groups (`"//_variants:"` or `":"`).

    Returns:
        `struct(condition, groups)` with the config_setting label and any required `_unselected_all_*` groups.
    """
    if len(set_suffixes) == 1:
        return struct(
            condition = lock_unselected_label(workspace_repo, set_suffixes[0]),
            groups = {},
        )
    name = unselected_all_name(set_suffixes)
    return struct(
        condition = local_prefix + name,
        groups = {name: set_suffixes},
    )

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
        `struct(condition, error_set, unselected_groups)`, or None.
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
    res = unselected_condition(set_suffixes, workspace_repo)
    return struct(
        condition = res.condition,
        error_set = error_set,
        unselected_groups = res.groups,
    )

def target_select(target_dict, prefix, workspace_repo, no_variant_fallbacks = None, all_target_dict = None, fallback_target = NO_MATCH_ERROR_TARGET):
    """Render a target label or `select({...})` mapping constraints to lock targets.

    Args:
        target_dict: Constraint -> package key mapping to render.
        prefix: Label prefix (e.g. `@ws//_lock:`).
        workspace_repo: Name of the workspace (backing) repo.
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        all_target_dict: Full constraint dict when rendering a partial subset (e.g. sdists).
        fallback_target: Default target when a constraint is uncovered, or None.

    Returns:
        `struct(expr, label, unselected_groups)` where `expr` is the Starlark expression
        string (encoded label or `select({...})`), `label` is the raw target label when
        unconditional (else None), and `unselected_groups` maps any required
        `_unselected_all_*` group names to their set suffixes.
    """
    effective_all = all_target_dict if all_target_dict != None else target_dict
    if len(effective_all) == 1 and "" in effective_all and "" in target_dict:
        label = prefix + target_dict[""]
        return struct(expr = json.encode(label), label = label, unselected_groups = {})

    branches = []
    for constraint in effective_all.keys():
        if constraint in target_dict:
            target_label = prefix + target_dict[constraint]
        elif fallback_target:
            target_label = fallback_target
        else:
            continue

        if constraint == "":
            branches.append(("//conditions:default", target_label))
        else:
            branches.append((lock_constraint_label(workspace_repo, constraint), target_label))

    # Add the uncovered-branch fallback (only if not already present via "").
    # When the select touches a conflict set, also add an explicit
    # _unselected_<set> condition -> _no_variant_<set> so unselected variants fail
    # clearly while platform-incompatible selected variants still fall through to default.
    # Variant defaults come from this repo's transition (`d:<set>` in `//_lock:_state`), not from
    # //conditions:default.
    default_target = None
    unselected_groups = {}
    if "" not in effective_all:
        unselected = unselected_branch(effective_all.keys(), no_variant_fallbacks, workspace_repo)
        if unselected:
            branches.append((unselected.condition, NO_VARIANT_PREFIX + unselected.error_set))
            unselected_groups.update(unselected.unselected_groups)
        if fallback_target:
            default_target = fallback_target

    return struct(
        expr = select_expr(branches, default = default_target, indent = 1),
        label = None,
        unselected_groups = unselected_groups,
    )

def proxy_actual(actual_lines, target_dict, prefix, workspace_repo, alias_name, actual_pkg_ref, has_transition = False, no_variant_fallbacks = None, all_target_dict = None, fallback_target = NO_MATCH_ERROR_TARGET):
    """Emit an intermediate select alias if needed, returning the actual expression and label.

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
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        all_target_dict: Full constraint dict when rendering a partial subset.
        fallback_target: Default target when a constraint is uncovered, or None.

    Returns:
        `struct(expr, label, unselected_groups)` where `expr` is the Starlark expression
        (without a trailing comma), `label` is the target label (always non-None when
        `has_transition` is True or `target_dict` is unconditional), and `unselected_groups`
        collects any required `_unselected_all_*` groups.
    """
    sel = target_select(
        target_dict,
        prefix,
        workspace_repo,
        no_variant_fallbacks = no_variant_fallbacks,
        all_target_dict = all_target_dict,
        fallback_target = fallback_target,
    )
    if has_transition and sel.label == None:
        actual_lines.extend(alias(alias_name, sel.expr, actual_is_expr = True))
        label = "{}:{}".format(actual_pkg_ref, alias_name)
        return struct(expr = json.encode(label), label = label, unselected_groups = sel.unselected_groups)
    return sel
