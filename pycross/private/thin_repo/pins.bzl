"""Per-pin BUILD.bazel, `__actual/`, and root alias generation for thin package repos."""

load("//pycross/private:build_text.bzl", "alias", "config_setting_group", "deps_plus_selects")
load(
    "//pycross/private:lock_contract.bzl",
    "lock_constraint_label",
    "lock_dist_info_prefix",
    "lock_label_prefix",
    "sdist_label_prefix",
    "wheel_label_prefix",
)
load("//pycross/private:util.bzl", "base_package_key", "is_platform_specific", "sanitize_name", "underscore_name")
load(":availability.bzl", "emit_maybe_alias", "markers_condition")
load(":common.bzl", "NO_MATCH_ERROR_TARGET", "effective_base_target_dict", "is_key_platform_specific", "safe_name")
load(":selects.bzl", "proxy_actual", "target_select")

def _cond_group(out_lines, out_used, group_cache, kind, labels):
    """Emit (or reuse) a `selects.config_setting_group` for `(kind, labels)`."""
    key = (kind, tuple(labels))
    if key not in group_cache:
        name = "_extra_%s_%x" % (kind, hash("|".join(labels)) & 0xffffffff)
        out_lines.extend(config_setting_group(name, kind, labels))
        out_used["selects"] = True
        group_cache[key] = ":" + name
    return group_cache[key]

def _extra_availability_condition(out_lines, out_used, avail_cache, extra_key, packages, workspace_repo):
    """Return a config_setting label for `extra_key`'s own `availability_markers`, or None."""
    if not packages:
        return None
    if extra_key in avail_cache:
        return avail_cache[extra_key]
    markers = packages.get(extra_key, {}).get("availability_markers")
    cond = markers_condition(
        out_lines,
        "_extra_avail_" + sanitize_name(extra_key),
        markers,
        workspace_repo,
        used = out_used,
    )
    avail_cache[extra_key] = cond
    return cond

def _build_extra_deps(extra_constraints, lock_ref, packages, workspace_repo, out_lines, out_used, avail_cache, group_cache):
    """Build `(static_deps, conditional_by_cond)` from `{extra_key: {constraint: True}}`."""
    static_deps = []
    conditional_by_cond = {}
    for extra_key in sorted(extra_constraints.keys()):
        constraints = extra_constraints[extra_key]
        avail_cond = _extra_availability_condition(
            out_lines,
            out_used,
            avail_cache,
            extra_key,
            packages,
            workspace_repo,
        )
        dep_label = lock_ref + extra_key
        if "" in constraints:
            if avail_cond:
                conditional_by_cond.setdefault(avail_cond, []).append(dep_label)
            else:
                static_deps.append(dep_label)
            continue

        sorted_cs = sorted(constraints.keys())
        if len(sorted_cs) == 1:
            c_cond = lock_constraint_label(workspace_repo, sorted_cs[0])
        else:
            c_cond = _cond_group(
                out_lines,
                out_used,
                group_cache,
                "match_any",
                [lock_constraint_label(workspace_repo, c) for c in sorted_cs],
            )
        final_cond = _cond_group(
            out_lines,
            out_used,
            group_cache,
            "match_all",
            [c_cond, avail_cond],
        ) if avail_cond else c_cond
        conditional_by_cond.setdefault(final_cond, []).append(dep_label)
    return static_deps, conditional_by_cond

def _emit_library_proxy_with_deps(out_lines, out_used, name, actual_expr, static_deps, conditional_by_cond, is_testonly = False):
    """Emit a `pycross_library_proxy` with static and conditional extra deps."""
    out_lines.extend([
        "pycross_library_proxy(",
        "    name = {},".format(json.encode(name)),
        "    actual = {},".format(actual_expr),
    ])
    out_lines.extend(deps_plus_selects(
        "deps",
        static_deps,
        conditional_by_cond,
        indent = 1,
        trailing_comma = True,
    ))
    if is_testonly:
        out_lines.append("    testonly = True,")
    out_lines.extend([")", ""])
    out_used["library_proxy"] = True

def pin_repo_context(
        workspace_repo,
        no_variant_fallbacks = None,
        target_platform = None,
        transition_bzl = None,
        packages = None):
    """Build the repo-wide context struct shared by every `pin_build` call in a thin repo.

    Args:
        workspace_repo: Name of the workspace (backing) repo.
        no_variant_fallbacks: Result of `variant_fallbacks`, or None.
        target_platform: Optional platform label for transitioning proxies.
        transition_bzl: Optional repo-local transition `.bzl` label.
        packages: Lock packages dict, or None.

    Returns:
        Context struct passed to `pin_build`.
    """
    return struct(
        workspace_repo = workspace_repo,
        no_variant_fallbacks = no_variant_fallbacks,
        target_platform = target_platform,
        transition_bzl = transition_bzl,
        packages = packages,
    )

