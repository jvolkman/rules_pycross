"""Per-package target rendering and extras aggregation for `_lock/lock.bzl`."""

load("//pycross/private:build_text.bzl", "alias", "config_setting_group", "deps_plus_selects")
load(
    "//pycross/private:lock_contract.bzl",
    "dist_info_target_name",
    "is_extras_proxy",
    "marker_match_target_name",
    "raw_target_name",
    "sdist_deps_target_name",
    "sdist_repo_name",
    "sdist_target_name",
    "wheel_target_name",
)
load("//pycross/private:util.bzl", "base_package_key", "base_packages_with_extras", "format_package_key", "has_build_fallback", "marker_evaluator_name", "parse_package_key", "sanitize_name")
load(":common.bzl", "ind", "is_in_same_cycle", "render_str_list_attr", "wheel_target")
load(":wheels.bzl", "render_marker_wheel_chooser")

def render_extras_aggregates(lines, packages):
    """Renders `[_all_]` `pycross_library_proxy` targets aggregating a base package and its extras.

    Args:
        lines: Output lines list.
        packages: Lock packages dict.
    """
    extras_by_base = base_packages_with_extras(packages)

    for base_pkg_key, extra_keys in sorted(
        extras_by_base.items(),
        key = lambda item: (parse_package_key(item[0]).name, parse_package_key(item[0]).version, parse_package_key(item[0]).tag),
    ):
        parts = parse_package_key(base_pkg_key)
        lines.extend([
            ind("pycross_library_proxy("),
            ind("name = {},".format(json.encode(format_package_key(parts.name, parts.version, extra = "_all_", tag = parts.tag))), 2),
            ind("actual = {},".format(json.encode(":" + base_pkg_key)), 2),
            ind("deps = [", 2),
        ])
        for extra_key in sorted(extra_keys):
            lines.append(ind("{},".format(json.encode(":" + extra_key)), 3))
        lines.extend([
            ind("],", 2),
            ind(")"),
            "",
        ])

def render_marker_package_deps(lines, pkg_key, pkg_key_san, pkg, packages, loads = None):
    """Render deps using marker-based `select()` instead of environment-based selects.

    Args:
        lines: Output lines list.
        pkg_key: Package key in the lock.
        pkg_key_san: Sanitized Starlark identifier form of `pkg_key`.
        pkg: Package dict.
        packages: All lock packages dict.
        loads: Optional dict tracking emitted helper loads (`"selects"`).
    """
    marker_deps = pkg.get("marker_dependencies", [])
    extra = parse_package_key(pkg_key).extra

    unconditional = {}
    conditional = []
    for md in marker_deps:
        dep_key = md["key"]
        if is_in_same_cycle(dep_key, pkg, packages):
            continue
        if md.get("marker"):
            conditional.append(md)
        else:
            unconditional[dep_key] = True

    # Collect per-dep unique evaluators, dropping any dep already unconditional.
    dep_evals = {}  # dep_key -> {eval_name: True}
    for md in conditional:
        dep_key = md["key"]
        if dep_key in unconditional:
            continue
        eval_name = marker_evaluator_name(md["marker"], extra)
        dep_evals.setdefault(dep_key, {})[eval_name] = True

    # Group single-evaluator deps by evaluator; deps reachable under multiple
    # distinct markers get a shared match_any config_setting_group so overlapping
    # markers never emit duplicate labels in `deps`.
    by_condition = {}  # condition_label -> {dep_label: True}
    multi_groups = {}  # tuple(sorted_evals) -> group_name
    for dep_key in sorted(dep_evals.keys()):
        evals = sorted(dep_evals[dep_key].keys())
        if len(evals) == 1:
            cond = ":" + marker_match_target_name(evals[0])
        else:
            evals_key = tuple(evals)
            if evals_key not in multi_groups:
                group_name = "_dep_any_%s_%x" % (
                    pkg_key_san,
                    hash("|".join(evals)) & 0xffffffff,
                )
                multi_groups[evals_key] = group_name
                lines.extend(config_setting_group(
                    group_name,
                    "match_any",
                    [":" + marker_match_target_name(ev) for ev in evals],
                    indent = 1,
                ))
                if loads != None:
                    loads["selects"] = True
            cond = ":{}".format(multi_groups[evals_key])
        by_condition.setdefault(cond, {})[":" + dep_key] = True

    lines.extend(deps_plus_selects(
        "_{}_deps".format(pkg_key_san),
        [":" + k for k in sorted(unconditional.keys())],
        by_condition,
        indent = 1,
        inline_values = True,
        trailing_comma = False,
    ))
    lines.append("")

