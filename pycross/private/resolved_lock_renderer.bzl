"""Pure Starlark implementation of the resolved_lock_renderer.

This module generates the BUILD.bazel content for the `_lock` repository.
It uses PEP 508 marker expressions for platform-conditional dependencies
and a wheel chooser for platform-specific wheel selection.

Naming conventions for generated targets:
  - `_raw_<pkg_key>`: The underlying `pycross_wheel_library` or `pycross_wheel_build` target.
  - `<pkg_key>`: For cycle members, this is a `pycross_library_proxy` (created by
    `pycross_cycle_member_marker_deps`) that wraps the raw target and adds conditional deps.
    For extras-only packages (e.g., `name[extra]@version`), this is a `pycross_library_proxy`
    with `actual` pointing to the base package and extra-specific deps in `deps`.
  - `<pkg_name>[_all_]@<version>`: A synthetic `pycross_library_proxy` that aggregates the
    base package and all of its parsed extras into a single target.
"""

load(":util.bzl", "parse_package_key")

def _ind(text, tabs = 1):
    if not text:
        return ""
    return ("    " * tabs) + text

def _sanitize_name(name):
    return name.lower().replace("-", "_").replace("@", "_").replace("+", "_").replace(".", "_").replace("[", "_").replace("]", "_")

def _is_in_same_cycle(dep_key, pkg, packages):
    cycle_group = pkg.get("cycle_group")
    if not cycle_group:
        return False
    dep_pkg = packages.get(dep_key)
    if not dep_pkg:
        return False
    return dep_pkg.get("cycle_group") == cycle_group

def _render_package_override_label_validation_test_rule(lines):
    lines.extend([
        "def _package_override_label_validation_test_impl(ctx):",
        _ind("_ = ctx.attr.targets"),
        _ind('executable = ctx.actions.declare_file(ctx.label.name + ".sh")'),
        _ind("ctx.actions.write("),
        _ind("output = executable,", 2),
        _ind('content = "#!/bin/sh\\nexit 0\\n",', 2),
        _ind("is_executable = True,", 2),
        _ind(")"),
        _ind("return [DefaultInfo(executable = executable)]"),
        "",
        "_package_override_label_validation_test = rule(",
        _ind("implementation = _package_override_label_validation_test_impl,"),
        _ind("attrs = {"),
        _ind('"targets": attr.label_list(', 2),
        _ind("allow_files = True,", 3),
        _ind('doc = "Targets referenced by pycross package overrides.",', 3),
        _ind("),", 2),
        _ind("},"),
        _ind("test = True,"),
        ")",
        "",
    ])

def _collect_package_override_labels(packages):
    labels = {}
    for _pkg_key, pkg in packages.items():
        build_target = pkg.get("build_target")
        if build_target:
            labels[build_target] = True

        sdist_file = pkg.get("sdist_file")
        if sdist_file and sdist_file.get("label"):
            labels[sdist_file["label"]] = True

        for candidate in pkg.get("wheel_candidates", []):
            file_ref = candidate.get("file_reference", {})
            if file_ref.get("label"):
                labels[file_ref["label"]] = True

    return sorted(labels.keys())

def _render_package_override_label_validation_test(lines, package_override_labels):
    lines.extend([
        _ind("_package_override_label_validation_test("),
        _ind('name = "validate_package_override_labels",', 2),
        _ind("targets = [", 2),
    ])
    for label in package_override_labels:
        lines.append(_ind('"{}",'.format(label), 3))
    lines.extend([
        _ind("],", 2),
        _ind('visibility = ["//visibility:public"],', 2),
        _ind(")"),
        "",
    ])

def _wheel_target(file_ref, sdist_file, pkg_key, pkg, repo_map, sdist_map, rctx_name):
    if file_ref.get("label"):
        return file_ref["label"]
    key = file_ref.get("key")
    if sdist_file and key == sdist_file.get("key"):
        if pkg.get("build_target"):
            return pkg["build_target"]
        if sdist_map and key in sdist_map:
            return sdist_map[key]
        repo_name = "{}_sdist_{}".format(rctx_name, _sanitize_name(pkg_key))
        return "@@{}//:wheel".format(repo_name)

    return repo_map.get(key)

