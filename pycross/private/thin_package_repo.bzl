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

load("@pycross_backends//:package_repo_dispatch.bzl", "PACKAGE_REPO_HOOKS")
load(":override_helpers.bzl", "merge_backend_overrides")
load(":util.bzl", "is_platform_specific", "is_wheel_platform_specific", "marker_evaluator_name", "parse_package_key", "sanitize_name", "underscore_name", "variant_item_qname")

_requirement_func = """\
load("@pypackaging.bzl", "pypackaging")

def requirement(pkg):
    extra = None
    if "[" in pkg:
        pkg, extra = pkg.split("[", 1)
        extra = pypackaging.utils.canonicalize_name(extra.rstrip("]"))

    pkg = pypackaging.utils.canonicalize_name(pkg)
    pkg_dir = pkg.replace("-", "_")

    if extra:
        return "@@{repo_name}//%s:[%s]" % (pkg_dir, extra)
    return "@@{repo_name}//%s" % (pkg_dir)
"""

def _is_key_platform_specific(packages, pkg_key):
    """Like is_platform_specific, but an extras key also inherits its base package's availability."""
    if is_platform_specific(packages.get(pkg_key, {})):
        return True
    parts = parse_package_key(pkg_key)
    if parts.extra:
        return is_platform_specific(packages.get("{}@{}".format(parts.name, parts.version), {}))
    return False

def _requirements_bzl(rctx, pins, packages, testonly_pins = {}):
    entries = {False: [], True: []}  # testonly -> requirement labels
    for pin in sorted(pins.keys()):
        pin_target_dict = pins[pin]
        pin_parts = parse_package_key(pin)

        # Route through :maybe when any variant of this pin is platform-specific
        # OR when the pin has no unconditional branch (variant-only / partial fork),
        # so inactive variants/forks become _empty_library instead of no_match_error.
        is_conditional = "" not in pin_target_dict
        if not is_conditional:
            for pkg_key in pin_target_dict.values():
                if _is_key_platform_specific(packages, pkg_key):
                    is_conditional = True
                    break

        us_pin = underscore_name(pin_parts.name)
        if pin_parts.extra:
            if is_conditional:
                label = "@@{repo_name}//{pin}:[{extra}]_maybe".format(repo_name = rctx.name, pin = us_pin, extra = pin_parts.extra)
            else:
                label = "@@{repo_name}//{pin}:[{extra}]".format(repo_name = rctx.name, pin = us_pin, extra = pin_parts.extra)
        elif is_conditional:
            label = "@@{repo_name}//{pin}:{maybe}".format(repo_name = rctx.name, pin = us_pin, maybe = _safe_name(us_pin, "maybe"))
        else:
            label = "@@{repo_name}//{pin}".format(repo_name = rctx.name, pin = us_pin)
        entries[pin in testonly_pins or pin_parts.name in testonly_pins].append(label)

    lines = [
        _requirement_func.format(repo_name = rctx.name),
        "",
        "# All pinned requirements, excluding testonly ones",
        "all_requirements = [",
    ]
    lines.extend(['    "{}",'.format(label) for label in entries[False]])
    lines.extend([
        "]",
        "",
        "# All testonly pinned requirements",
        "all_testonly_requirements = [",
    ])
    lines.extend(['    "{}",'.format(label) for label in entries[True]])
    lines.append("]")
    return "\n".join(lines) + "\n"

def _flag_values(flags):
    """Parse `--label[=value]` flags (validated by the extension) into label -> values.

    Values keep declaration order; a flag without a value means "True".
    """
    values = {}
    for f in flags:
        label, sep, value = f[2:].partition("=")
        values.setdefault(label, []).append(value if sep else "True")
    return values

def _safe_name(pin_name, name):
    return name + "_" if pin_name == name else name

_NO_MATCH_ERROR_TARGET = "@rules_pycross//pycross/private:no_match_error"

# Per-repo "no variant selected" targets, emitted in _variants/BUILD.bazel with this repo's flag names.
_NO_VARIANT_PREFIX = "//_variants:_no_variant_"

def _aggregated_key(pkg_key, aggregated_keys):
    """Return the [_all_] aggregate key for pkg_key, unless aggregated_keys says it has no extras."""
    parts = parse_package_key(pkg_key)
    if aggregated_keys != None and "{}@{}".format(parts.name, parts.version) not in aggregated_keys:
        return pkg_key
    return "{}[_all_]@{}".format(parts.name, parts.version)

def _variant_fallbacks(sets_by_constraint):
    """Build the no-variant fallback info for this repo's selects.

    Args:
        sets_by_constraint: {constraint: [conflict set suffixes]} for each
            constraint that needs a variant.

    Returns:
        struct(sets, groups). `groups` collects the `_unselected_all_<hash>`
        targets that selects reference, for _variants_build to emit.
    """
    return struct(sets = sets_by_constraint, groups = {})

def _unselected_all_name(set_suffixes):
    return "_unselected_all_%x" % (hash("|".join(set_suffixes)) & 0xffffffff)