def render_marker_package(lines, pkg_key, pkg, packages, repo_map, rctx_name, reset_plan = None, loads = None):
    """Renders all targets for a single package using marker-based deps and wheel selection.

    Args:
        lines: Output lines list.
        pkg_key: Package key in the lock.
        pkg: Package dict.
        packages: All lock packages dict.
        repo_map: File key -> repository label dict.
        rctx_name: Canonical repository name of the `package_repo`.
        reset_plan: Optional dict mapping `pkg_key -> struct(ok, gate)`.
        loads: Optional dict tracking emitted helper loads (`"selects"`, `"wheel_matched"`).
    """
    pkg_key_san = sanitize_name(pkg_key)
    parts = parse_package_key(pkg_key)
    package_name = parts.name
    package_version = parts.version

    has_marker_deps = bool(pkg.get("marker_dependencies"))
    has_wheel_candidates = bool(pkg.get("wheel_candidates"))

    sdist_file = pkg.get("sdist_file")
    sdist_label = wheel_target(sdist_file, repo_map) if sdist_file else None

    # Runtime deps
    if has_marker_deps:
        render_marker_package_deps(lines, pkg_key, pkg_key_san, pkg, packages, loads = loads)

    if is_extras_proxy(pkg_key, pkg):
        base_pkg_key = base_package_key(pkg_key)
        proxy_name = raw_target_name(pkg_key) if pkg.get("cycle_group") else pkg_key
        base_actual = raw_target_name(base_pkg_key) if is_in_same_cycle(base_pkg_key, pkg, packages) else base_pkg_key

        lines.extend([
            ind("pycross_library_proxy("),
            ind("name = {},".format(json.encode(proxy_name)), 2),
            ind("actual = {},".format(json.encode(":" + base_actual)), 2),
            ind("deps = _{}_deps,".format(pkg_key_san) if has_marker_deps else "deps = [],", 2),
            ind(")"),
            "",
        ])
        return

    # Sdist alias
    if sdist_label:
        lines.extend(alias(sdist_target_name(pkg_key), sdist_label, indent = 1, use_native = True))

    # Compute the sdist build target (if available) for fallback when no wheel matches.
    sdist_target = None
    has_sdist_repo = False
    if pkg.get("build_target"):
        sdist_target = pkg["build_target"]
    elif sdist_file and has_build_fallback(pkg):
        sdist_file_key = sdist_file.get("key")
        if sdist_file_key:
            pkg_sdist_repo = sdist_repo_name(rctx_name, pkg_key)
            sdist_target = "@@{}//:wheel".format(pkg_sdist_repo)
            has_sdist_repo = True

    # Wheel chooser
    if has_wheel_candidates:
        render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_target = sdist_target, loads = loads)
    else:
        # No wheel candidates, alias directly to sdist_target or no_match_error
        target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
        lines.extend(alias(wheel_target_name(pkg_key), target, indent = 1, use_native = True))

    # Library
    lib_name = pkg_key
    if pkg.get("cycle_group"):
        lib_name = raw_target_name(pkg_key)

    reset = reset_plan.get(pkg_key) if reset_plan else None
    if reset and reset.ok:
        lines.extend([
            ind("pycross_resettable_wheel_library("),
            ind("name = {},".format(json.encode(lib_name)), 2),
            ind("reset_gate = {},".format(json.encode(reset.gate) if reset.gate else "None"), 2),
        ])
    else:
        lines.extend([
            ind("pycross_wheel_library("),
            ind("name = {},".format(json.encode(lib_name)), 2),
        ])
    lines.extend([
        ind("package_name = {},".format(json.encode(package_name)), 2),
        ind("package_version = {},".format(json.encode(package_version)), 2),
        ind("wheel = {},".format(json.encode(":" + wheel_target_name(pkg_key))), 2),
    ])

    for attr_name in ("site_paths", "bin_paths", "data_paths", "include_paths"):
        render_str_list_attr(lines, attr_name, pkg.get(attr_name))

    if has_marker_deps:
        lines.append(ind("deps = _{}_deps,".format(pkg_key_san), 2))

    for field, attr_name in (
        ("install_exclude_globs", "install_exclude_globs"),
        ("post_install_patches", "post_install_patches"),
        ("wheel_library_tags", "tags"),
    ):
        render_str_list_attr(lines, attr_name, pkg.get(field))

    if pkg.get("precompile"):
        lines.append(ind("precompile = {},".format(json.encode(pkg["precompile"])), 2))

    lines.extend([
        ind(")"),
        "",
    ])

    # Note: if this package is in a cycle group, the public target is created
    # by lock_render/cycles.bzl (rendered separately).
    # The pycross_wheel_library above is named _raw_<pkg_key> in that case.

    # dist_info (point directly at _raw_<pkg> for cycle members so console script
    # exec analysis doesn't pull in the entire cycle SCC and reachability evaluators)
    lines.extend([
        ind("pycross_dist_info("),
        ind("name = {},".format(json.encode(dist_info_target_name(pkg_key))), 2),
        ind("pkg = {},".format(json.encode(":" + lib_name)), 2),
        ind(")"),
        "",
    ])

    # Sdist build runtime deps proxy: evaluated under wheel_build.deps's exec
    # platform transition so PEP 508 markers match the host platform, same-cycle
    # deps are excluded, and edges merged across workspace members are included.
    if has_sdist_repo and has_marker_deps:
        lines.extend([
            ind("pycross_library_proxy("),
            ind("name = {},".format(json.encode(sdist_deps_target_name(pkg_key))), 2),
            ind("deps = _{}_deps,".format(pkg_key_san), 2),
            ind(")"),
            "",
        ])