def _render_extras_aggregates(lines, packages):
    """Renders [_all_] pycross_library_proxy targets that aggregate a base package and all its extras."""
    base_packages_with_extras = {}
    for pkg_key in packages.keys():
        parts = parse_package_key(pkg_key)
        if parts.extra:
            base_key = (parts.name, parts.version)
            if base_key not in base_packages_with_extras:
                base_packages_with_extras[base_key] = []
            base_packages_with_extras[base_key].append(pkg_key)

    for (base_name, version), extra_keys in sorted(base_packages_with_extras.items()):
        base_pkg_key = "{}@{}".format(base_name, version)
        lines.extend([
            _ind("pycross_library_proxy("),
            _ind('name = "{}[_all_]@{}",'.format(base_name, version), 2),
            _ind('actual = ":{}",'.format(base_pkg_key), 2),
            _ind("deps = [", 2),
        ])
        for extra_key in sorted(extra_keys):
            lines.append(_ind('":{}\",'.format(extra_key), 3))
        lines.extend([
            _ind("],", 2),
            _ind(")"),
            "",
        ])

def _collect_unique_markers(packages):
    """Collect all unique (marker, extra) pairs across packages.

    Returns a dict mapping (marker_string, extra_value) to True.
    The extra is derived from the package key (e.g. 'foo[test]@1.0' -> 'test').
    """
    markers = {}
    for pkg_key, pkg in packages.items():
        extra = parse_package_key(pkg_key).extra
        for md in pkg.get("marker_dependencies", []):
            marker = md.get("marker")
            if marker:
                # Optimization: if "extra" is not in the marker string, it doesn't reference the extra variable.
                # We can share a single evaluator by setting extra to "".
                effective_extra = extra if "extra" in marker else ""
                markers[(marker, effective_extra)] = True
    return markers.keys()

def _marker_evaluator_name(marker_str, extra = ""):
    """Generate a deterministic target name for a marker evaluator.

    Args:
        marker_str: The PEP 508 marker expression.
        extra: The PEP 508 extra value (e.g. 'test'), or '' for no extra.
    """

    # Starlark's hash() is deterministic within a build invocation.
    # We sanitize the marker string for readability and add the hash for uniqueness.
    key = marker_str if not extra else "{}|extra={}".format(marker_str, extra)
    san = _sanitize_name(key.replace(" ", "").replace("\"", "").replace("'", ""))

    # Truncate to keep target names reasonable
    if len(san) > 40:
        san = san[:40]
    return "_marker_eval_{}_{}".format(san, hash(key))

def _render_marker_evaluators(lines, unique_markers):
    """Render deduped pycross_pep508_evaluator and config_setting targets.

    Args:
        lines: Output lines list.
        unique_markers: Iterable of (marker_str, extra) tuples.
    """
    for marker_str, extra in sorted(unique_markers):
        eval_name = _marker_evaluator_name(marker_str, extra)

        # Evaluator rule — returns FeatureFlagInfo("true"/"false")
        lines.extend([
            _ind("pycross_pep508_evaluator("),
            _ind('name = "{}",'.format(eval_name), 2),
            _ind('expr = "{}",'.format(marker_str.replace('"', '\\"')), 2),
        ])
        if extra:
            lines.append(_ind('extra = "{}",'.format(extra), 2))
        lines.extend([
            _ind(")"),
            "",
        ])

        # Config setting that matches when the evaluator says "true"
        lines.extend([
            _ind("native.config_setting("),
            _ind('name = "{}_match",'.format(eval_name), 2),
            _ind("flag_values = {", 2),
            _ind('":{eval}": "true",'.format(eval = eval_name), 3),
            _ind("},", 2),
            _ind(")"),
            "",
        ])

