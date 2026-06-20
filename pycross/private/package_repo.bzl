"""A pure-Starlark workspace repository rule that wraps a pycross lock structure.

A workspace repo is the shared backing store for one or more user-facing
"thin" package repos. It contains the actual pycross_wheel_library targets
and artifact references, while thin repos provide pin aliases and
user-facing convenience targets.

The file structure is as follows:
- REPO.bazel               - The repository root marker.
- BUILD.bazel              - Minimal root build file.
- _lock/lock.bzl           - Generated Starlark with all package targets.
- _lock/BUILD.bazel        - Loads lock.bzl and calls targets().
- _wheel/BUILD.bazel       - Versioned wheel aliases.
- _sdist/BUILD.bazel       - Versioned sdist aliases.
- _backend/<rule>.bzl      - Backend macros with pre-configured tool deps.
"""

load(":resolved_lock_renderer.bzl", "render_lock_bzl")
load(":util.bzl", "key_name", "key_parts", "normalize_pep503_name", "underscore_name")

def _normalize_name(name):
    return normalize_pep503_name(name)

def _underscore_name(name):
    return underscore_name(name)

def _merge_dependencies(pkg_key, first_data, entries, member_envs):
    merged = dict(first_data)

    for _, pkg_data in entries[1:]:
        for env_name, env_ref in pkg_data.get("environment_files", {}).items():
            merged.setdefault("environment_files", {})[env_name] = env_ref
        if not merged.get("site_paths") and pkg_data.get("site_paths"):
            merged["site_paths"] = pkg_data["site_paths"]
        if not merged.get("data_level_paths") and pkg_data.get("data_level_paths"):
            merged["data_level_paths"] = pkg_data["data_level_paths"]
        if not merged.get("sdist_file") and pkg_data.get("sdist_file"):
            merged["sdist_file"] = pkg_data["sdist_file"]

    # Check whether common_dependencies differ between members.
    has_common_dep_conflict = False
    for _, other_data in entries[1:]:
        if sorted(first_data.get("common_dependencies", [])) != sorted(other_data.get("common_dependencies", [])):
            has_common_dep_conflict = True
            break

    if has_common_dep_conflict:
        # Validate: members with overlapping environments must agree on deps.
        env_to_member = {}  # env_name -> (member, common_deps)
        for member, pkg_data in entries:
            member_common = sorted(pkg_data.get("common_dependencies", []))
            for env_name in member_envs.get(member, []):
                prev_member, prev_deps = env_to_member.setdefault(env_name, (member, member_common))
                if prev_deps != member_common:
                    fail(
                        "Workspace conflict for package '{}': members '{}' and '{}' " +
                        "share environment '{}' but have different dependencies.\n" +
                        "  {}: {}\n  {}: {}\n\n" +
                        "Members sharing the same workspace must resolve compatible " +
                        "dependency versions for overlapping environments.".format(
                            pkg_key,
                            prev_member,
                            member,
                            env_name,
                            prev_member,
                            prev_deps,
                            member,
                            member_common,
                        ),
                    )

        # Promote differing common_dependencies to environment_dependencies.
        # Each member's environments are disjoint, so the environment
        # select() naturally routes to the correct deps.
        ed = merged.setdefault("environment_dependencies", {})
        for member, pkg_data in entries:
            member_common = pkg_data.get("common_dependencies", [])
            for env_name in member_envs.get(member, []):
                env_deps = list(ed.get(env_name, []))
                for dep in member_common:
                    if dep not in env_deps:
                        env_deps.append(dep)
                ed[env_name] = env_deps

            # Also merge this member's environment_dependencies.
            for env_name, deps in pkg_data.get("environment_dependencies", {}).items():
                env_deps = list(ed.get(env_name, []))
                for dep in deps:
                    if dep not in env_deps:
                        env_deps.append(dep)
                ed[env_name] = env_deps

        # Clear common_dependencies since they've been promoted.
        merged.pop("common_dependencies", None)
    else:
        # Common deps agree — merge as union.
        for _, pkg_data in entries[1:]:
            for dep in pkg_data.get("common_dependencies", []):
                cd = merged.setdefault("common_dependencies", [])
                if dep not in cd:
                    cd.append(dep)
            for env_name, env_deps in pkg_data.get("environment_dependencies", {}).items():
                ed = merged.setdefault("environment_dependencies", {})
                if env_name not in ed:
                    ed[env_name] = list(env_deps)
                else:
                    for dep in env_deps:
                        if dep not in ed[env_name]:
                            ed[env_name].append(dep)

    return merged

