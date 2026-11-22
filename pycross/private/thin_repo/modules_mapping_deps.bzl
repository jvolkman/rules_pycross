"""Conditional deps computation for `pycross_modules_mapping` in thin package repos."""

load("//pycross/private:util.bzl", "sanitize_name")
load(":common.bzl", "is_key_platform_specific")
load(":selects.bzl", "unselected_all_name")

def modules_mapping_deps(pins, packages, workspace_repo, variant_info = None, no_variant_fallbacks = None, pins_by_set = None, excluded = None, resolution_marker_exprs = None):
    """Compute conditional `deps` lines and helper config_setting_groups for `pycross_modules_mapping`.

    Resolution-marker forks and pinned/defaulted repo variants are selected on
    their active condition so inactive forks are never analyzed or fetched.
    Unpinned conflict variants without a repo default remain unioned when no
    variant flag is set (via `_unselected_<set>`), while narrowing to the active
    variant when a flag is set.

    Args:
        pins: Normalized pin dict mapping pin name -> `{constraint: pkg_key}`.
        packages: Lock packages dict.
        workspace_repo: Name of the workspace (backing) repo.
        variant_info: Result of `collect_variants`, or None.
        no_variant_fallbacks: Result of `variant_fallbacks`, or None.
        pins_by_set: Dict of set suffix -> pinned qname, or None.
        excluded: Set/dict of qnames excluded by pins, or None.
        resolution_marker_exprs: Lock `resolution_marker_exprs` dict, or None.

    Returns:
        `struct(deps_lines, extra_target_lines, maybe_mapping_targets, needs_selects)`.
    """
    pins_by_set = pins_by_set or {}
    excluded = excluded or {}
    resolution_marker_exprs = resolution_marker_exprs or {}
    variant_sets = variant_info.sets if variant_info else {}
    sets_by_constraint = no_variant_fallbacks.sets if no_variant_fallbacks else {}

    maybe_mapping_targets = {}  # maybe_name -> (pkg_key, lock_label)
    unconditional = {}  # dep_label -> True
    conditional = {}  # dep_label -> {constraint: True}

    for pin_name in sorted(pins.keys()):
        pin_target_dict = pins[pin_name]
        for constraint, pin_target in sorted(pin_target_dict.items()):
            package = packages.get(pin_target, {})
            if package.get("cycle_group"):
                lock_label = "@%s//_lock:_raw_%s" % (workspace_repo, pin_target)
            else:
                lock_label = "@%s//_lock:%s" % (workspace_repo, pin_target)

            if is_key_platform_specific(packages, pin_target):
                maybe_name = sanitize_name(pin_target)
                maybe_mapping_targets[maybe_name] = (pin_target, lock_label)
                dep_label = "//__maybe:%s" % maybe_name
            else:
                dep_label = lock_label

            if constraint == "":
                unconditional[dep_label] = True
            else:
                conditional.setdefault(dep_label, {})[constraint] = True

    extra_target_lines = []
    emitted_unselected_compounds = {}
    emitted_any_groups = {}
    by_cond = {}  # condition_label -> [dep_label, ...]

    for dep_label in sorted(conditional.keys()):
        if dep_label in unconditional:
            continue
        conds_set = {}
        for constraint in sorted(conditional[dep_label].keys()):
            conds_set["@{}//_lock:is_{}".format(workspace_repo, constraint)] = True

            # Check whether this constraint belongs to an unpinned conflict variant
            # (either bare variant qname or compound {variant, marker}).
            expr = resolution_marker_exprs.get(constraint)
            if type(expr) == "dict" and expr.get("variant"):
                variant_qname = expr["variant"]
                marker_cname = expr.get("marker")
            else:
                variant_qname = constraint
                marker_cname = None

            v_sets = sets_by_constraint.get(variant_qname, [])
            if not v_sets or variant_qname in excluded:
                continue

            # If any set containing this variant has a pin or non-excluded
            # default, do not union it via _unselected_: when pinned/defaulted
            # to this variant, @ws//_lock:is_<v> already activates under the
            # repo's transition; when pinned/defaulted to a rival (or when a
            # rival CLI flag is passed in that set), unioning an unselected
            # sibling set would falsely pull this variant in.
            has_pin_or_default = False
            for s in v_sets:
                if s in pins_by_set:
                    has_pin_or_default = True
                    break
                vset = variant_sets.get(s)
                if vset and vset.default and vset.default not in excluded:
                    has_pin_or_default = True
                    break
            if has_pin_or_default:
                continue

            unpinned_sets = sorted(v_sets)
            if len(unpinned_sets) == 1:
                unselected_cond = "@{}//_lock:_unselected_{}".format(workspace_repo, unpinned_sets[0])
            else:
                group_name = unselected_all_name(unpinned_sets)
                no_variant_fallbacks.groups[group_name] = unpinned_sets
                unselected_cond = "//_variants:{}".format(group_name)

            if marker_cname:
                comp_name = "_mm_unselected_{}".format(sanitize_name(constraint))
                if comp_name not in emitted_unselected_compounds:
                    emitted_unselected_compounds[comp_name] = True
                    extra_target_lines.extend([
                        "selects.config_setting_group(",
                        '    name = "{}",'.format(comp_name),
                        "    match_all = [",
                        '        "{}",'.format(unselected_cond),
                        '        "@{}//_lock:is_{}",'.format(workspace_repo, marker_cname),
                        "    ],",
                        ")",
                        "",
                    ])
                conds_set[":{}".format(comp_name)] = True
            else:
                conds_set[unselected_cond] = True

        conds = sorted(conds_set.keys())
        if len(conds) == 1:
            group_cond = conds[0]
        else:
            conds_key = tuple(conds)
            if conds_key not in emitted_any_groups:
                any_name = "_mm_any_%x" % (hash("|".join(conds)) & 0xffffffff)
                emitted_any_groups[conds_key] = any_name
                extra_target_lines.extend([
                    "selects.config_setting_group(",
                    '    name = "{}",'.format(any_name),
                    "    match_any = [",
                ])
                for cond in conds:
                    extra_target_lines.append('        "{}",'.format(cond))
                extra_target_lines.extend([
                    "    ],",
                    ")",
                    "",
                ])
            group_cond = ":{}".format(emitted_any_groups[conds_key])
        by_cond.setdefault(group_cond, []).append(dep_label)

    deps_lines = ["    deps = ["]
    for dep_label in sorted(unconditional.keys()):
        deps_lines.append('        "{}",'.format(dep_label))
    deps_lines.append("    ]")
    for cond in sorted(by_cond.keys()):
        deps_lines[-1] = deps_lines[-1] + " + select({"
        deps_lines.append('        "{}": ['.format(cond))
        for dep_label in sorted(by_cond[cond]):
            deps_lines.append('            "{}",'.format(dep_label))
        deps_lines.append("        ],")
        deps_lines.append('        "//conditions:default": [],')
        deps_lines.append("    })")
    deps_lines[-1] = deps_lines[-1] + ","

    return struct(
        deps_lines = deps_lines,
        extra_target_lines = extra_target_lines,
        maybe_mapping_targets = maybe_mapping_targets,
        needs_selects = bool(extra_target_lines),
    )