def _render_resolution_marker_evaluators(lines, resolution_marker_exprs):
    """Render pycross_pep508_evaluator + config_setting for resolution-marker forks.

    Entries in ``resolution_marker_exprs`` are either:
    - A string (simple fork): generates an evaluator + config_setting.
    - A dict with ``variant`` and ``marker`` keys (compound fork): generates a
      config_setting_group that matches both the variant and the marker.

    Args:
        lines: Output lines list.
        resolution_marker_exprs: Dict mapping constraint_name to either a
            PEP 508 marker expression string or a compound dict.
    """
    for constraint_name, entry in sorted(resolution_marker_exprs.items()):
        if type(entry) == "dict":
            # Compound constraint: combine variant + marker config_settings.
            # Both is_<variant> and is_<marker> must already exist.
            lines.extend([
                _ind("selects.config_setting_group("),
                _ind('name = "is_{}",'.format(constraint_name), 2),
                _ind("match_all = [", 2),
                _ind('"is_{}",'.format(entry["variant"]), 3),
                _ind('"is_{}",'.format(entry["marker"]), 3),
                _ind("],", 2),
                _ind(")"),
                "",
            ])
        else:
            # Simple fork: evaluator + config_setting.
            eval_name = "_res_eval_{}".format(constraint_name)
            lines.extend([
                _ind("pycross_pep508_evaluator("),
                _ind('name = "{}",'.format(eval_name), 2),
                _ind('expr = "{}",'.format(entry.replace('"', '\\"')), 2),
                _ind(")"),
                "",
            ])

            # Config setting matching when the evaluator says "true".
            lines.extend([
                _ind("native.config_setting("),
                _ind('name = "is_{}",'.format(constraint_name), 2),
                _ind("flag_values = {", 2),
                _ind('":{eval}": "true",'.format(eval = eval_name), 3),
                _ind("},", 2),
                _ind(")"),
                "",
            ])

def _build_cycle_edges_dict(scc, packages):
    """Builds the in-cycle edge map for marker mode.

    Returns a dict with format:
      {pkg: [{"dep": dep_key, "marker": "..."}, ...], ...}
    """
    scc_set = {k: True for k in scc}
    edges = {}
    for pkg_key in sorted(scc):
        pkg = packages.get(pkg_key, {})
        edge_list = []
        for md in pkg.get("marker_dependencies", []):
            dep_key = md["key"]
            if dep_key in scc_set:
                entry = {"dep": dep_key}
                if md.get("marker"):
                    entry["marker"] = md["marker"]
                edge_list.append(entry)
        edges[pkg_key] = edge_list
    return edges

def _render_edges_dict(edges, base_indent = 1):
    """Renders an edges dict as pretty-printed Starlark dict literal lines.

    Args:
        edges: Dict of {node: [{dep, marker?}, ...], ...}.
        base_indent: Number of indent levels for the outer braces.

    Returns:
        A list of indented lines forming a valid Starlark dict literal.
    """
    lines = [_ind("{", base_indent)]
    for pkg_key in sorted(edges.keys()):
        edge_list = edges[pkg_key]
        if not edge_list:
            lines.append(_ind('"{}": [],'.format(pkg_key), base_indent + 1))
        else:
            lines.append(_ind('"{}": ['.format(pkg_key), base_indent + 1))
            for entry in edge_list:
                parts = ['"dep": {}'.format(repr(entry["dep"]))]
                if entry.get("marker"):
                    parts.append('"marker": {}'.format(repr(entry["marker"])))
                lines.append(_ind("{{{}}},".format(", ".join(parts)), base_indent + 2))
            lines.append(_ind("],", base_indent + 1))
    lines.append(_ind("}", base_indent))
    return lines

def _render_marker_cycle_member_deps(lines, cycle_groups, packages):
    """Renders pycross_cycle_member_marker_deps macro calls for each cycle member.

    Each macro call internally creates N reachability evaluators + config_settings
    and wraps them in a pycross_library_proxy with select() per dep.

    Only cycle group members that appear in ``packages`` are rendered; groups
    whose members are entirely outside the resolved set are silently skipped.
    """
    for group_name, scc in sorted(cycle_groups.items()):
        # Only render members that are part of the resolved package set.
        resolved_members = [m for m in scc if m in packages]
        if not resolved_members:
            continue

        edges = _build_cycle_edges_dict(scc, packages)

        sanitized_group_name = _sanitize_name(group_name).upper()
        edges_var_name = "_{}_EDGES".format(sanitized_group_name)

        edges_lines = _render_edges_dict(edges, base_indent = 1)

        # Attach the variable assignment to the first line of the dict literal.
        edges_lines[0] = _ind("{} = ".format(edges_var_name)) + edges_lines[0].lstrip()
        lines.extend(edges_lines)
        lines.append("")

        for pkg_key in sorted(resolved_members):
            extra = parse_package_key(pkg_key).extra
            lines.append(_ind("pycross_cycle_member_marker_deps("))
            lines.append(_ind('name = "{}",'.format(pkg_key), 2))
            lines.append(_ind('raw_name = "_raw_{}",'.format(pkg_key), 2))
            lines.append(_ind('member = "{}",'.format(pkg_key), 2))
            lines.append(_ind("edges = {},".format(edges_var_name), 2))
            if extra:
                lines.append(_ind('extra = "{}",'.format(extra), 2))
            lines.append(_ind(")"))
            lines.append("")

