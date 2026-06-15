"""A pure-Starlark universe repository rule that wraps a pycross lock structure.

A universe repo is the shared backing store for one or more user-facing
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
load(":util.bzl", "normalize_pep503_name", "underscore_name")

def _normalize_name(name):
    return normalize_pep503_name(name)

def _underscore_name(name):
    return underscore_name(name)

def _package_repo_impl(rctx):
    # Universe repos always have member_lock_files — even single-lock repos
    # are wrapped in a universe with one member.
    packages = {}
    environments = {}

    # Annotation fields that affect pycross_wheel_library targets.
    # If these differ between members for the same pkg_key, the package
    # is "conflicting" and gets per-member variant targets.
    _ANNOTATION_FIELDS = ["post_install_patches", "install_exclude_globs"]

    # First pass: collect per-member package data for conflict detection.
    member_packages = {}  # member_name -> {pkg_key -> pkg_data}
    for member, lock_label in rctx.attr.member_lock_files.items():
        member_lock = json.decode(rctx.read(rctx.path(Label(lock_label))))

        # Merge environments (union across members).
        for env_name, env_ref in member_lock.get("environments", {}).items():
            if env_name not in environments:
                environments[env_name] = env_ref

        member_packages[member] = member_lock.get("packages", {})

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
        has_conflict = False
        for _, other_data in entries[1:]:
            for field in _ANNOTATION_FIELDS:
                if first_data.get(field, []) != other_data.get(field, []):
                    has_conflict = True
                    break
            if has_conflict:
                break

        if has_conflict:
            # Conflicting: create per-member variant packages.
            conflicts[pkg_key] = [member for member, _ in entries]
            for member, pkg_data in entries:
                variant_key = "{}__via_{}".format(pkg_key, member)
                packages[variant_key] = dict(pkg_data)
        else:
            # Non-conflicting: merge as before.
            packages[pkg_key] = dict(first_data)
            for _, pkg_data in entries[1:]:
                existing = packages[pkg_key]
                for env_name, env_ref in pkg_data.get("environment_files", {}).items():
                    existing.setdefault("environment_files", {})[env_name] = env_ref
                for env_name, env_deps in pkg_data.get("environment_dependencies", {}).items():
                    ed = existing.setdefault("environment_dependencies", {})
                    if env_name not in ed:
                        ed[env_name] = list(env_deps)
                    else:
                        for dep in env_deps:
                            if dep not in ed[env_name]:
                                ed[env_name].append(dep)
                for dep in pkg_data.get("common_dependencies", []):
                    cd = existing.setdefault("common_dependencies", [])
                    if dep not in cd:
                        cd.append(dep)
                if not existing.get("top_level_paths") and pkg_data.get("top_level_paths"):
                    existing["top_level_paths"] = pkg_data["top_level_paths"]
                if not existing.get("sdist_file") and pkg_data.get("sdist_file"):
                    existing["sdist_file"] = pkg_data["sdist_file"]

    # Universe repos have no pins — each thin repo has its own.
    lock = {"packages": packages, "pins": {}, "environments": environments}

    repo_map = {}
    for label, file_key in rctx.attr.repo_map.items():
        repo_map[file_key] = str(label)

    rctx.file("REPO.bazel", "")

    # 1. Render _lock/lock.bzl and _lock/BUILD.bazel
    rctx.file("_lock/lock.bzl", render_lock_bzl(lock, repo_map, rctx.name))
    rctx.file("_lock/BUILD.bazel", "\n".join([
        'package(default_visibility = ["//visibility:public"])',
        "",
        'load(":lock.bzl", "targets")',
        "",
        "targets()",
        "",
    ]))

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
        norm_name = _normalize_name(pkg_key.split("@")[0])
        us_name = _underscore_name(pkg_key.split("@")[0])
        pkg_version = pkg_key.split("@")[1]
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
    normalized_locked_package_names = {}
    for pkg_key in packages.keys():
        norm_pkg = _normalize_name(pkg_key.split("@")[0])
        normalized_locked_package_names[norm_pkg] = True

    rctx.file("_backend/BUILD.bazel", 'package(default_visibility = ["//visibility:public"])\n')

    backend_configs = {}
    for name, config_json in rctx.attr.backend_configs.items():
        backend_configs[name] = json.decode(config_json)

    for macro_name, config in backend_configs.items():
        rule_bzl = config["rule_bzl"]

        tool_deps_labels = []
        for pkg in config["tool_packages"]:
            norm_pkg = _normalize_name(pkg)
            if norm_pkg in normalized_locked_package_names:
                matching = [k for k in packages.keys() if "__via_" not in k and _normalize_name(k.split("@")[0]) == norm_pkg]
                if matching:
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