def pin_spec(
        target_name,
        pin_target_dict,
        extras_dict = None,
        maybe_available_keys = None,
        extras_maybe_keys = None,
        testonly = False,
        sdist_target_dict = None):
    """Build the per-pin specification struct passed to `pin_build`.

    Args:
        target_name: Underscore-normalized pin directory and default alias name.
        pin_target_dict: Constraint -> package key mapping for the base package.
        extras_dict: Optional dict of extra name -> constraint mapping.
        maybe_available_keys: Package keys needing `:maybe` availability gating.
        extras_maybe_keys: Dict of extra name -> list of platform-specific keys.
        testonly: Whether library proxy targets are marked `testonly = True`.
        sdist_target_dict: Constraint -> package key mapping for branches with sdists.

    Returns:
        Pin specification struct passed to `pin_build`.
    """
    return struct(
        target_name = target_name,
        pin_target_dict = pin_target_dict,
        extras_dict = extras_dict or {},
        maybe_available_keys = maybe_available_keys,
        extras_maybe_keys = extras_maybe_keys or {},
        testonly = testonly,
        sdist_target_dict = sdist_target_dict,
    )

def pin_build(pin, repo_ctx):
    """Generates the BUILD file for a pin directory, pointing to the workspace.

    Args:
        pin: Per-pin specification from `pin_spec`.
        repo_ctx: Repo-wide context from `pin_repo_context`.

    Returns:
        `struct(build, actual_build, unselected_groups)` with BUILD file contents for
        `<pkg>/` and `__actual/<pkg>/`, plus any `_unselected_all_*` groups referenced.
    """
    target_name = pin.target_name
    pin_target_dict = pin.pin_target_dict
    extras_dict = pin.extras_dict
    maybe_available_keys = pin.maybe_available_keys
    extras_maybe_keys = pin.extras_maybe_keys
    testonly = pin.testonly
    sdist_target_dict = pin.sdist_target_dict

    workspace_repo = repo_ctx.workspace_repo
    no_variant_fallbacks = repo_ctx.no_variant_fallbacks
    target_platform = repo_ctx.target_platform
    transition_bzl = repo_ctx.transition_bzl
    packages = repo_ctx.packages

    lock_ref = lock_label_prefix(workspace_repo)
    wheel_ref = wheel_label_prefix(workspace_repo)
    sdist_ref = sdist_label_prefix(workspace_repo)

    actual_lines = []
    used_main = {}
    used_actual = {}
    unselected_groups = {}
    actual_pkg_ref = "//__actual/{}".format(target_name)

    if transition_bzl:
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    elif target_platform:
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    else:
        lib_rule = "pycross_thin_library_proxy"
        file_rule = "pycross_file_proxy"

    lines = []

    has_transition = bool(transition_bzl or target_platform)

    def _emit_proxy(rule_name, name, actual_expr, is_testonly = False):
        if rule_name == "pycross_thin_library_proxy":
            used_main["thin_library_proxy"] = True
        elif rule_name == "pycross_file_proxy":
            used_main["file_proxy"] = True
        lines.extend([
            rule_name + "(",
            "    name = {},".format(json.encode(name)),
            "    actual = {},".format(actual_expr),
        ])
        if is_testonly:
            lines.append("    testonly = True,")
        if target_platform:
            lines.append("    platform = {},".format(json.encode(target_platform)))
        lines.extend([")", ""])

    def _emit_maybe_target(maybe_name, actual_maybe_name, pkg_target, actual_target, target_dict, available_keys, helper_prefix):
        if not target_dict or (not available_keys and "" in target_dict):
            return
        out_lines = actual_lines if has_transition else lines
        alias_name = actual_maybe_name if has_transition else maybe_name
        alias_target = actual_target if has_transition else pkg_target
        used = used_actual if has_transition else used_main
        unselected_groups.update(emit_maybe_alias(
            out_lines,
            alias_name,
            alias_target,
            target_dict,
            available_keys,
            workspace_repo,
            no_variant_fallbacks = no_variant_fallbacks,
            helper_prefix = helper_prefix,
            packages = packages,
            used = used,
        ))
        if has_transition:
            _emit_proxy(lib_rule, maybe_name, json.encode("{}:{}".format(actual_pkg_ref, actual_maybe_name)), is_testonly = testonly)

    actual_pkg_label = None
    if pin_target_dict:
        pkg_target_name = safe_name(target_name, "pkg")
        lines.extend(alias(target_name, ":" + pkg_target_name))

        unique_bases = sorted({b: True for b in pin_target_dict.values()}.keys())
        has_pkg_extras = False
        pkg_emitted = False
        if extras_dict and len(unique_bases) == 1:
            only_base = unique_bases[0]
            out_lines = actual_lines if has_transition else lines
            out_used = used_actual if has_transition else used_main
            avail_cache = {}
            group_cache = {}
            extra_constraints = {}
            for _extra_name, extra_target_dict in sorted(extras_dict.items()):
                if "" in extra_target_dict and base_package_key(extra_target_dict[""]) == only_base:
                    extra_constraints.setdefault(extra_target_dict[""], {})[""] = True
                    continue
                for constraint, extra_key in sorted(extra_target_dict.items()):
                    if base_package_key(extra_key) == only_base:
                        extra_constraints.setdefault(extra_key, {})[constraint] = True

            static_deps, conditional_by_cond = _build_extra_deps(
                extra_constraints,
                lock_ref,
                packages,
                workspace_repo,
                out_lines,
                out_used,
                avail_cache,
                group_cache,
            )
            if static_deps or conditional_by_cond:
                has_pkg_extras = True
                pkg_emitted = True
                base_sel = target_select(
                    pin_target_dict,
                    lock_ref,
                    workspace_repo,
                    no_variant_fallbacks = no_variant_fallbacks,
                )
                unselected_groups.update(base_sel.unselected_groups)
                _emit_library_proxy_with_deps(
                    out_lines,
                    out_used,
                    "pkg" if has_transition else pkg_target_name,
                    base_sel.expr,
                    static_deps,
                    conditional_by_cond,
                    is_testonly = testonly,
                )
                if has_transition:
                    actual_pkg_label = "{}:pkg".format(actual_pkg_ref)
                    _emit_proxy(lib_rule, pkg_target_name, json.encode(actual_pkg_label), is_testonly = testonly)
        elif extras_dict:
            out_lines = actual_lines if has_transition else lines
            out_used = used_actual if has_transition else used_main
            avail_cache = {}
            group_cache = {}
            branch_target_labels = {}
            emitted_branch_proxies = {}
            used_helper_names = {}
            sorted_constraints = sorted([c for c in pin_target_dict.keys() if c]) + ([""] if "" in pin_target_dict else [])
            for pin_constraint in sorted_constraints:
                base_key = pin_target_dict[pin_constraint]
                branch_extra_constraints = {}
                for _extra_name, extra_target_dict in sorted(extras_dict.items()):
                    if pin_constraint in extra_target_dict:
                        ek = extra_target_dict[pin_constraint]
                        if base_package_key(ek) == base_key:
                            branch_extra_constraints.setdefault(ek, {})[""] = True
                    elif "" in extra_target_dict:
                        ek = extra_target_dict[""]
                        if base_package_key(ek) == base_key:
                            branch_extra_constraints.setdefault(ek, {})[""] = True
                    for ec, ek in sorted(extra_target_dict.items()):
                        if ec and ec not in pin_target_dict and base_package_key(ek) == base_key:
                            branch_extra_constraints.setdefault(ek, {})[ec] = True

                static_deps, conditional_by_cond = _build_extra_deps(
                    branch_extra_constraints,
                    lock_ref,
                    packages,
                    workspace_repo,
                    out_lines,
                    out_used,
                    avail_cache,
                    group_cache,
                )
                if not static_deps and not conditional_by_cond:
                    branch_target_labels[pin_constraint] = lock_ref + base_key
                    continue

                has_pkg_extras = True
                sig_key = json.encode([
                    base_key,
                    static_deps,
                    [[c, sorted(ds)] for c, ds in sorted(conditional_by_cond.items())],
                ])
                if sig_key not in emitted_branch_proxies:
                    base_helper = "_pkg_" + sanitize_name(base_key)
                    helper_name = base_helper if base_helper not in used_helper_names else "%s_%x" % (base_helper, hash(sig_key) & 0xffffffff)
                    used_helper_names[helper_name] = True
                    emitted_branch_proxies[sig_key] = helper_name
                    _emit_library_proxy_with_deps(
                        out_lines,
                        out_used,
                        helper_name,
                        json.encode(lock_ref + base_key),
                        static_deps,
                        conditional_by_cond,
                        is_testonly = testonly,
                    )
                branch_target_labels[pin_constraint] = ":" + emitted_branch_proxies[sig_key]

            if has_pkg_extras:
                pkg_emitted = True
                pkg_sel = target_select(
                    branch_target_labels,
                    "",
                    workspace_repo,
                    no_variant_fallbacks = no_variant_fallbacks,
                )
                unselected_groups.update(pkg_sel.unselected_groups)
                if has_transition:
                    actual_lines.extend(alias("pkg", pkg_sel.expr, actual_is_expr = True))
                    actual_pkg_label = "{}:pkg".format(actual_pkg_ref)
                    _emit_proxy(lib_rule, pkg_target_name, json.encode(actual_pkg_label), is_testonly = testonly)
                else:
                    _emit_proxy(lib_rule, pkg_target_name, pkg_sel.expr, is_testonly = testonly)
                    actual_pkg_label = pkg_sel.label

        if not pkg_emitted:
            actual_pkg = proxy_actual(actual_lines, pin_target_dict, lock_ref, workspace_repo, "pkg", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
            unselected_groups.update(actual_pkg.unselected_groups)
            _emit_proxy(lib_rule, pkg_target_name, actual_pkg.expr, is_testonly = testonly)
            actual_pkg_label = actual_pkg.label

        actual_wheel = proxy_actual(actual_lines, pin_target_dict, wheel_ref, workspace_repo, "wheel", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        unselected_groups.update(actual_wheel.unselected_groups)
        _emit_proxy(file_rule, safe_name(target_name, "wheel"), actual_wheel.expr)

        actual_dist_info = proxy_actual(actual_lines, pin_target_dict, lock_dist_info_prefix(workspace_repo), workspace_repo, "dist_info", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        unselected_groups.update(actual_dist_info.unselected_groups)
        _emit_proxy(file_rule, safe_name(target_name, "dist_info"), actual_dist_info.expr)
        lines.extend(alias(safe_name(target_name, "data"), ":" + pkg_target_name, trailing_blank = False))

        if extras_dict:
            if has_pkg_extras:
                actual_base = proxy_actual(actual_lines, pin_target_dict, lock_ref, workspace_repo, "base", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
                unselected_groups.update(actual_base.unselected_groups)
                _emit_proxy(lib_rule, "[]", actual_base.expr, is_testonly = testonly)
            else:
                lines.extend(alias("[]", ":" + pkg_target_name))

        if sdist_target_dict:
            actual_sdist = proxy_actual(
                actual_lines,
                sdist_target_dict,
                sdist_ref,
                workspace_repo,
                "sdist",
                actual_pkg_ref,
                has_transition = has_transition,
                no_variant_fallbacks = no_variant_fallbacks,
                all_target_dict = pin_target_dict,
                fallback_target = NO_MATCH_ERROR_TARGET,
            )
            unselected_groups.update(actual_sdist.unselected_groups)
            _emit_proxy(file_rule, safe_name(target_name, "sdist"), actual_sdist.expr)

    for extra_name, extra_target_dict in sorted(extras_dict.items()):
        actual_extra = proxy_actual(actual_lines, extra_target_dict, lock_ref, workspace_repo, "extra_{}".format(extra_name), actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        unselected_groups.update(actual_extra.unselected_groups)
        _emit_proxy(lib_rule, "[{}]".format(extra_name), actual_extra.expr, is_testonly = testonly)
        _emit_maybe_target(
            maybe_name = "[{}]_maybe".format(extra_name),
            actual_maybe_name = "extra_{}_maybe".format(extra_name),
            pkg_target = ":[{}]".format(extra_name),
            actual_target = actual_extra.label,
            target_dict = extra_target_dict,
            available_keys = extras_maybe_keys.get(extra_name),
            helper_prefix = "_maybe_extra_{}".format(extra_name),
        )

    if pin_target_dict:
        _emit_maybe_target(
            maybe_name = safe_name(target_name, "maybe"),
            actual_maybe_name = "maybe",
            pkg_target = ":{}".format(safe_name(target_name, "pkg")),
            actual_target = actual_pkg_label,
            target_dict = pin_target_dict,
            available_keys = maybe_available_keys,
            helper_prefix = "_maybe",
        )

    header_lines = []
    if transition_bzl:
        header_lines.append('load({}, "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")'.format(json.encode(transition_bzl)))
    elif target_platform:
        header_lines.append('load("@rules_pycross//pycross/private:proxy.bzl", "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")')
    else:
        proxy_symbols = []
        if used_main.get("file_proxy"):
            proxy_symbols.append("pycross_file_proxy")
        if used_main.get("library_proxy"):
            proxy_symbols.append("pycross_library_proxy")
        if used_main.get("thin_library_proxy"):
            proxy_symbols.append("pycross_thin_library_proxy")
        if proxy_symbols:
            header_lines.append('load("@rules_pycross//pycross/private:proxy.bzl", {})'.format(
                ", ".join([json.encode(sym) for sym in proxy_symbols]),
            ))
    if used_main.get("selects"):
        header_lines.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    header_lines.extend([
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])

    actual_build = None
    if actual_lines:
        actual_header = []
        if used_actual.get("selects"):
            actual_header.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
        if used_actual.get("library_proxy"):
            actual_header.append('load("@rules_pycross//pycross/private:proxy.bzl", "pycross_library_proxy")')
        if actual_header:
            actual_header.append("")
        actual_header.extend([
            'package(default_visibility = ["//{}:__pkg__"])'.format(target_name),
            "",
        ])
        actual_build = "\n".join(actual_header + actual_lines) + "\n"

    return struct(
        build = "\n".join(header_lines + lines) + "\n",
        actual_build = actual_build,
        unselected_groups = unselected_groups,
    )

def append_root_aliases(root_build_lines, grouped_pins):
    """Append top-level `//:pkg`, `//:pkg[]`, and `//:pkg[extra]` aliases to root BUILD lines.

    Args:
        root_build_lines: Output list of root `BUILD.bazel` lines.
        grouped_pins: Dict of base pin name -> `{"base_target", "extras"}`.
    """
    for base_pin_name in sorted(grouped_pins.keys()):
        group = grouped_pins[base_pin_name]
        us_name = underscore_name(base_pin_name)
        base_target = group["base_target"]

        if base_target:
            root_build_lines.extend(alias(base_pin_name, "//{}:pkg".format(us_name), trailing_blank = False))
            if group["extras"]:
                root_build_lines.extend(alias("{}[]".format(base_pin_name), "//{}:[]".format(us_name)))
        elif group["extras"]:
            # If no base target was pinned, but extras were, point the base name at the extras union.
            root_build_lines.extend(alias(base_pin_name, "//{}:pkg".format(us_name)))

        for extra_name, _extra_target in sorted(group["extras"].items()):
            root_build_lines.extend(alias("{}[{}]".format(base_pin_name, extra_name), "//{}:[{}]".format(us_name, extra_name)))

def emit_pin_directories(rctx, grouped_pins, packages, workspace_repo, no_variant_fallbacks, target_platform, has_flags, testonly_pins_set, resolution_marker_exprs = None):
    """Generate `<pkg>/BUILD.bazel` (and `__actual/<pkg>/BUILD.bazel`) for each pinned package.

    Args:
        rctx: Repository context.
        grouped_pins: Dict of base pin name -> `{"base_target", "extras"}`.
        packages: Lock packages dict.
        workspace_repo: Name of the workspace (backing) repo.
        no_variant_fallbacks: Result of variant_fallbacks.
        target_platform: Optional platform label for transitioning proxies.
        has_flags: Whether `_transition.bzl` was generated for this repo.
        testonly_pins_set: Set/dict of pin names marked testonly.
        resolution_marker_exprs: Optional lock `resolution_marker_exprs` dict.

    Returns:
        Dict of `{group_name: set_suffixes}` for all `_unselected_all_*` groups referenced.
    """
    repo_ctx = pin_repo_context(
        workspace_repo = workspace_repo,
        no_variant_fallbacks = no_variant_fallbacks,
        target_platform = target_platform,
        transition_bzl = "//:_transition.bzl" if has_flags else None,
        packages = packages,
    )
    variant_constraints = no_variant_fallbacks.sets if no_variant_fallbacks else None
    unselected_groups = {}
    for base_pin_name, group in sorted(grouped_pins.items()):
        base_target_dict = effective_base_target_dict(
            group,
            resolution_marker_exprs = resolution_marker_exprs,
            variant_constraints = variant_constraints,
        )
        us_name = underscore_name(base_pin_name)
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
                if is_key_platform_specific(packages, pkg_key):
                    extra_avail.append(pkg_key)
            if extra_avail:
                extras_maybe_keys[extra_name] = extra_avail

        result = pin_build(
            pin_spec(
                target_name = us_name,
                pin_target_dict = base_target_dict,
                extras_dict = extras_dict,
                maybe_available_keys = maybe_available_keys,
                extras_maybe_keys = extras_maybe_keys,
                testonly = (base_pin_name in testonly_pins_set),
                sdist_target_dict = sdist_target_dict,
            ),
            repo_ctx,
        )
        unselected_groups.update(result.unselected_groups)
        rctx.file("{}/BUILD.bazel".format(us_name), result.build)
        if result.actual_build:
            rctx.file("__actual/{}/BUILD.bazel".format(us_name), result.actual_build)
    return unselected_groups