def _render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_map, rctx_name, sdist_target = None):
    """Render a wheel chooser target and per-wheel config_settings + alias."""
    candidates = pkg.get("wheel_candidates", [])
    if not candidates:
        return

    filenames = [c["filename"] for c in candidates]
    chooser_name = "_wheel_chooser_{}".format(pkg_key)

    lines.extend([
        _ind("pycross_wheel_chooser("),
        _ind('name = "{}",'.format(chooser_name), 2),
        _ind("candidates = {},".format(filenames), 2),
        _ind(")"),
        "",
    ])

    # Config setting per wheel candidate (skip candidates with no target)
    sdist_file = pkg.get("sdist_file")
    resolved_candidates = []
    for candidate in candidates:
        file_ref = candidate.get("file_reference", {})
        target = _wheel_target(file_ref, sdist_file, pkg_key, pkg, repo_map, sdist_map, rctx_name)
        if target:
            resolved_candidates.append((candidate, target))

    for candidate, _target in resolved_candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, _sanitize_name(filename))
        lines.extend([
            _ind("native.config_setting("),
            _ind('name = "{}",'.format(cs_name), 2),
            _ind("flag_values = {", 2),
            _ind('":{chooser}": "{filename}",'.format(
                chooser = chooser_name,
                filename = filename,
            ), 3),
            _ind("},", 2),
            _ind(")"),
            "",
        ])

    # Wheel alias selecting over the config_settings
    lines.extend([
        _ind("native.alias("),
        _ind('name = "_wheel_{}",'.format(pkg_key), 2),
        _ind("actual = select({", 2),
    ])
    for candidate, target in resolved_candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, _sanitize_name(filename))
        lines.append(_ind('":{}": "{}",'.format(cs_name, target), 3))
    no_match_target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
    lines.append(_ind('"//conditions:default": "{}",'.format(no_match_target), 3))
    lines.extend([
        _ind("}),", 2),
        _ind(")"),
        "",
    ])

    # Availability config_setting_group: ORs all per-wheel config_settings.
    # Only emitted for packages that would fall to no_match_error (no sdist),
    # so that all_requirements can use select() to exclude them on incompatible
    # platforms.
    if not sdist_target and resolved_candidates:
        cs_names = []
        for candidate, _target in resolved_candidates:
            filename = candidate["filename"]
            cs_names.append(":_wheel_cs_{}_{}".format(pkg_key, _sanitize_name(filename)))
        lines.extend([
            _ind("selects.config_setting_group("),
            _ind('name = "_available_{}",'.format(pkg_key), 2),
            _ind("match_any = [", 2),
        ])
        for cs in cs_names:
            lines.append(_ind('"{}",'.format(cs), 3))
        lines.extend([
            _ind("],", 2),
            _ind(")"),
            "",
        ])

def _render_marker_package_deps(lines, pkg_key, pkg_key_san, pkg, packages):
    """Render deps using marker-based select() instead of environment-based."""
    marker_deps = pkg.get("marker_dependencies", [])
    if not marker_deps:
        lines.append(_ind("_{}_deps = []".format(pkg_key_san)))
        lines.append("")
        return

    extra = parse_package_key(pkg_key).extra

    unconditional = []
    conditional = []
    for md in marker_deps:
        dep_key = md["key"]
        if _is_in_same_cycle(dep_key, pkg, packages):
            continue
        if md.get("marker"):
            conditional.append(md)
        else:
            unconditional.append(md)

    lines.append(_ind("_{}_deps = [".format(pkg_key_san)))
    for md in sorted(unconditional, key = lambda m: m["key"]):
        lines.append(_ind('":{}\",'.format(md["key"]), 2))
    lines.append(_ind("]"))

    if conditional:
        # Each conditional dep gets its own select()
        for md in sorted(conditional, key = lambda m: m["key"]):
            effective_extra = extra if "extra" in md["marker"] else ""
            eval_name = _marker_evaluator_name(md["marker"], effective_extra)
            lines[-1] = lines[-1] + " + select({"
            lines.append(_ind('":{}_match": [":{}"],'.format(eval_name, md["key"]), 2))
            lines.append(_ind('"//conditions:default": [],', 2))
            lines.append(_ind("})", 1))

    lines.append("")