def _unselected_branch(constraints, no_variant_fallbacks, workspace_repo):
    """The select() branch for "no variant selected", or None.

    It matches only when every conflict set that the constraints touch is
    unselected. An item can be in several sets (`[[cpu, gpu], [cpu, gpu-test]]`),
    and if any of them is selected, one of the select's own conditions decides.

    Args:
        constraints: The select's constraint keys.
        no_variant_fallbacks: Result of _variant_fallbacks, or None.
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
    name = _unselected_all_name(set_suffixes)
    no_variant_fallbacks.groups[name] = set_suffixes
    return ("//_variants:" + name, error_set)

def _target_select(target_dict, prefix, suffix, workspace_repo, is_aggregated = False, no_variant_fallbacks = None, all_target_dict = None, fallback_target = _NO_MATCH_ERROR_TARGET, aggregated_keys = None):
    effective_all = all_target_dict if all_target_dict != None else target_dict
    if len(effective_all) == 1 and "" in effective_all and "" in target_dict:
        t = target_dict[""]
        if is_aggregated:
            t = _aggregated_key(t, aggregated_keys)
        return '"{}{}{}"'.format(prefix, t, suffix)

    lines = ["select({"]
    for constraint in effective_all.keys():
        if constraint in target_dict:
            t_base = target_dict[constraint]
            if is_aggregated:
                # Only versions that actually have extras get an [_all_] target.
                t_base = _aggregated_key(t_base, aggregated_keys)
            target_label = "{}{}{}".format(prefix, t_base, suffix)
        elif fallback_target:
            target_label = fallback_target
        else:
            continue

        if constraint == "":
            lines.append('        "//conditions:default": "{}",'.format(target_label))
        else:
            lines.append('        "@{}//_lock:is_{}": "{}",'.format(workspace_repo, constraint, target_label))

    # Add the uncovered-branch fallback (only if not already present via "").
    # When the select touches a conflict set, also add an explicit
    # _unselected_<set> condition -> _no_variant_<set> so unselected variants fail
    # clearly while platform-incompatible selected variants still fall through to default.
    # Variant defaults come from this repo's transition (`_default_<set>`), not from
    # //conditions:default.
    if "" not in effective_all:
        unselected = _unselected_branch(effective_all.keys(), no_variant_fallbacks, workspace_repo)
        if unselected:
            lines.append('        "{}": "{}{}",'.format(unselected[0], _NO_VARIANT_PREFIX, unselected[1]))
        if fallback_target:
            lines.append('        "//conditions:default": "{}",'.format(fallback_target))

    lines.append("    })")
    return "\n".join(lines)

def _proxy_actual(actual_lines, target_dict, prefix, suffix, workspace_repo, alias_name, actual_pkg_ref, has_transition = False, is_aggregated = False, no_variant_fallbacks = None, all_target_dict = None, fallback_target = _NO_MATCH_ERROR_TARGET, aggregated_keys = None):
    """Emit an intermediate select alias if needed, return the actual expression for the proxy.

    When transitions are active (has_transition is True) and target_dict has variants
    or resolution-marker forks (would generate a select()), we emit an intermediate alias in the
    __actual/<pkg> package so the select() is evaluated in the transitioned configuration rather
    than before the transition applies.
    """
    effective_all = all_target_dict if all_target_dict != None else target_dict
    actual = _target_select(
        target_dict,
        prefix,
        suffix,
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
            '    name = "{}",'.format(alias_name),
            "    actual = {},".format(actual),
            ")",
            "",
        ])
        return '"{}:{}",'.format(actual_pkg_ref, alias_name)
    return "{},".format(actual)

def _availability_condition(lines, helper_prefix, lock_key, packages, workspace_repo):
    """Return a config_setting label for a package's availability in this thin repo.

    Composes this member's own `availability_markers` (via `@ws//_lock:<eval>_match`)
    with `@ws//_lock:_wheel_available_<pkg>` when wheel selection is platform-specific,
    so different workspace members with different root platform markers never clobber
    each other in the shared `@ws//_lock` package.
    """
    if packages == None:
        return "@{}//_lock:_available_{}".format(workspace_repo, lock_key)

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
        return "@{}//_lock:_available_{}".format(workspace_repo, lock_key)
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

def _emit_maybe_alias(lines, maybe_name, pkg_target, target_dict, available_keys, workspace_repo, no_variant_fallbacks = None, helper_prefix = "_maybe", packages = None, is_testonly = False):
    """Emit a `:maybe` or `:[extra]_maybe` alias supporting both single-branch and multi-branch pins."""
    available_set = {k: True for k in (available_keys or [])}
    if not target_dict or (not available_set and "" in target_dict):
        return

    if len(target_dict) == 1 and "" in target_dict:
        only_key = target_dict[""]
        if only_key not in available_set:
            fail("Single-branch target '{}' not found in available_keys {}".format(only_key, available_keys))
        avail_cond = _availability_condition(lines, helper_prefix, only_key, packages, workspace_repo)
        lines.extend([
            "alias(",
            '    name = "{}",'.format(maybe_name),
            "    actual = select({",
            '        "{}": "{}",'.format(avail_cond, pkg_target),
            '        "//conditions:default": "//:_empty_library",',
            "    }),",
        ])
        if is_testonly:
            lines.append("    testonly = True,")
        lines.extend([")", ""])
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
            avail_cond = _availability_condition(lines, helper_prefix, pkg_key, packages, workspace_repo)
            lines.extend([
                "alias(",
                '    name = "{}",'.format(helper_name),
                "    actual = select({",
                '        "{}": "{}",'.format(avail_cond, pkg_target),
                '        "//conditions:default": "//:_empty_library",',
                "    }),",
            ])
            if is_testonly:
                lines.append("    testonly = True,")
            lines.extend([")", ""])
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
        unselected = _unselected_branch(branch_targets.keys(), no_variant_fallbacks, workspace_repo)
        if unselected:
            lines.append('        "{}": "{}{}",'.format(unselected[0], _NO_VARIANT_PREFIX, unselected[1]))
        lines.append('        "//conditions:default": "//:_empty_library",')

    lines.append("    }),")
    if is_testonly:
        lines.append("    testonly = True,")
    lines.extend([")", ""])

def _pin_build(target_name, pin_target_dict, package, workspace_repo, has_aggregated_variant = False, extras_dict = None, no_variant_fallbacks = None, target_platform = None, transition_bzl = None, maybe_available_keys = None, extras_maybe_keys = None, testonly = False, sdist_target_dict = None, aggregated_keys = None, packages = None):
    """Generates the BUILD file for a pin directory, pointing to the workspace."""
    lock_target_dict = pin_target_dict
    lock_ref = "@{}//_lock:".format(workspace_repo)
    wheel_ref = "@{}//_wheel:".format(workspace_repo)
    sdist_ref = "@{}//_sdist:".format(workspace_repo)

    actual_lines = []
    actual_pkg_ref = "//__actual/{}".format(target_name)

    if transition_bzl:
        # Flags-based transition: use generated transitioning rules.
        proxy_load = 'load("{}", "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")'.format(transition_bzl)
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    elif target_platform:
        # Platform-only transition: use built-in transitioning rules.
        proxy_load = 'load("@rules_pycross//pycross/private:proxy.bzl", "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")'
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    else:
        # No transition.
        proxy_load = 'load("@rules_pycross//pycross/private:proxy.bzl", "pycross_file_proxy", "pycross_library_proxy")'
        lib_rule = "pycross_library_proxy"
        file_rule = "pycross_file_proxy"

    lines = []

    has_transition = bool(transition_bzl or target_platform)

    def _emit_proxy(rule_name, name, actual, is_testonly = False):
        lines.extend([
            rule_name + "(",
            '    name = "{}",'.format(name),
            "    actual = {}".format(actual),
        ])
        if is_testonly:
            lines.append("    testonly = True,")
        if target_platform:
            lines.append('    platform = "{}",'.format(target_platform))
        lines.extend([")", ""])

    actual_pkg = None
    if lock_target_dict:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(target_name),
            '    actual = ":{}",'.format(_safe_name(target_name, "pkg")),
            ")",
            "",
        ])
        actual_pkg = _proxy_actual(actual_lines, lock_target_dict, lock_ref, "", workspace_repo, "pkg", actual_pkg_ref, has_transition = has_transition, is_aggregated = has_aggregated_variant, no_variant_fallbacks = no_variant_fallbacks, aggregated_keys = aggregated_keys)
        _emit_proxy(lib_rule, _safe_name(target_name, "pkg"), actual_pkg, is_testonly = testonly)

        actual_wheel = _proxy_actual(actual_lines, pin_target_dict, wheel_ref, "", workspace_repo, "wheel", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        _emit_proxy(file_rule, _safe_name(target_name, "wheel"), actual_wheel)

        actual_dist_info = _proxy_actual(actual_lines, lock_target_dict, lock_ref + "_dist_info_", "", workspace_repo, "dist_info", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        _emit_proxy(file_rule, _safe_name(target_name, "dist_info"), actual_dist_info)
        lines.extend([
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "data")),
            '    actual = ":{}",'.format(_safe_name(target_name, "pkg")),
            ")",
        ])

        if extras_dict or has_aggregated_variant:
            if not has_aggregated_variant:
                lines.extend([
                    "alias(",
                    '    name = "[]",',
                    '    actual = ":{}",'.format(_safe_name(target_name, "pkg")),
                    ")",
                    "",
                ])
            else:
                actual_all = _proxy_actual(actual_lines, lock_target_dict, lock_ref, "", workspace_repo, "all", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
                _emit_proxy(lib_rule, "[]", actual_all, is_testonly = testonly)

        effective_sdist_dict = sdist_target_dict
        if effective_sdist_dict == None and package.get("sdist_file"):
            effective_sdist_dict = pin_target_dict
        if effective_sdist_dict:
            actual_sdist = _proxy_actual(
                actual_lines,
                effective_sdist_dict,
                sdist_ref,
                "",
                workspace_repo,
                "sdist",
                actual_pkg_ref,
                has_transition = has_transition,
                no_variant_fallbacks = no_variant_fallbacks,
                all_target_dict = pin_target_dict,
                fallback_target = _NO_MATCH_ERROR_TARGET,
            )
            _emit_proxy(file_rule, _safe_name(target_name, "sdist"), actual_sdist)

    extras_dict = extras_dict or {}
    extras_maybe_keys = extras_maybe_keys or {}
    for extra_name, extra_target_dict in sorted(extras_dict.items()):
        actual_extra = _proxy_actual(actual_lines, extra_target_dict, lock_ref, "", workspace_repo, "extra_{}".format(extra_name), actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        _emit_proxy(lib_rule, "[{}]".format(extra_name), actual_extra, is_testonly = testonly)
        extra_maybe = extras_maybe_keys.get(extra_name)
        if extra_target_dict and (extra_maybe or "" not in extra_target_dict):
            if has_transition:
                actual_extra_maybe = "extra_{}_maybe".format(extra_name)
                _emit_maybe_alias(
                    actual_lines,
                    actual_extra_maybe,
                    actual_extra.rstrip(",").strip('"'),
                    extra_target_dict,
                    extra_maybe,
                    workspace_repo,
                    no_variant_fallbacks = no_variant_fallbacks,
                    helper_prefix = "_maybe_extra_{}".format(extra_name),
                    packages = packages,
                )
                _emit_proxy(lib_rule, "[{}]_maybe".format(extra_name), '"{}:{}",'.format(actual_pkg_ref, actual_extra_maybe), is_testonly = testonly)
            else:
                _emit_maybe_alias(
                    lines,
                    "[{}]_maybe".format(extra_name),
                    ":[{}]".format(extra_name),
                    extra_target_dict,
                    extra_maybe,
                    workspace_repo,
                    no_variant_fallbacks = no_variant_fallbacks,
                    helper_prefix = "_maybe_extra_{}".format(extra_name),
                    packages = packages,
                    is_testonly = testonly,
                )

    if lock_target_dict and (maybe_available_keys or "" not in lock_target_dict):
        maybe_name = _safe_name(target_name, "maybe")
        pkg_name = _safe_name(target_name, "pkg")
        if has_transition:
            _emit_maybe_alias(
                actual_lines,
                "maybe",
                actual_pkg.rstrip(",").strip('"'),
                lock_target_dict,
                maybe_available_keys,
                workspace_repo,
                no_variant_fallbacks = no_variant_fallbacks,
                helper_prefix = "_maybe",
                packages = packages,
            )
            _emit_proxy(lib_rule, maybe_name, '"{}:maybe",'.format(actual_pkg_ref), is_testonly = testonly)
        else:
            _emit_maybe_alias(
                lines,
                maybe_name,
                ":{}".format(pkg_name),
                lock_target_dict,
                maybe_available_keys,
                workspace_repo,
                no_variant_fallbacks = no_variant_fallbacks,
                helper_prefix = "_maybe",
                packages = packages,
                is_testonly = testonly,
            )

    header_lines = [proxy_load]
    if any(["selects.config_setting_group(" in line for line in lines]):
        header_lines.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    header_lines.extend([
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])

    actual_build = None
    if actual_lines:
        actual_header = []
        if any(["selects.config_setting_group(" in line for line in actual_lines]):
            actual_header.extend(['load("@bazel_skylib//lib:selects.bzl", "selects")', ""])
        actual_header.extend([
            'package(default_visibility = ["//{}:__pkg__"])'.format(target_name),
            "",
        ])
        actual_build = "\n".join(actual_header + actual_lines) + "\n"

    return struct(
        build = "\n".join(header_lines + lines) + "\n",
        actual_build = actual_build,
    )

def _collect_variants(variant_sets):
    """Collect this repo's variant flags, conflict sets and defaults from its lock.

    Args:
        variant_sets: The lock's `variants` list.

    Returns:
        struct(
            flags = {flag: [qnames]},  # this repo's _variants flags and the items they enable
            sets = {set_suffix: struct(qnames, flags, default, pin, requested)},
        )
    """
    flags = {}
    sets = {}
    for variant_set in variant_sets:
        qnames = []
        display_items = []
        set_flags = {}  # flag -> [qnames in this set]
        item_flags = []  # (qname, [flags])
        for item in variant_set["items"]:
            qname = variant_item_qname(item)
            qnames.append(qname)
            pkg = item.get("package", "")
            kind = item.get("kind", "")
            iname = item.get("name", "")
            if kind == "extra" and iname:
                display_items.append("{}[{}]".format(pkg, iname) if pkg else "extra '{}'".format(iname))
            elif kind == "group" and iname:
                display_items.append("{}:{}".format(pkg, iname) if pkg else "group '{}'".format(iname))
            elif kind == "project" and pkg:
                display_items.append(pkg)
            else:
                display_items.append(qname)
            item_flags.append((qname, item.get("flags", [])))
            for flag in item.get("flags", []):
                flag_qnames = flags.setdefault(flag, [])
                if qname not in flag_qnames:
                    flag_qnames.append(qname)
                set_flags.setdefault(flag, []).append(qname)

        # For messages: per item, the first of its flags that selects only that
        # item in this set (e.g. `extra_cpu`, or `group_app-a_test` when
        # `group_test` would enable two conflicting items).
        usable = []
        for _, item_flag_list in item_flags:
            for flag in item_flag_list:
                if len(set_flags[flag]) == 1:
                    if flag not in usable:
                        usable.append(flag)
                    break
        if qnames:
            sets["_".join(sorted(qnames))] = struct(
                qnames = qnames,
                display_items = display_items,
                flags = usable,
                default = variant_set.get("repo_default", ""),
                pin = variant_set.get("repo_pin", ""),
                requested = variant_set.get("repo_requested", []),
            )
    return struct(flags = flags, sets = sets)

def _excluded_items(variant_info, pins_by_set):
    """The items that conflict with an item the repo pins.

    Args:
        variant_info: Result of _collect_variants.
        pins_by_set: {set suffix: pinned qname}.

    Returns:
        {qname: True}.
    """
    excluded = {}
    pinned = pins_by_set.values()
    for vset in variant_info.sets.values():
        for qname in pinned:
            if qname not in vset.qnames:
                continue
            for other in vset.qnames:
                if other != qname:
                    excluded[other] = True
    return excluded

def _usable_settings(variant_info, pins_by_set, excluded, workspace_repo):
    """`_usable_<set>` settings for a transitioned repo.

    Variant resolvers read every repo's flags. Inside a repo with its own
    transition, a flag meant for another repo could otherwise activate an item
    that this repo didn't request, or that conflicts with one it pins, and
    switch versions in shared packages. Each unpinned set is limited to the
    items the repo requests that aren't excluded.

    Args:
        variant_info: Result of _collect_variants.
        pins_by_set: {set suffix: pinned qname}.
        excluded: Result of _excluded_items.
        workspace_repo: Name of the workspace (backing) repo.

    Returns:
        {label: space-separated usable qnames} for sets that aren't fully usable.
    """
    result = {}
    for set_suffix, vset in sorted(variant_info.sets.items()):
        if set_suffix in pins_by_set:
            continue
        usable = [q for q in vset.requested if q not in excluded]
        if len(usable) < len(vset.qnames):
            result["@{}//_lock:_usable_{}".format(workspace_repo, set_suffix)] = " ".join(sorted(usable))
    return result

def _transition_settings(variant_info, variant_pins, workspace_repo, member_name, has_other_flags):
    """The `_lock` settings that a repo's transition sets.

    Args:
        variant_info: Result of _collect_variants.
        variant_pins: {set suffix: qname} that the repo's flags/settings select.
        workspace_repo: Name of the workspace (backing) repo.
        member_name: The repo name, for messages.
        has_other_flags: Whether the repo transitions for other reasons (its
            own `flags` or `settings`).

    Returns:
        struct(fixed_settings = {label: value}, pins_by_set, excluded).
    """
    pins_by_set = dict(variant_pins)
    for set_suffix, vset in sorted(variant_info.sets.items()):
        if not vset.pin:
            continue

        # The only item of the set that the repo requests.
        if pins_by_set.get(set_suffix, vset.pin) != vset.pin:
            fail("{}: flags/settings select {}, but the repo requests only {} from that conflict set".format(
                member_name,
                pins_by_set[set_suffix],
                vset.pin,
            ))
        pins_by_set[set_suffix] = vset.pin
    excluded = _excluded_items(variant_info, pins_by_set)

    fixed_settings = {}
    for set_suffix, qname in sorted(pins_by_set.items()):
        fixed_settings["@{}//_lock:_pin_{}".format(workspace_repo, set_suffix)] = qname
    for set_suffix, vset in sorted(variant_info.sets.items()):
        # A default that conflicts with a pin in another set would select both.
        if set_suffix not in pins_by_set and vset.default and vset.default not in excluded:
            fixed_settings["@{}//_lock:_default_{}".format(workspace_repo, set_suffix)] = vset.default
    if has_other_flags or fixed_settings:
        fixed_settings.update(_usable_settings(variant_info, pins_by_set, excluded, workspace_repo))
    return struct(fixed_settings = fixed_settings, pins_by_set = pins_by_set, excluded = excluded)

def _variants_build(variant_info, workspace_repo, repo_name, unselected_groups = None, pins_by_set = None, excluded = None, expose_variant_flags = True):
    """Render _variants/BUILD.bazel: this repo's variant flags.

    The workspace repo's variant resolvers read these bool_flags (see
    package_repo.bzl), so one flag here can enable the same extra/group in
    several projects. `is_<flag>` matches when all of the items the flag
    enables are active. For this repo's default variant, it also matches when
    nothing in the set is selected, so first-party select()s outside the repo's
    transition see the default too.

    Args:
        variant_info: Result of _collect_variants.
        workspace_repo: Name of the workspace (backing) repo.
        repo_name: This repo's apparent name, for messages.
        unselected_groups: {name: [set suffixes]} of `_unselected_all_*`
            groups that the repo's selects reference.
        pins_by_set: {set suffix: qname} this repo's transition pins.
        excluded: {qname: True} of items that conflict with those pins.
        expose_variant_flags: Whether to emit user-facing `_variants` flags and
            `is_<flag>` config_settings (False for auto-generated `<ws>__build`).

    Returns:
        The file content, or None if the repo has no variants.
    """
    flags = variant_info.flags if expose_variant_flags else {}
    if not flags and not variant_info.sets:
        return None

    pins_by_set = pins_by_set or {}
    excluded = excluded or {}
    defaults = {}  # qname -> [all set suffixes containing qname] for repo defaults/pins
    if expose_variant_flags:
        default_qnames = {}
        for set_suffix, vset in variant_info.sets.items():
            sel = pins_by_set.get(set_suffix) or vset.pin
            if not sel and vset.default not in excluded:
                sel = vset.default
            if sel:
                default_qnames[sel] = True
        for qname in default_qnames.keys():
            defaults[qname] = [
                set_suffix
                for set_suffix, vset in variant_info.sets.items()
                if qname in vset.qnames
            ]

    body = []
    needs_selects = False

    # `_selected_<qname>` for each item this repo pins or defaults to: active,
    # or nothing in its sets is selected (outside the repo's transition).
    groups = dict(unselected_groups or {})
    selected = {}  # qname -> condition label
    for qname, set_suffixes in sorted(defaults.items()):
        needs_selects = True
        set_suffixes = sorted(set_suffixes)
        if len(set_suffixes) == 1:
            unselected = "@{}//_lock:_unselected_{}".format(workspace_repo, set_suffixes[0])
        else:
            name = _unselected_all_name(set_suffixes)
            groups[name] = set_suffixes
            unselected = ":" + name
        selected[qname] = '":_selected_{}"'.format(qname)
        body.append("selects.config_setting_group(")
        body.append('    name = "_selected_{}",'.format(qname))
        body.append("    match_any = [")
        body.append('        "@{}//_lock:is_{}",'.format(workspace_repo, qname))
        body.append('        "{}",'.format(unselected))
        body.extend(["    ],", ")", ""])

    # `_unselected_all_<hash>`: all of several conflict sets are unselected.
    for name, set_suffixes in sorted(groups.items()):
        needs_selects = True
        body.append("selects.config_setting_group(")
        body.append('    name = "{}",'.format(name))
        body.append("    match_all = [")
        body.extend(['        "@{}//_lock:_unselected_{}",'.format(workspace_repo, s) for s in set_suffixes])
        body.extend(["    ],", ")", ""])

    if flags:
        body.extend([
            "string_flag(",
            '    name = "_variants",',
            '    build_setting_default = "",',
            ")",
            "",
        ])

    for flag, qnames in sorted(flags.items()):
        body.extend([
            "bool_flag(",
            '    name = "{}",'.format(flag),
            "    build_setting_default = False,",
            ")",
            "",
        ])
        conditions = [selected.get(q, '"@{}//_lock:is_{}"'.format(workspace_repo, q)) for q in qnames]
        if len(qnames) == 1:
            body.extend([
                "alias(",
                '    name = "is_{}",'.format(flag),
                "    actual = {},".format(conditions[0]),
                ")",
                "",
            ])
            continue
        needs_selects = True
        body.append("selects.config_setting_group(")
        body.append('    name = "is_{}",'.format(flag))
        body.append("    match_all = [")
        body.extend(["        {},".format(c) for c in conditions])
        body.extend(["    ],", ")", ""])

    for set_suffix, vset in sorted(variant_info.sets.items()):
        if expose_variant_flags and vset.flags:
            message = "No uv conflict variant selected. Set one of the _variants flags on your pycross repo: {} (e.g. --@{}//_variants:{}=True or --@{}//_variants={})".format(
                ", ".join(vset.flags),
                repo_name,
                vset.flags[0],
                repo_name,
                vset.flags[0],
            )
        else:
            readable_items = ", ".join(vset.display_items)
            message = "No uv conflict variant selected, and @{} has no _variants flag for it ({}). Select it through a repo for the declaring project.".format(
                repo_name,
                readable_items,
            )
        body.extend([
            "pycross_no_variant_selected(",
            '    name = "_no_variant_{}",'.format(set_suffix),
            "    message = {},".format(json.encode(message)),
            ")",
            "",
        ])

    header = ['package(default_visibility = ["//visibility:public"])', ""]
    if needs_selects:
        header.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    if flags:
        header.append('load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "string_flag")')
    if variant_info.sets:
        header.append('load("@rules_pycross//pycross/private:variant_resolver.bzl", "pycross_no_variant_selected")')
    header.append("")
    return "\n".join(header + body)

# Visible for testing
collect_variants_for_testing = _collect_variants
variant_fallbacks_for_testing = _variant_fallbacks
transition_settings_for_testing = _transition_settings
variants_build_for_testing = _variants_build

def _thin_package_repo_impl(rctx):
    workspace_repo = rctx.attr.workspace_repo
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock = json.decode(rctx.read(lock_json_path))
    packages = lock["packages"]
    pins = lock["pins"]
    testonly_pins_set = {p: True for p in lock.get("testonly_pins", [])}

    # Normalize pin values: bare strings (unconditional) become {"": value}
    for pin_name in pins.keys():
        if type(pins[pin_name]) == "string":
            pins[pin_name] = {"": pins[pin_name]}

    # This repo's variant flags and conflict sets. Every set gets an
    # _unselected_<set> -> _no_variant_<set> fallback in selects; defaults come
    # from this repo's transition (`_default_<set>`), not //conditions:default.
    variant_info = _collect_variants(lock.get("variants", []))
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
    no_variant_fallbacks = _variant_fallbacks(sets_by_constraint)

    rctx.file("REPO.bazel", "")
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins, packages, testonly_pins_set))

    # Root BUILD.bazel with //:package aliases

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

    # Generate internal platform + transition if needed
    target_platform = rctx.attr.platform

    # Variant settings this repo's transition sets in the workspace repo:
    # `_pin_<set>` from its flags/settings (computed by the extension) and
    # `_default_<set>` from its projects' default-groups.
    settings = _transition_settings(
        variant_info,
        rctx.attr.variant_pins,
        workspace_repo,
        rctx.attr.member_name,
        has_other_flags = bool(rctx.attr.flags) or bool(rctx.attr.settings),
    )
    fixed_settings = settings.fixed_settings
    pins_by_set = settings.pins_by_set
    excluded = settings.excluded
    has_flags = bool(rctx.attr.flags) or bool(rctx.attr.settings) or bool(fixed_settings)
    has_constraints = bool(rctx.attr.constraint_values)

    if not target_platform and has_constraints:
        target_platform = "//:_internal_platform"

        # Generate the platform target (for constraint_values / toolchain resolution).
        root_build_lines.extend([
            "platform(",
            '    name = "_internal_platform",',
            "    constraint_values = [",
        ])
        for cv in rctx.attr.constraint_values:
            root_build_lines.append('        "{}",'.format(cv))
        root_build_lines.extend([
            "    ],",
            ")",
            "",
        ])

    if has_flags:
        # Bazel's platform(flags=[...]) only applies during top-level platform
        # mapping, NOT when --platforms is set via a Starlark transition.
        # So we generate a _transition.bzl with custom proxy rules whose
        # transition sets the individual flag values (and --platforms, if a
        # platform or constraint_values were given; otherwise the incoming
        # --platforms is kept).

        flag_settings = _flag_values(rctx.attr.flags)

        # Build the transition settings list and the label -> raw values dicts.
        # Values are coerced at analysis time based on the setting's type.
        # Overlap is checked eagerly in the extension and again in _transition.bzl
        # using the generated repo's mapping (which also sees sibling extension repos).
        outputs_lines = []
        return_lines = []
        for label, values in sorted(flag_settings.items()):
            outputs_lines.append('        "{}",'.format(label))
            return_lines.append('    "{}": {},'.format(label, repr(values)))
        settings_lines = []
        for label, value in sorted(rctx.attr.settings.items()):
            outputs_lines.append('        "{}",'.format(label))
            settings_lines.append('    "{}": {},'.format(label, repr(value)))
        fixed_lines = []
        fixed_outputs_lines = []
        for label, value in sorted(fixed_settings.items()):
            fixed_outputs_lines.append('        "{}",'.format(label))
            fixed_lines.append('    "{}": {},'.format(label, repr(value)))

        duplicate_check = ""
        if flag_settings and rctx.attr.settings:
            duplicate_check = (
                "\n_CANONICAL_FLAG_LABELS = {\n" +
                "    Label(label): True\n" +
                "    for label in _FLAG_VALUES\n" +
                '    if not label.startswith("//command_line_option:")\n' +
                "}\n" +
                "for _setting_label in _SETTING_VALUES:\n" +
                "    if Label(_setting_label) in _CANONICAL_FLAG_LABELS:\n" +
                '        fail("Build setting {} is set in both flags and settings".format(_setting_label))\n'
            )

        transition_bzl = """\