def _package_repo_impl(rctx):
    # Workspace repos always have member_lock_files — even single-lock repos
    # are wrapped in a workspace with one member.
    packages = {}
    environments = {}

    # Annotation fields that affect pycross_wheel_library targets.
    # If these differ between members for the same pkg_key, the package
    # is "conflicting" and gets per-member variant targets.
    _ANNOTATION_FIELDS = ["post_install_patches", "install_exclude_globs"]

    # First pass: collect per-member package data, environment names, and cycle groups.
    member_packages = {}  # member_name -> {pkg_key -> pkg_data}
    member_envs = {}  # member_name -> [env_name, ...]
    cycle_groups = {}  # group_name -> [pkg_key, ...]
    conflict_items = {}  # qualified_name -> True (dedup across members)
    for member, lock_label in rctx.attr.member_lock_files.items():
        member_lock = json.decode(rctx.read(rctx.path(Label(lock_label))))

        # Merge environments (union across members).
        member_env_names = []
        for env_name, env_ref in member_lock.get("environments", {}).items():
            member_env_names.append(env_name)
            if env_name not in environments:
                environments[env_name] = env_ref

        for conflict_set in member_lock.get("conflicts", []):
            for item in conflict_set["items"]:
                if item["kind"] == "project":
                    qname = "package_{}".format(item["package"])
                else:
                    qname = "{}_{}".format(item["kind"], item["name"])
                conflict_items[qname] = True

        member_envs[member] = sorted(member_env_names)
        member_packages[member] = member_lock.get("packages", {})

        # Merge cycle groups (union across members).
        for group_name, group_members in member_lock.get("cycle_groups", {}).items():
            if group_name in cycle_groups and sorted(cycle_groups[group_name]) != sorted(group_members):
                fail("Cycle group {} conflicts between workspace members ({} vs {})".format(group_name, cycle_groups[group_name], group_members))
            cycle_groups[group_name] = group_members

    # Second pass: detect conflicts and build merged package set.
    # conflicts maps pkg_key -> [member_name, ...] for packages with
    # differing annotations across members.
    conflicts = {}
    all_pkg_keys = {}  # pkg_key -> list of (member, pkg_data)
    for member, pkgs in member_packages.items():
        for pkg_key, pkg_data in pkgs.items():
            all_pkg_keys.setdefault(pkg_key, []).append((member, pkg_data))

    for pkg_key, entries in all_pkg_keys.items():
        if len(entries) <= 1:
            # Only in one member — no conflict possible.
            packages[pkg_key] = dict(entries[0][1])
            continue

        # Check annotation fields for differences.
        _, first_data = entries[0]
        has_annotation_conflict = False
        for _, other_data in entries[1:]:
            for field in _ANNOTATION_FIELDS:
                if first_data.get(field, []) != other_data.get(field, []):
                    has_annotation_conflict = True
                    break
            if has_annotation_conflict:
                break

        if has_annotation_conflict:
            # Conflicting annotations: create per-member variant packages.
            conflicts[pkg_key] = [member for member, _ in entries]
            for member, pkg_data in entries:
                variant_key = "{}__via_{}".format(pkg_key, member)
                packages[variant_key] = dict(pkg_data)
        else:
            packages[pkg_key] = _merge_dependencies(pkg_key, first_data, entries, member_envs)

    # Workspace repos have no pins — each thin repo has its own.
    lock = {
        "packages": packages,
        "pins": {},
        "environments": environments,
        "cycle_groups": cycle_groups,
    }

    repo_map = {}
    for label, file_key in rctx.attr.repo_map.items():
        repo_map[file_key] = str(label)

    sdist_map = {}
    for label, file_key in rctx.attr.sdist_map.items():
        sdist_map[file_key] = str(label)

    rctx.file("REPO.bazel", "")

    # 1. Render _lock/lock.bzl and _lock/BUILD.bazel
    rctx.file("_lock/lock.bzl", render_lock_bzl(lock, repo_map, sdist_map, rctx.name))

    lock_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'load(":lock.bzl", "targets")',
        "",
    ]
    if conflict_items:
        lock_build_lines.extend([
            'load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")',
            "",
        ])
    lock_build_lines.extend([
        "targets()",
        "",
    ])
    for qname in sorted(conflict_items.keys()):
        lock_build_lines.extend([
            "bool_flag(",
            '    name = "{}",'.format(qname),
            "    build_setting_default = False,",
            ")",
            "",
            "config_setting(",
            '    name = "is_{}",'.format(qname),
            '    flag_values = {{":{flag}": "True"}},'.format(flag = qname),
            ")",
            "",
        ])

    rctx.file("_lock/BUILD.bazel", "\n".join(lock_build_lines))

    # 2. Minimal root BUILD.bazel
    rctx.file("BUILD.bazel", "\n".join([
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]))

    # 3. _wheel/ and _sdist/ directories for versioned artifact access
    wheel_lines = [
        'load("@rules_pycross//pycross/private:wheel_dir.bzl", "pycross_wheel_dir")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    sdist_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    for pkg_key in sorted(packages.keys()):
        # Skip variant packages (they use __via_ suffix for conflict resolution)
        if "__via_" in pkg_key:
            continue
        pkg_name_part, pkg_version = key_parts(pkg_key)
        norm_name = _normalize_name(pkg_name_part)
        us_name = _underscore_name(pkg_name_part)
        whldir_name = "{}-{}.whldir".format(us_name, pkg_version)

        # Versioned target: _wheel:name@version -> pycross_wheel_dir wrapping //_lock:_wheel_{key}
        wheel_lines.extend([
            "pycross_wheel_dir(",
            '    name = "{}@{}",'.format(norm_name, pkg_version),
            '    src = "//_lock:_wheel_{}",'.format(pkg_key),
            '    whldir_name = "{}",'.format(whldir_name),
            ")",
            "",
        ])

        sdist_file = packages[pkg_key].get("sdist_file")
        if sdist_file:
            sdist_lines.extend([
                "alias(",
                '    name = "{}@{}",'.format(norm_name, pkg_version),
                '    actual = "//_lock:_sdist_{}",'.format(pkg_key),
                ")",
                "",
            ])

    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_lines) + "\n")
    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_lines) + "\n")

    # 4. _backend/ directory
    rctx.file("_backend/BUILD.bazel", 'package(default_visibility = ["//visibility:public"])\n')

    backend_configs = {}
    for name, config_json in rctx.attr.backend_configs.items():
        backend_configs[name] = json.decode(config_json)

    for macro_name, config in backend_configs.items():
        rule_bzl = config["rule_bzl"]

        tool_deps_labels = []
        for pkg in config["tool_packages"]:
            norm_pkg = _normalize_name(pkg)

            # Find a matching package in the lockfile
            matching = [k for k in packages.keys() if _normalize_name(key_name(k)) == norm_pkg]
            if matching:
                # Use the first match. For cycle groups, the name is _raw_{pkg_key}.
                # But here we just need the dependency, so pointing to //_lock:{pkg_key} is fine.
                tool_deps_labels.append("//_lock:{}".format(matching[0]))

        lines = [
            '"""Backend macro with pre-configured tool defaults for this lock repo."""',
            "",
            'load("{rule_bzl}", _{macro_name} = "{macro_name}")'.format(
                rule_bzl = rule_bzl,
                macro_name = macro_name,
            ),
            "",
            "def {macro_name}(name, **kwargs):".format(macro_name = macro_name),
        ]

        if tool_deps_labels:
            lines.append("    if \"tool_deps\" not in kwargs:")
            lines.append("        kwargs[\"tool_deps\"] = [")
            for label in tool_deps_labels:
                lines.append("            Label(\"{}\"),".format(label))
            lines.append("        ]")

        lines.extend([
            "    _{macro_name}(name = name, **kwargs)".format(macro_name = macro_name),
            "",
        ])

        rctx.file("_backend/{}.bzl".format(macro_name), "\n".join(lines))

package_repo = repository_rule(
    implementation = _package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "repo_map": attr.label_keyed_string_dict(),
        "sdist_map": attr.label_keyed_string_dict(),
        "backend_configs": attr.string_dict(
            doc = "Maps pycross rule names to JSON-encoded config dicts with 'rule_bzl' and 'tool_packages'.",
        ),
        "member_lock_files": attr.string_dict(
            doc = "Maps member repo names to their resolved lock file labels.",
            mandatory = True,
        ),
    },
)