def _render_marker_package(lines, pkg_key, pkg, packages, repo_map, sdist_map, rctx_name):
    """Renders all targets for a single package using marker-based deps and wheel selection."""
    pkg_key_san = _sanitize_name(pkg_key)
    parts = parse_package_key(pkg_key)
    package_name = parts.name
    package_version = parts.version
    extra = parts.extra

    has_marker_deps = bool(pkg.get("marker_dependencies"))
    has_wheel_candidates = bool(pkg.get("wheel_candidates"))

    sdist_file = pkg.get("sdist_file")
    sdist_label = None
    if sdist_file:
        if sdist_file.get("label"):
            sdist_label = sdist_file["label"]
        elif sdist_file.get("key"):
            sdist_label = repo_map.get(sdist_file["key"])

    has_runtime_deps = has_marker_deps

    # Runtime deps
    if has_marker_deps:
        _render_marker_package_deps(lines, pkg_key, pkg_key_san, pkg, packages)

    if not has_wheel_candidates and extra:
        # Extras packages wrap the base package plus their own deps.
        base_pkg_key = "{}@{}".format(package_name, package_version)
        lines.extend([
            _ind("pycross_library_proxy("),
            _ind('name = "{}",'.format(pkg_key), 2),
            _ind('actual = ":{}",'.format(base_pkg_key), 2),
            _ind("deps = _{}_deps,".format(pkg_key_san) if has_runtime_deps else "deps = [],", 2),
            _ind(")"),
            "",
        ])
        return

    # Sdist alias
    if sdist_label:
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_sdist_{}",'.format(pkg_key), 2),
            _ind('actual = "{}",'.format(sdist_label), 2),
            _ind(")"),
            "",
        ])

    # Compute the sdist build target (if available) for fallback when no wheel matches.
    sdist_target = None
    if pkg.get("build_target"):
        sdist_target = pkg["build_target"]
    elif sdist_file:
        sdist_file_key = sdist_file.get("key")
        if sdist_file_key:
            sdist_repo_name = "{}_sdist_{}".format(rctx_name, _sanitize_name(pkg_key))
            sdist_target = "@@{}//:wheel".format(sdist_repo_name)

    # Wheel chooser
    if has_wheel_candidates:
        _render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_map, rctx_name, sdist_target = sdist_target)
    else:
        # No wheel candidates, alias directly to sdist_target or no_match_error
        target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_wheel_{}",'.format(pkg_key), 2),
            _ind('actual = "{}",'.format(target), 2),
            _ind(")"),
            "",
        ])

    # Library
    lib_name = pkg_key
    if pkg.get("cycle_group"):
        lib_name = "_raw_{}".format(pkg_key)

    has_any_deps = has_runtime_deps

    lines.extend([
        _ind("pycross_wheel_library("),
        _ind('name = "{}",'.format(lib_name), 2),
        _ind('package_name = "{}",'.format(package_name), 2),
        _ind('package_version = "{}",'.format(package_version), 2),
        _ind('wheel = ":_wheel_{}",'.format(pkg_key), 2),
    ])

    if pkg.get("site_paths"):
        lines.append(_ind("site_paths = [", 2))
        for tlp in pkg["site_paths"]:
            lines.append(_ind('"{}",'.format(tlp), 3))
        lines.append(_ind("],", 2))

    if pkg.get("bin_paths"):
        lines.append(_ind("bin_paths = [", 2))
        for bp in pkg["bin_paths"]:
            lines.append(_ind('"{}",'.format(bp), 3))
        lines.append(_ind("],", 2))

    if pkg.get("data_paths"):
        lines.append(_ind("data_paths = [", 2))
        for dp in pkg["data_paths"]:
            lines.append(_ind('"{}",'.format(dp), 3))
        lines.append(_ind("],", 2))

    if pkg.get("include_paths"):
        lines.append(_ind("include_paths = [", 2))
        for ip in pkg["include_paths"]:
            lines.append(_ind('"{}",'.format(ip), 3))
        lines.append(_ind("],", 2))

    if has_any_deps:
        lines.append(_ind("deps = _{}_deps,".format(pkg_key_san), 2))

    if pkg.get("install_exclude_globs"):
        lines.append(_ind("install_exclude_globs = [", 2))
        for glob in pkg["install_exclude_globs"]:
            lines.append(_ind('"{}",'.format(glob), 3))
        lines.append(_ind("],", 2))

    if pkg.get("post_install_patches"):
        lines.append(_ind("post_install_patches = [", 2))
        for patch in pkg["post_install_patches"]:
            lines.append(_ind('"{}",'.format(patch), 3))
        lines.append(_ind("],", 2))

    if pkg.get("wheel_library_tags"):
        lines.append(_ind("tags = [", 2))
        for tag in pkg["wheel_library_tags"]:
            lines.append(_ind('"{}",'.format(tag), 3))
        lines.append(_ind("],", 2))

    lines.extend([
        _ind(")"),
        "",
    ])

    # Note: if this package is in a cycle group, the public target is created
    # by the pycross_cycle_member_marker_deps macro call (rendered separately).
    # The pycross_wheel_library above is named _raw_<pkg_key> in that case.

    # dist_info
    lines.extend([
        _ind("pycross_dist_info("),
        _ind('name = "_dist_info_{}",'.format(pkg_key), 2),
        _ind('pkg = ":{lib}",'.format(lib = pkg_key), 2),
        _ind(")"),
        "",
    ])