\"\"\"Generated transition rules for {repo} with pinned flag values.\"\"\"

load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_pycross//pycross/private:proxy.bzl",
    _file_proxy_impl = "pycross_file_proxy_impl",
    _library_proxy_impl = "pycross_library_proxy_impl",
)
load("@rules_pycross//pycross/private:util.bzl", "PY_COMMON_ATTRS", "coerce_transition_values", "split_setting_value")

_FLAG_VALUES = {{
{return_dict}
}}

_SETTING_VALUES = {{
{settings_dict}
}}

# Variant pins and defaults for the workspace repo's resolvers.
_FIXED_VALUES = {{
{fixed_dict}
}}
{duplicate_check}
def _transition_impl(settings, attr):
    result = {{
        label: coerce_transition_values(settings[label], values)
        for label, values in _FLAG_VALUES.items()
    }}
    for label, value in _SETTING_VALUES.items():
        result[label] = coerce_transition_values(settings[label], split_setting_value(settings[label], value))
    result.update(_FIXED_VALUES)
    if attr.platform:
        result["//command_line_option:platforms"] = [str(attr.platform)]
    else:
        result["//command_line_option:platforms"] = settings["//command_line_option:platforms"]
    return result

_repo_transition = transition(
    implementation = _transition_impl,
    inputs = [
        "//command_line_option:platforms",
{outputs}
    ],
    outputs = [
        "//command_line_option:platforms",
{outputs}
{fixed_outputs}
    ],
)

