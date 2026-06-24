"""Pure Starlark implementation of the resolved_lock_renderer.

This module generates the BUILD.bazel content for the `_lock` repository.
It implements the following naming conventions for generated targets:
  - `_raw_<pkg_key>`: The underlying `pycross_wheel_library` or `pycross_wheel_build` target.
  - `<pkg_key>`: A `py_library` that wraps the raw target. If the package is part of a cycle,
    this target depends on both the raw target and a per-member cycle deps target.
  - `_cycle_deps_for_<pkg_key>`: A `pycross_cycle_member_deps` target that computes the exact
    transitive in-cycle dependencies for a specific member at analysis time.
  - `<pkg_name>[_all_]@<version>`: A synthetic `py_library` that aggregates the base package and
    all of its parsed extras into a single target. Repos using `squash_extras` point their
    aliases to this `[_all_]` target to squash the graph at the alias layer.
"""

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

def _render_environment_config_settings(lines, environments):
    """Renders native.alias or native.config_setting targets for each environment."""
    for env_name, env_ref in sorted(environments.items()):
        if env_ref.get("config_setting_label"):
            lines.extend([
                _ind("native.alias("),
                _ind('name = "{}",'.format(env_name), 2),
                _ind('actual = "{}",'.format(env_ref["config_setting_label"]), 2),
                _ind(")"),
                "",
            ])
        else:
            config_setting = env_ref.get("config_setting", {})
            lines.extend([
                _ind("native.config_setting("),
                _ind('name = "{}",'.format(env_name), 2),
            ])
            if config_setting.get("constraint_values"):
                lines.append(_ind("constraint_values = [", 2))
                for cv in config_setting["constraint_values"]:
                    lines.append(_ind('"{}",'.format(cv), 3))
                lines.append(_ind("],", 2))
            if config_setting.get("flag_values"):
                lines.append(_ind("flag_values = {", 2))
                for f, v in sorted(config_setting["flag_values"].items()):
                    lines.append(_ind('"{}": "{}",'.format(f, v), 3))
                lines.append(_ind("},", 2))
            lines.extend([
                _ind(")"),
                "",
            ])

def _build_cycle_edges_json(scc, packages):
    """Builds the JSON-encoded in-cycle edge map for a cycle group.

    Returns a JSON string with format:
      {"pkg": {"common": ["dep", ...], "env_name": ["dep", ...]}, ...}
    """
    scc_set = {k: True for k in scc}
    edges = {}
    for pkg_key in sorted(scc):
        pkg = packages.get(pkg_key, {})
        edge_map = {}
        common = []
        for dep in pkg.get("common_dependencies", []):
            if dep in scc_set:
                common.append(dep)
        if common:
            edge_map["common"] = common
        for env_name, env_deps in sorted(pkg.get("environment_dependencies", {}).items()):
            env_cycle_deps = []
            for dep in env_deps:
                if dep in scc_set:
                    env_cycle_deps.append(dep)
            if env_cycle_deps:
                edge_map[env_name] = env_cycle_deps
        edges[pkg_key] = edge_map
    return json.encode(edges)

def _render_cycle_member_deps(lines, cycle_groups, packages, environments):
    """Renders per-member pycross_cycle_member_deps targets for each cycle SCC.

    Each cycle member gets its own target that computes its exact transitive
    in-cycle dependencies at analysis time based on the resolved environment.
    Members with platform-specific wheels are gated with select() in the
    raw_members attr to prevent analysis failures.
    """
    for _group_name, scc in sorted(cycle_groups.items()):
        edges_json = _build_cycle_edges_json(scc, packages)

        # Partition members by wheel availability for the raw_members attr.
        common_members = []
        env_members = {}  # env_name → [pkg_key, ...]
        for pkg_key in sorted(scc):
            pkg = packages.get(pkg_key, {})
            pkg_envs = pkg.get("environment_files", {}).keys()
            if not pkg_envs or all([env in pkg_envs for env in environments]):
                common_members.append(pkg_key)
            else:
                for env in pkg_envs:
                    if env in environments:
                        env_members.setdefault(env, []).append(pkg_key)

        for pkg_key in sorted(scc):
            lines.append(_ind("pycross_cycle_member_deps("))
            lines.append(_ind('name = "_cycle_deps_for_{}",'.format(pkg_key), 2))
            lines.append(_ind('member = "{}",'.format(pkg_key), 2))

            # raw_members: label_keyed_string_dict with select for platform-specific wheels
            if not env_members:
                lines.append(_ind("raw_members = {", 2))
                for m in common_members:
                    lines.append(_ind('":_raw_{}": "{}",'.format(m, m), 3))
                lines.append(_ind("},", 2))
            else:
                lines.append(_ind("raw_members = {", 2))
                for m in common_members:
                    lines.append(_ind('":_raw_{}": "{}",'.format(m, m), 3))
                lines.append(_ind("} | select({", 2))
                for env_name in sorted(environments.keys()):
                    deps = env_members.get(env_name, [])
                    if deps:
                        lines.append(_ind('":{env}": {{'.format(env = env_name), 3))
                        for m in sorted(deps):
                            lines.append(_ind('":_raw_{}": "{}",'.format(m, m), 4))
                        lines.append(_ind("},", 3))
                lines.append(_ind('"//conditions:default": {},', 3))
                lines.append(_ind("}),", 2))

            lines.append(_ind("edges = '{}',".format(edges_json), 2))

            # env: resolved environment name via select
            lines.append(_ind("env = select({", 2))
            for env_name in sorted(environments.keys()):
                lines.append(_ind('":{env}": "{env}",'.format(env = env_name), 3))
            lines.append(_ind("}),", 2))

            lines.append(_ind(")"))
            lines.append("")