# ---- Main render function ---------------------------------------------------

def render_lock_bzl(lock, repo_map, sdist_map = None, rctx_name = ""):
    """Renders a lock.bzl file from a resolved lock structure.

    Args:
        lock: The parsed lock.json dict.
        repo_map: A dict mapping file keys to repo labels.
        sdist_map: A dict mapping sdist package keys to their wheel target labels.
        rctx_name: The name of the package repository.

    Returns:
        A string containing the rendered lock.bzl file.
    """
    packages = lock.get("packages", {})
    cycle_groups = lock.get("cycle_groups", {})

    pycross_loads = ["pycross_dist_info", "pycross_library_proxy", "pycross_pep508_evaluator", "pycross_wheel_chooser", "pycross_wheel_library"]
    if cycle_groups:
        pycross_loads.insert(0, "pycross_cycle_member_marker_deps")

    # Check if selects.bzl is needed (for config_setting_group).
    # True for: packages with wheel candidates but no sdist fallback,
    # or compound resolution-marker constraints.
    needs_selects = False
    for _pk, pkg_data in packages.items():
        if pkg_data.get("wheel_candidates") and not pkg_data.get("sdist_file") and not pkg_data.get("build_target"):
            needs_selects = True
            break
    if not needs_selects:
        for _cn, entry in lock.get("resolution_marker_exprs", {}).items():
            if type(entry) == "dict":
                needs_selects = True
                break

    lines = [
        "# This file is generated by rules_pycross.",
        "# It is not intended for manual editing.",
        '"""Pycross-generated dependency targets."""',
        "",
        'load("@rules_pycross//pycross:defs.bzl", {})'.format(
            ", ".join(['"{}"'.format(s) for s in sorted(pycross_loads)]),
        ),
        'load("@rules_pycross//pycross/private:pep508_marker_values.bzl",',
        '    "FREETHREADED_VALUES",',
        '    "LIBC_VALUES",',
        ")",
    ]

    if needs_selects:
        lines.append('load("@bazel_skylib//lib:selects.bzl", "selects")')

    lines.extend([
        "",
    ])
    _render_package_override_label_validation_test_rule(lines)
    lines.extend([
        "# buildifier: disable=unnamed-macro",
        "def targets():",
        _ind('"""Generated package targets."""'),
        "",
    ])

    package_override_labels = _collect_package_override_labels(packages)

    # 1. Marker evaluators for dependency markers (deduped)
    unique_markers = _collect_unique_markers(packages)
    _render_marker_evaluators(lines, unique_markers)

    # 1b. Resolution-marker evaluators for pin forks
    resolution_marker_exprs = lock.get("resolution_marker_exprs", {})
    _render_resolution_marker_evaluators(lines, resolution_marker_exprs)

    # 2. Per-member cycle deps (marker-aware)
    _render_marker_cycle_member_deps(lines, cycle_groups, packages)

    # 3. Packages
    for pkg_key, pkg in sorted(packages.items()):
        _render_marker_package(lines, pkg_key, pkg, packages, repo_map, sdist_map, rctx_name)

    # 4. Extras aggregates ([_all_] targets)
    _render_extras_aggregates(lines, packages)

    # 5. Package override label validation
    _render_package_override_label_validation_test(lines, package_override_labels)

    return "\n".join(lines) + "\n"