pycross_transitioning_library_proxy = rule(
    implementation = _library_proxy_impl,
    attrs = dict({{
        "actual": attr.label(
            mandatory = True,
            providers = [PyInfo],
            cfg = _repo_transition,
        ),
        "deps": attr.label_list(
            default = [],
            providers = [PyInfo],
        ),
        "platform": attr.label(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }}, **PY_COMMON_ATTRS),
    provides = [DefaultInfo, PyInfo],
)

pycross_transitioning_file_proxy = rule(
    implementation = _file_proxy_impl,
    attrs = dict({{
        "actual": attr.label(
            mandatory = True,
            cfg = _repo_transition,
        ),
        "platform": attr.label(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }}),
    provides = [DefaultInfo],
)
""".format(
            repo = rctx.attr.member_name,
            return_dict = "\n".join(return_lines),
            settings_dict = "\n".join(settings_lines),
            fixed_dict = "\n".join(fixed_lines),
            duplicate_check = duplicate_check,
            outputs = "\n".join(outputs_lines),
            fixed_outputs = "\n".join(fixed_outputs_lines),
        )
        rctx.file("_transition.bzl", transition_bzl)

    # Collect conditional deps and platform-specific packages for modules_mapping.
    mm = _modules_mapping_deps(
        pins,
        packages,
        workspace_repo,
        variant_info = variant_info,
        no_variant_fallbacks = no_variant_fallbacks,
        pins_by_set = pins_by_set,
        excluded = excluded,
        resolution_marker_exprs = lock.get("resolution_marker_exprs", {}),
    )
    maybe_mapping_targets = mm.maybe_mapping_targets
    if mm.needs_selects:
        root_build_lines.insert(0, 'load("@bazel_skylib//lib:selects.bzl", "selects")')

    # When the repo has a transition, the mapping (and the selects behind its
    # deps) must be analyzed under it, so wrap it in a transitioning proxy.
    if has_flags or target_platform:
        mapping_name = "_modules_mapping"
        if has_flags:
            root_build_lines.insert(0, 'load("//:_transition.bzl", "pycross_transitioning_file_proxy")')
        else:
            root_build_lines.insert(0, 'load("@rules_pycross//pycross/private:proxy.bzl", "pycross_transitioning_file_proxy")')
        root_build_lines.append("pycross_transitioning_file_proxy(")
        root_build_lines.append('    name = "modules_mapping",')
        root_build_lines.append('    actual = ":_modules_mapping",')
        if target_platform:
            root_build_lines.append('    platform = "{}",'.format(target_platform))
        root_build_lines.extend([
            ")",
            "",
        ])
    else:
        mapping_name = "modules_mapping"

    root_build_lines.extend([
        'exports_files(["requirements.bzl", "_packages.bzl"])',
        "",
    ])
    root_build_lines.extend(mm.extra_target_lines)
    root_build_lines.extend([
        "pycross_modules_mapping(",
        '    name = "{}",'.format(mapping_name),
    ])
    root_build_lines.extend(mm.deps_lines)
    root_build_lines.extend([
        ")",
        "",
    ])

    # Generate __maybe/ subdirectory with platform-specific conditional aliases.
    if maybe_mapping_targets:
        maybe_body_lines = []
        for maybe_name, (pkg_key, lock_label) in sorted(maybe_mapping_targets.items()):
            avail_cond = _availability_condition(maybe_body_lines, "_maybe", pkg_key, packages, workspace_repo)
            maybe_body_lines.extend([
                "alias(",
                '    name = "%s",' % maybe_name,
                "    actual = select({",
                '        "%s": "%s",' % (avail_cond, lock_label),
                '        "//conditions:default": ":_empty_library",',
                "    }),",
                ")",
                "",
            ])
        maybe_header_lines = [
            'load("@rules_python//python:defs.bzl", "py_library")',
        ]
        if any(["selects.config_setting_group(" in line for line in maybe_body_lines]):
            maybe_header_lines.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
        maybe_header_lines.extend([
            "",
            "package(default_visibility = [\"//visibility:public\"])",
            "",
            "# Empty library for incompatible platforms.",
            'py_library(name = "_empty_library", visibility = ["//visibility:private"])',
            "",
        ])
        rctx.file("__maybe/BUILD.bazel", "\n".join(maybe_header_lines + maybe_body_lines))

    base_packages_with_extras = {}
    for pkg_key in packages.keys():
        parts = parse_package_key(pkg_key)
        if not parts.extra:
            continue
        base_packages_with_extras["{}@{}".format(parts.name, parts.version)] = True

    if rctx.attr.generate_root_aliases:
        for base_pin_name in sorted(grouped_pins.keys()):
            group = grouped_pins[base_pin_name]
            us_name = underscore_name(base_pin_name)
            base_target = group["base_target"]

            if base_target:
                root_build_lines.extend([
                    "alias(",
                    '    name = "{}",'.format(base_pin_name),
                    '    actual = "//{}:pkg",'.format(us_name),
                    ")",
                ])
                has_aggregated_variant = any([
                    t in base_packages_with_extras
                    for t in base_target.values()
                ])
                if group["extras"] or has_aggregated_variant:
                    root_build_lines.extend([
                        "alias(",
                        '    name = "{}[]",'.format(base_pin_name),
                        '    actual = "//{}:[]",'.format(us_name),
                        ")",
                        "",
                    ])
            elif group["extras"]:
                # If no base target was pinned, but extras were, point the base name at the extras union.
                root_build_lines.extend([
                    "alias(",
                    '    name = "{}",'.format(base_pin_name),
                    '    actual = "//{}:pkg",'.format(us_name),
                    ")",
                    "",
                ])

            for extra_name, _extra_target in sorted(group["extras"].items()):
                root_build_lines.extend([
                    "alias(",
                    '    name = "{}[{}]",'.format(base_pin_name, extra_name),
                    '    actual = "//{}:[{}]",'.format(us_name, extra_name),
                    ")",
                    "",
                ])
    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # Pin directories: proxies pointing to @workspace//_lock targets
    for base_pin_name, group in sorted(grouped_pins.items()):
        base_target_dict = _effective_base_target_dict(group)

        package = {}
        if base_target_dict:
            first_target = list(base_target_dict.values())[0]
            package = packages.get(first_target, {})
        us_name = underscore_name(base_pin_name)

        has_aggregated_variant = bool(base_target_dict) and any([
            t in base_packages_with_extras
            for t in base_target_dict.values()
        ])

        extras_dict = group["extras"]

        # Determine which branches of this pin are platform-specific or have sdists.
        maybe_available_keys = []
        sdist_target_dict = {}
        if base_target_dict:
            for constraint, pkg_key in base_target_dict.items():
                pkg = packages.get(pkg_key, {})
                if is_platform_specific(pkg):
                    maybe_available_keys.append(pkg_key)
                if pkg.get("sdist_file"):
                    sdist_target_dict[constraint] = pkg_key

        extras_maybe_keys = {}
        for extra_name, extra_target_dict in extras_dict.items():
            extra_avail = []
            for _constraint, pkg_key in extra_target_dict.items():
                if _is_key_platform_specific(packages, pkg_key):
                    extra_avail.append(pkg_key)
            if extra_avail:
                extras_maybe_keys[extra_name] = extra_avail

        result = _pin_build(
            us_name,
            base_target_dict,
            package,
            workspace_repo,
            has_aggregated_variant = has_aggregated_variant,
            extras_dict = extras_dict,
            no_variant_fallbacks = no_variant_fallbacks,
            target_platform = target_platform,
            transition_bzl = "//:_transition.bzl" if has_flags else None,
            maybe_available_keys = maybe_available_keys,
            extras_maybe_keys = extras_maybe_keys,
            testonly = (base_pin_name in testonly_pins_set),
            sdist_target_dict = sdist_target_dict,
            aggregated_keys = base_packages_with_extras,
            packages = packages,
        )
        rctx.file(
            "{}/BUILD.bazel".format(us_name),
            result.build,
        )
        if result.actual_build:
            rctx.file(
                "__actual/{}/BUILD.bazel".format(us_name),
                result.actual_build,
            )

    # _backend/ directory
    if rctx.attr.backend_configs:
        rctx.file(
            "_backend/BUILD.bazel",
            "exports_files(glob(['*.bzl']))\n",
        )

        for macro_name in rctx.attr.backend_configs.keys():
            lines = [
                '"""Backend macro alias for this thin repo."""',
                "",
                'load("@{}//_backend:{}.bzl", _{} = "{}")'.format(workspace_repo, macro_name, macro_name, macro_name),
                "",
                "{} = _{}".format(macro_name, macro_name),
                "",
            ]

            rctx.file("_backend/{}.bzl".format(macro_name), "\n".join(lines))

    # _packages.bzl: metadata about all packages in this thin repo.
    rctx.file("_packages.bzl", _packages_bzl(grouped_pins, packages))

    # _cargo/ aliases: if any packages have cargo lock overrides for a registered
    # cargo-lock backend hook, create aliases from unversioned names to versioned
    # targets in the package repo.
    cargo_hook_backends = [b for b in _CARGO_HOOK_BACKENDS if b in PACKAGE_REPO_HOOKS]
    if rctx.attr.override_configs and cargo_hook_backends:
        override_configs = json.decode(rctx.attr.override_configs)
        cargo_build = _cargo_build(
            grouped_pins,
            packages,
            override_configs,
            workspace_repo,
            no_variant_fallbacks = no_variant_fallbacks,
            cargo_backends = cargo_hook_backends,
        )
        if cargo_build:
            rctx.file("_cargo/BUILD.bazel", cargo_build)

    # _variants/ BUILD: this repo's variant flags (see _variants_build). Last,
    # since the selects above collect the `_unselected_all_*` groups it emits.
    variants_build = _variants_build(
        variant_info,
        workspace_repo,
        getattr(rctx, "original_name", "") or "<repo>",
        unselected_groups = no_variant_fallbacks.groups,
        pins_by_set = pins_by_set,
        excluded = excluded,
        expose_variant_flags = rctx.attr.expose_variant_flags,
    )
    if variants_build:
        rctx.file("_variants/BUILD.bazel", variants_build)

    # Generate pin_versions.json: a manifest of what each //dep:pkg pin resolves to.
    # Simple pins: name -> version string. Variant pins: name -> {variant -> version}.
    rctx.file("pin_versions.json", json.encode(_pin_versions(grouped_pins)))

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

def _effective_base_target_dict(group):
    """Return group['base_target'], or derive base lock keys from extras for extras-only pins."""
    base_target_dict = group["base_target"]
    if base_target_dict or not group["extras"]:
        return base_target_dict
    derived = {}
    for _extra_name, extra_target_dict in sorted(group["extras"].items()):
        for constraint, extra_target in extra_target_dict.items():
            parts = parse_package_key(extra_target)
            derived.setdefault(constraint, "{}@{}".format(parts.name, parts.version))
    return derived

def _modules_mapping_deps(pins, packages, workspace_repo, variant_info = None, no_variant_fallbacks = None, pins_by_set = None, excluded = None, resolution_marker_exprs = None):
    """Compute conditional `deps` lines and helper config_setting_groups for `pycross_modules_mapping`.

    Resolution-marker forks and pinned/defaulted repo variants are selected on
    their active condition so inactive forks are never analyzed or fetched.
    Unpinned conflict variants without a repo default remain unioned when no
    variant flag is set (via `_unselected_<set>`), while narrowing to the active
    variant when a flag is set.
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

            if _is_key_platform_specific(packages, pin_target):
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
                group_name = _unselected_all_name(unpinned_sets)
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

def _pin_versions(grouped_pins):
    """Build pin_versions.json mapping from grouped pins (including extras-only pins)."""
    pin_versions = {}
    for base_pin_name in sorted(grouped_pins.keys()):
        base_target_dict = _effective_base_target_dict(grouped_pins[base_pin_name])
        if not base_target_dict:
            continue

        if len(base_target_dict) == 1 and "" in base_target_dict:
            parts = parse_package_key(base_target_dict[""])
            pin_versions[base_pin_name] = parts.version
        else:
            variant_versions = {}
            for variant_name, pkg_key in sorted(base_target_dict.items()):
                parts = parse_package_key(pkg_key)
                variant_versions[variant_name] = parts.version
            pin_versions[base_pin_name] = variant_versions
    return pin_versions

def _packages_bzl(grouped_pins, packages):
    """Render `_packages.bzl` metadata for all packages in a thin repo."""
    packages_lines = [
        '"""Generated package metadata. Do not edit."""',
        "",
        "PACKAGES = {",
    ]
    for base_pin_name in sorted(grouped_pins.keys()):
        group = grouped_pins[base_pin_name]
        us_name = underscore_name(base_pin_name)

        base_target_dict = _effective_base_target_dict(group)
        has_sdist = False
        if base_target_dict:
            for pkg_key in base_target_dict.values():
                if packages.get(pkg_key, {}).get("sdist_file"):
                    has_sdist = True
                    break

        packages_lines.extend([
            '    "{}": struct('.format(us_name),
            "        has_sdist = {},".format(has_sdist),
            "    ),",
        ])
    packages_lines.extend([
        "}",
        "",
    ])
    return "\n".join(packages_lines)

_CARGO_HOOK_BACKENDS = ("maturin_build", "setuptools_rust_build")

def _cargo_build(grouped_pins, packages, override_configs, workspace_repo, no_variant_fallbacks = None, cargo_backends = None):
    """Render `_cargo/BUILD.bazel` aliases for packages with cargo lock overrides, or None."""
    effective_backends = _CARGO_HOOK_BACKENDS if cargo_backends == None else cargo_backends
    if not effective_backends:
        return None

    cargo_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    has_cargo_targets = False
    for base_pin_name in sorted(grouped_pins.keys()):
        us_name = underscore_name(base_pin_name)
        target_dict = _effective_base_target_dict(grouped_pins[base_pin_name])
        if not target_dict:
            continue

        cargo_target_dict = {}
        for constraint, pkg_key in target_dict.items():
            parts = parse_package_key(pkg_key)
            base_key = "{}@{}".format(parts.name, parts.version)
            if not packages.get(base_key, {}).get("sdist_file"):
                continue
            merged = merge_backend_overrides(override_configs, parts.name, parts.version)
            if not any([b in merged for b in effective_backends]):
                continue
            cargo_target_dict[constraint] = base_key
        if not cargo_target_dict:
            continue

        actual_cargo = _target_select(
            cargo_target_dict,
            "@{}//_cargo:".format(workspace_repo),
            "",
            workspace_repo,
            no_variant_fallbacks = no_variant_fallbacks,
            all_target_dict = target_dict,
            fallback_target = _NO_MATCH_ERROR_TARGET,
        )

        cargo_lines.extend([
            "alias(",
            '    name = "{}",'.format(us_name),
            "    actual = {},".format(actual_cargo),
            ")",
            "",
        ])
        has_cargo_targets = True

    if not has_cargo_targets:
        return None
    return "\n".join(cargo_lines)

thin_package_repo = repository_rule(
    implementation = _thin_package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "generate_root_aliases": attr.bool(
            doc = "Whether to generate aliases like @uv//:numpy.",
            default = False,
        ),
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
                  "Its transition sets the workspace repo's `_pin_<set>` to it.",
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

# Visible for testing
pin_build_for_testing = _pin_build
flag_values_for_testing = _flag_values
is_platform_specific_for_testing = is_platform_specific
requirements_bzl_for_testing = _requirements_bzl
packages_bzl_for_testing = _packages_bzl
pin_versions_for_testing = _pin_versions
modules_mapping_deps_for_testing = _modules_mapping_deps
cargo_build_for_testing = _cargo_build