def _render_package_deps(lines, pkg_key_san, pkg, packages):
    """Renders the _<pkg>_deps list and optional select() for a package's runtime deps."""
    lines.append(_ind("_{}_deps = [".format(pkg_key_san)))
    for dep_key in sorted(pkg.get("common_dependencies", [])):
        if _is_in_same_cycle(dep_key, pkg, packages):
            continue
        lines.append(_ind('":{}",'.format(dep_key), 2))
    lines.append(_ind("]"))

    if pkg.get("environment_dependencies"):
        lines[-1] = lines[-1] + " + select({"
        for env_name, deps in sorted(pkg.get("environment_dependencies").items()):
            lines.append(_ind('":{env}": ['.format(env = env_name), 2))
            for dep_key in sorted(deps):
                if _is_in_same_cycle(dep_key, pkg, packages):
                    continue
                lines.append(_ind('":{}",'.format(dep_key), 3))
            lines.append(_ind("],", 2))
        lines.append(_ind('"//conditions:default": [],', 2))
        lines.append(_ind("})", 1))
    lines.append("")

def _render_package(lines, pkg_key, pkg, packages, repo_map, sdist_map, rctx_name):
    """Renders all targets for a single package: deps, wheel alias, library, wrapper, dist_info."""
    pkg_key_san = _sanitize_name(pkg_key)
    package_name = pkg_key.split("@", 1)[0]
    package_version = pkg_key.split("@", 1)[1]

    has_runtime_deps = bool(pkg.get("common_dependencies") or pkg.get("environment_dependencies"))

    sdist_file = pkg.get("sdist_file")
    sdist_label = None
    if sdist_file:
        if sdist_file.get("label"):
            sdist_label = sdist_file["label"]
        elif sdist_file.get("key"):
            sdist_label = repo_map.get(sdist_file["key"])

    # Runtime deps
    if has_runtime_deps:
        _render_package_deps(lines, pkg_key_san, pkg, packages)

    if not pkg.get("environment_files") and "[" in pkg_key:
        # Extra packages just wrap their dependencies
        lines.extend([
            _ind("py_library("),
            _ind('name = "{}",'.format(pkg_key), 2),
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

    # Wheel alias (with select for multi-environment)
    lines.extend([
        _ind("native.alias("),
        _ind('name = "_wheel_{}",'.format(pkg_key), 2),
    ])
    lines.append(_ind("actual = select({", 2))
    for env_name, env_ref in sorted(pkg.get("environment_files", {}).items()):
        lines.append(_ind('":{env}": "{target}",'.format(
            env = env_name,
            target = _wheel_target(env_ref, sdist_file, pkg_key, pkg, repo_map, sdist_map, rctx_name),
        ), 3))
    lines.append(_ind('"//conditions:default": "@rules_pycross//pycross/private:no_match_error",', 3))
    lines.append(_ind("}),", 2))
    lines.extend([
        _ind(")"),
        "",
    ])

    # Library
    lib_name = pkg_key
    if pkg.get("cycle_group"):
        lib_name = "_raw_{}".format(pkg_key)

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

    if has_runtime_deps:
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

    lines.extend([
        _ind(")"),
        "",
    ])

    # Cycle member wrapper
    if pkg.get("cycle_group"):
        lines.append(_ind("py_library("))
        lines.append(_ind('name = "{}",'.format(pkg_key), 2))
        lines.append(_ind('deps = [":_raw_{}", ":_cycle_deps_for_{}"],'.format(pkg_key, pkg_key), 2))
        lines.append(_ind(")"))
        lines.append("")

    # dist_info
    lines.extend([
        _ind("pycross_dist_info("),
        _ind('name = "_dist_info_{}",'.format(pkg_key), 2),
        _ind('pkg = ":{lib}",'.format(lib = pkg_key), 2),
        _ind(")"),
        "",
    ])

def _render_extras_aggregates(lines, packages):
    """Renders [_all_] py_library targets that aggregate a base package and all its extras."""
    base_packages_with_extras = {}
    for pkg_key in packages.keys():
        if "[" in pkg_key:
            base_name, extra_and_version = pkg_key.split("[", 1)
            _, version = extra_and_version.split("]@", 1)
            base_pkg_key = "{}@{}".format(base_name, version)
            if base_pkg_key not in base_packages_with_extras:
                base_packages_with_extras[base_pkg_key] = []
            base_packages_with_extras[base_pkg_key].append(pkg_key)

    for base_pkg_key, extra_keys in sorted(base_packages_with_extras.items()):
        base_name, version = base_pkg_key.split("@", 1)
        lines.extend([
            _ind("py_library("),
            _ind('name = "{}[_all_]@{}",'.format(base_name, version), 2),
            _ind("deps = [", 2),
            _ind('":{}\",'.format(base_pkg_key), 3),
        ])
        for extra_key in sorted(extra_keys):
            lines.append(_ind('":{}\",'.format(extra_key), 3))
        lines.extend([
            _ind("],", 2),
            _ind(")"),
            "",
        ])

# ---- Marker-based rendering (Phase 3) --------------------------------------

def _has_marker_data(packages):
    """Returns True if any package has marker_dependencies or wheel_candidates."""
    for pkg in packages.values():
        if pkg.get("marker_dependencies") or pkg.get("wheel_candidates"):
            return True
    return False

def _collect_unique_markers(packages):
    """Collect all unique marker strings across packages, returning a deduped set."""
    markers = {}
    for pkg in packages.values():
        for md in pkg.get("marker_dependencies", []):
            marker = md.get("marker")
            if marker:
                markers[marker] = md.get("marker_ast")
    return markers

def _marker_evaluator_name(marker_str):
    """Generate a deterministic target name for a marker evaluator."""

    # Starlark's hash() is deterministic within a build invocation.
    # We sanitize the marker string for readability and add the hash for uniqueness.
    san = _sanitize_name(marker_str.replace(" ", "").replace("\"", "").replace("'", ""))

    # Truncate to keep target names reasonable
    if len(san) > 40:
        san = san[:40]
    return "_marker_eval_{}_{}".format(san, hash(marker_str))

def _render_marker_evaluators(lines, unique_markers):
    """Render deduped pycross_pep508_evaluator and config_setting targets."""
    for marker_str, marker_ast in sorted(unique_markers.items()):
        eval_name = _marker_evaluator_name(marker_str)
        ast_json = json.encode(marker_ast) if marker_ast else "{}"

        # Evaluator rule — returns FeatureFlagInfo("true"/"false")
        lines.extend([
            _ind("pycross_pep508_evaluator("),
            _ind('name = "{}",'.format(eval_name), 2),
            _ind("expr = '{}',".format(ast_json), 2),
            _ind("sys_platform = select(SYS_PLATFORM_VALUES),", 2),
            _ind("os_name = select(OS_NAME_VALUES),", 2),
            _ind("platform_system = select(PLATFORM_SYSTEM_VALUES),", 2),
            _ind("platform_machine = select(PLATFORM_MACHINE_VALUES),", 2),
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

def _build_marker_cycle_edges_json(scc, packages):
    """Builds the JSON-encoded in-cycle edge map for marker mode.

    Returns a JSON string with format:
      {"pkg": [{"dep": "dep_key", "marker_ast": {...}}, ...], ...}
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
                if md.get("marker_ast"):
                    entry["marker_ast"] = md["marker_ast"]
                edge_list.append(entry)
        # Fallback: also check common_dependencies for backward compat
        for dep in pkg.get("common_dependencies", []):
            if dep in scc_set and not any([e["dep"] == dep for e in edge_list]):
                edge_list.append({"dep": dep})
        edges[pkg_key] = edge_list
    return json.encode(edges)

def _render_marker_cycle_member_deps(lines, cycle_groups, packages):
    """Renders pycross_cycle_member_marker_deps macro calls for each cycle member.

    Each macro call internally creates N reachability evaluators + config_settings
    and wraps them in a py_library with select() per dep.
    """
    for _group_name, scc in sorted(cycle_groups.items()):
        edges_json = _build_marker_cycle_edges_json(scc, packages)
        all_members = sorted(scc)

        for pkg_key in all_members:
            lines.append(_ind("pycross_cycle_member_marker_deps("))
            lines.append(_ind('name = "{}",'.format(pkg_key), 2))
            lines.append(_ind('raw_name = "_raw_{}",'.format(pkg_key), 2))
            lines.append(_ind('member = "{}",'.format(pkg_key), 2))
            lines.append(_ind("members = [", 2))
            for m in all_members:
                lines.append(_ind('"{}",'.format(m), 3))
            lines.append(_ind("],", 2))
            lines.append(_ind("edges = '{}',".format(edges_json), 2))
            # Marker values via select
            lines.append(_ind("sys_platform = select(SYS_PLATFORM_VALUES),", 2))
            lines.append(_ind("os_name = select(OS_NAME_VALUES),", 2))
            lines.append(_ind("platform_system = select(PLATFORM_SYSTEM_VALUES),", 2))
            lines.append(_ind("platform_machine = select(PLATFORM_MACHINE_VALUES),", 2))
            lines.append(_ind(")"))
            lines.append("")



def _render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_map, rctx_name):
    """Render a wheel chooser target and per-wheel config_settings + alias."""
    candidates = pkg.get("wheel_candidates", [])
    if not candidates:
        return

    candidates_json = json.encode(candidates)
    chooser_name = "_wheel_chooser_{}".format(pkg_key)

    lines.extend([
        _ind("pycross_wheel_chooser("),
        _ind('name = "{}",'.format(chooser_name), 2),
        _ind("candidates = '{}',".format(candidates_json), 2),
        _ind("sys_platform = select(SYS_PLATFORM_VALUES),", 2),
        _ind("platform_machine = select(PLATFORM_MACHINE_VALUES),", 2),
        _ind(")"),
        "",
    ])

    # Config setting per wheel candidate
    for candidate in candidates:
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
    sdist_file = pkg.get("sdist_file")
    lines.extend([
        _ind("native.alias("),
        _ind('name = "_wheel_{}",'.format(pkg_key), 2),
        _ind("actual = select({", 2),
    ])
    for candidate in candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, _sanitize_name(filename))
        file_ref = candidate.get("file_reference", {})
        target = _wheel_target(file_ref, sdist_file, pkg_key, pkg, repo_map, sdist_map, rctx_name)
        lines.append(_ind('":{cs}": "{target}",'.format(cs = cs_name, target = target), 3))
    lines.append(_ind('"//conditions:default": "@rules_pycross//pycross/private:no_match_error",', 3))
    lines.extend([
        _ind("}),", 2),
        _ind(")"),
        "",
    ])

def _render_marker_package_deps(lines, pkg_key_san, pkg, packages):
    """Render deps using marker-based select() instead of environment-based."""
    marker_deps = pkg.get("marker_dependencies", [])
    if not marker_deps:
        lines.append(_ind("_{}_deps = []".format(pkg_key_san)))
        lines.append("")
        return

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
        lines.append(_ind('":{}",'.format(md["key"]), 2))
    lines.append(_ind("]"))

    if conditional:
        # Each conditional dep gets its own select()
        for md in sorted(conditional, key = lambda m: m["key"]):
            eval_name = _marker_evaluator_name(md["marker"])
            lines[-1] = lines[-1] + " + select({"
            lines.append(_ind('":{}_match": [":{}"],'.format(eval_name, md["key"]), 2))
            lines.append(_ind('"//conditions:default": [],', 2))
            lines.append(_ind("})", 1))

    lines.append("")

def _render_marker_package(lines, pkg_key, pkg, packages, repo_map, sdist_map, rctx_name):
    """Renders all targets for a single package using marker-based deps and wheel selection."""
    pkg_key_san = _sanitize_name(pkg_key)
    package_name = pkg_key.split("@", 1)[0]
    package_version = pkg_key.split("@", 1)[1]

    has_marker_deps = bool(pkg.get("marker_dependencies"))
    has_wheel_candidates = bool(pkg.get("wheel_candidates"))

    sdist_file = pkg.get("sdist_file")
    sdist_label = None
    if sdist_file:
        if sdist_file.get("label"):
            sdist_label = sdist_file["label"]
        elif sdist_file.get("key"):
            sdist_label = repo_map.get(sdist_file["key"])

    # Runtime deps
    if has_marker_deps:
        _render_marker_package_deps(lines, pkg_key_san, pkg, packages)
    elif pkg.get("common_dependencies") or pkg.get("environment_dependencies"):
        _render_package_deps(lines, pkg_key_san, pkg, packages)

    if not (has_wheel_candidates or pkg.get("environment_files")) and "[" in pkg_key:
        # Extra packages just wrap their dependencies
        has_any_deps = has_marker_deps or pkg.get("common_dependencies") or pkg.get("environment_dependencies")
        lines.extend([
            _ind("py_library("),
            _ind('name = "{}",'.format(pkg_key), 2),
            _ind("deps = _{}_deps,".format(pkg_key_san) if has_any_deps else "deps = [],", 2),
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

    # Wheel: use chooser if we have candidates, fall back to env-based select
    if has_wheel_candidates:
        _render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_map, rctx_name)
    elif pkg.get("environment_files"):
        # Fall back to environment-based select (same as existing)
        lines.extend([
            _ind("native.alias("),
            _ind('name = "_wheel_{}",'.format(pkg_key), 2),
        ])
        lines.append(_ind("actual = select({", 2))
        for env_name, env_ref in sorted(pkg.get("environment_files", {}).items()):
            lines.append(_ind('":{env}": "{target}",'.format(
                env = env_name,
                target = _wheel_target(env_ref, sdist_file, pkg_key, pkg, repo_map, sdist_map, rctx_name),
            ), 3))
        lines.append(_ind('"//conditions:default": "@rules_pycross//pycross/private:no_match_error",', 3))
        lines.append(_ind("}),", 2))
        lines.extend([
            _ind(")"),
            "",
        ])

    # Library
    lib_name = pkg_key
    if pkg.get("cycle_group"):
        lib_name = "_raw_{}".format(pkg_key)

    has_any_deps = has_marker_deps or pkg.get("common_dependencies") or pkg.get("environment_dependencies")

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
    environments = lock.get("environments", {})
    packages = lock.get("packages", {})
    cycle_groups = lock.get("cycle_groups", {})
    use_markers = _has_marker_data(packages)

    pycross_loads = ["pycross_dist_info", "pycross_wheel_library"]
    if cycle_groups:
        if use_markers:
            pycross_loads.insert(0, "pycross_cycle_member_marker_deps")
        else:
            pycross_loads.insert(0, "pycross_cycle_member_deps")
    if use_markers:
        pycross_loads.extend(["pycross_pep508_evaluator", "pycross_wheel_chooser"])

    lines = [
        "# This file is generated by rules_pycross.",
        "# It is not intended for manual editing.",
        '"""Pycross-generated dependency targets."""',
        "",
        'load("@rules_pycross//pycross:defs.bzl", {})'.format(
            ", ".join(['"{}"'.format(s) for s in sorted(pycross_loads)]),
        ),
        'load("@rules_python//python:defs.bzl", "py_library")',
    ]

    if use_markers:
        lines.extend([
            'load("@rules_pycross//pycross/private:pep508_marker_values.bzl",',
            '    "OS_NAME_VALUES",',
            '    "PLATFORM_MACHINE_VALUES",',
            '    "PLATFORM_SYSTEM_VALUES",',
            '    "SYS_PLATFORM_VALUES",',
            ")",
        ])

    lines.extend([
        "",
        "# buildifier: disable=unnamed-macro",
        "def targets():",
        _ind('"""Generated package targets."""'),
        "",
    ])

    if use_markers:
        # 1. Marker evaluators (deduped)
        unique_markers = _collect_unique_markers(packages)
        _render_marker_evaluators(lines, unique_markers)

        # 2. Per-member cycle deps (marker-aware)
        _render_marker_cycle_member_deps(lines, cycle_groups, packages)

        # 3. Packages (marker-based)
        for pkg_key, pkg in sorted(packages.items()):
            _render_marker_package(lines, pkg_key, pkg, packages, repo_map, sdist_map, rctx_name)

    else:
        # Legacy environment-based path
        # 1. Environment config_settings
        _render_environment_config_settings(lines, environments)

        # 2. Per-member cycle deps
        _render_cycle_member_deps(lines, cycle_groups, packages, environments)

        # 3. Packages
        for pkg_key, pkg in sorted(packages.items()):
            _render_package(lines, pkg_key, pkg, packages, repo_map, sdist_map, rctx_name)

    # 4. Extras aggregates ([_all_] targets)
    _render_extras_aggregates(lines, packages)

    return "\n".join(lines) + "\n"
