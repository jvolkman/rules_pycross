"""A pure-Starlark hub repository rule that wraps a pycross lock structure.

The file structure is as follows:
- REPO.bazel               - The repository root marker.
- BUILD.bazel              - The root build file with //:package aliases.
- defs.bzl                 - Compatibility file (may be empty).
- requirements.bzl         - Provides `requirement()` and `all_requirements`.
- _lock/lock.bzl           - Generated Starlark with all package targets.
- _lock/BUILD.bazel        - Loads lock.bzl and calls targets().
- _wheel/BUILD.bazel         - Versioned wheel aliases.
- _sdist/BUILD.bazel       - Versioned sdist aliases.
- _backend/<rule>.bzl      - Backend macros with pre-configured tool deps.
- <package>/BUILD.bazel    - Pin aliases pointing to //_lock targets.

Naming conventions:
- Root aliases (//:name) use PEP 503 dashes (pycross convention).
- Pin directories (//name/) use underscores (rules_python convention).

From a target perspective:
- //:package             - Alias to the pycross_wheel_library target.
- //:package[extra]      - Alias to the extra dependency group.
- //package:pkg          - The pycross_wheel_library target (pinned version).
- //package:wheel        - The wheel target (pinned version).
- //package:sdist        - The sdist file (pinned version, if available).
- //package:dist_info    - The dist-info files (for py_console_script_binary).
- //package:data         - The package data (alias for :pkg, rules_python compat).
- //package:[extra]      - Extra dependency group (pinned version).
- //_wheel:package            - Pinned wheel target.
- //_wheel:package@ver        - Specific version wheel target.
- //_sdist:package       - Pinned sdist file.
- //_sdist:package@ver   - Specific version sdist file.

The idea is that, for a repo named "pypi", something will depend on
e.g. `@pypi//:numpy`, `@pypi//numpy:pkg`, or `@pypi//numpy`.

Pin directory names use underscores (rules_python convention).
Root alias names use PEP 503 dashes (pycross convention).
"""

load(":resolved_lock_renderer.bzl", "render_lock_bzl")
load(":util.bzl", "normalize_pep503_name", "underscore_name")

def _normalize_name(name):
    return normalize_pep503_name(name)

def _underscore_name(name):
    return underscore_name(name)

_requirement_func = """\
def requirement(pkg):
    extra = None
    if "[" in pkg:
        pkg, extra = pkg.split("[", 1)
        extra = extra.rstrip("]")

    # Convert given name into PEP 503 normalized form (dashes).
    # Root aliases use this form (pycross convention).
    # https://packaging.python.org/en/latest/specifications/name-normalization/#name-normalization
    pkg = pkg.replace("_", "-").replace(".", "-").lower()
    for i in range(len(pkg)):
        if "--" in pkg:
            pkg = pkg.replace("--", "-")
        else:
            break

    if extra:
        return "@@{repo_name}//:%s[%s]" % (pkg, extra)
    return "@@{repo_name}//:%s" % pkg
"""

def _requirements_bzl(rctx, pins):
    lines = [
        _requirement_func.format(repo_name = rctx.name),
        "",
        "# All pinned requirements",
        "all_requirements = [",
    ]
    for pin in sorted(pins.keys()):
        lines.append('    "@@{repo_name}//:{pin}",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")

    return "\n".join(lines) + "\n"

def _safe_name(pin_name, name):
    return name + "_" if pin_name == name else name

def _pin_build(target_name, original_pin_name, pin_target, package, squash_extras = False):
    """Generates the BUILD file for a pin directory (//package/)."""
    pin_target_base = (pin_target + "__squashed") if (squash_extras and package.get("extra_dependencies")) else pin_target
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        # //package -> //package:package -> //_lock:<pin_target>
        "alias(",
        '    name = "{}",'.format(target_name),
        '    actual = "//_lock:{}",'.format(pin_target_base),
        ")",
        "",
        # //package:pkg -> //_lock:<pin_target>
        "alias(",
        '    name = "{}",'.format(_safe_name(target_name, "pkg")),
        '    actual = "//_lock:{}",'.format(pin_target_base),
        ")",
        "",
        # //package:wheel -> //_wheel:<original_pin_name>
        "alias(",
        '    name = "{}",'.format(_safe_name(target_name, "wheel")),
        '    actual = "//_wheel:{}",'.format(original_pin_name),
        ")",
        "",
        # //package:dist_info -> //_lock:_dist_info_<pin_target>
        "alias(",
        '    name = "{}",'.format(_safe_name(target_name, "dist_info")),
        '    actual = "//_lock:_dist_info_{}",'.format(pin_target),
        ")",
        "",
        # //package:data -> //_lock:<pin_target> (rules_python compat)
        "alias(",
        '    name = "{}",'.format(_safe_name(target_name, "data")),
        '    actual = "//_lock:{}",'.format(pin_target_base),
        ")",
        "",
    ]

    sdist_file = package.get("sdist_file")
    if sdist_file:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "sdist")),
            '    actual = "//_sdist:{}",'.format(original_pin_name),
            ")",
            "",
        ])

    for extra_name in sorted(package.get("extra_dependencies", {}).keys()):
        lines.extend([
            "alias(",
            '    name = "[{}]",'.format(extra_name),
            '    actual = "//_lock:{}",'.format(pin_target_base if squash_extras else "{}[{}]".format(pin_target, extra_name)),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

def _package_repo_impl(rctx):
    squash_extras = False
    is_hub = bool(rctx.attr.member_lock_files)

    if is_hub:
        # Hub mode does not squash. Hub contains canonical un-squashed graphs.
        # Thin repos decide whether to squash via their aliases.
        # Detect annotation conflicts and generate per-member variants.
        packages = {}
        environments = {}
        pins = {}  # Hub has no pins; each thin repo has its own.

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
                    for extra, extra_deps in pkg_data.get("extra_dependencies", {}).items():
                        ex = existing.setdefault("extra_dependencies", {})
                        if extra not in ex:
                            ex[extra] = dict(extra_deps)
                        else:
                            # Union common_dependencies within the extra.
                            for dep in extra_deps.get("common_dependencies", []):
                                ecd = ex[extra].setdefault("common_dependencies", [])
                                if dep not in ecd:
                                    ecd.append(dep)

                            # Union environment_dependencies within the extra.
                            for env_name, env_deps in extra_deps.get("environment_dependencies", {}).items():
                                eed = ex[extra].setdefault("environment_dependencies", {})
                                if env_name not in eed:
                                    eed[env_name] = list(env_deps)
                                else:
                                    for dep in env_deps:
                                        if dep not in eed[env_name]:
                                            eed[env_name].append(dep)
                    if not existing.get("top_level_paths") and pkg_data.get("top_level_paths"):
                        existing["top_level_paths"] = pkg_data["top_level_paths"]
                    if not existing.get("sdist_file") and pkg_data.get("sdist_file"):
                        existing["sdist_file"] = pkg_data["sdist_file"]

        # Build a synthetic lock dict for the renderer.
        lock = {"packages": packages, "pins": pins, "environments": environments}
    else:
        lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
        lock = json.decode(rctx.read(lock_json_path))
        squash_extras = lock.get("squash_extras", False)
        packages = lock["packages"]
        pins = lock["pins"]

    # 0. Read inspection.json from wheel repos to populate top_level_paths.
    # repo_map is a label_keyed_string_dict: Label -> file_key.
    # Labels are resolved by Bazel from the extension context, so we can use
    # label.repo_name to construct inspection labels without string splitting.
    # Only the wheel repos we actually call rctx.path() on get fetched (lazy).

    # Build a reverse map (file_key -> label_string) for the renderer and
    # other downstream consumers that need forward string lookups.
    repo_map = {}  # file_key -> label_string
    wheel_labels = {}  # file_key -> Label (only wheel entries)
    for label, file_key in rctx.attr.repo_map.items():
        repo_map[file_key] = str(label)
        if label.name == "wheel":
            wheel_labels[file_key] = label

    sdist_labels = {}  # file_key -> Label
    for label, file_key in getattr(rctx.attr, "sdist_map", {}).items():
        sdist_labels[file_key] = label

    for pkg_key, pkg in packages.items():
        # Skip if the user explicitly overrode top_level_paths via annotation.
        if pkg.get("top_level_paths"):
            continue
        for _, file_ref in pkg.get("environment_files", {}).items():
            key = file_ref.get("key")
            if not key:
                continue
            wheel_label = wheel_labels.get(key)
            if wheel_label:
                inspection_label = Label("@@{}//:inspection.json".format(wheel_label.repo_name))
                inspection_path = rctx.path(inspection_label)
                if inspection_path.exists:
                    inspection_data = json.decode(rctx.read(inspection_path))
                    if "top_level_paths" in inspection_data:
                        pkg["top_level_paths"] = inspection_data["top_level_paths"]
                break

            sdist_label = sdist_labels.get(key)
            if sdist_label:
                inspection_label = Label("@@{}//:inspection.json".format(sdist_label.repo_name))
                inspection_path = rctx.path(inspection_label)
                if inspection_path.exists:
                    inspection_data = json.decode(rctx.read(inspection_path))
                    if "top_level_paths" in inspection_data:
                        pkg["top_level_paths"] = inspection_data["top_level_paths"]
                break

    # 0.5. Generate modules_mapping.json
    # Known file extensions that should be stripped to derive the module name.
    _MODULE_EXTENSIONS = [".pth", ".so", ".py"]

    modules_mapping = {}
    for pin_name, pin_target in pins.items():
        pkg = packages.get(pin_target)
        if pkg:
            for tlp in pkg.get("top_level_paths", []):
                # Strip known file extensions to derive the importable module name.
                module_name = tlp
                for ext in _MODULE_EXTENSIONS:
                    if module_name.endswith(ext):
                        module_name = module_name[:-len(ext)]
                        break

                # Convert path separators to dots for namespace packages.
                if "/" in module_name:
                    module_name = module_name.replace("/", ".")
                modules_mapping[module_name] = pin_name

    rctx.file("modules_mapping.json", json.encode(modules_mapping))

    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")  # Empty file for compatibility
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

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

    # 2. Root BUILD.bazel with //:package aliases (PEP 503 dash-form names)
    root_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl", "requirements.bzl", "modules_mapping.json"])',
        "",
    ]
    for pin_name in sorted(pins.keys()):
        us_name = _underscore_name(pin_name)
        pin_target = pins[pin_name]
        package = packages[pin_target]

        # //:pin-name -> //pin_name:pkg
        root_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = "//{}:pkg",'.format(us_name),
            ")",
            "",
        ])

        # //:pin-name[extra] -> //pin_name:[extra]
        for extra_name in sorted(package.get("extra_dependencies", {}).keys()):
            root_build_lines.extend([
                "alias(",
                '    name = "{}[{}]",'.format(pin_name, extra_name),
                '    actual = "//{}:[{}]",'.format(us_name, extra_name),
                ")",
                "",
            ])
    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # 3. Pin directories: //package/ with aliases to //_lock targets
    # Directory names use underscores (rules_python convention).
    for pin_name, pin_target in sorted(pins.items()):
        package = packages[pin_target]
        underscore_name = _underscore_name(pin_name)
        rctx.file("{}/BUILD.bazel".format(underscore_name), _pin_build(underscore_name, pin_name, pin_target, package, squash_extras))

    # 4. _wheel/ and _sdist/ directories for versioned artifact access
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
        norm_name = _normalize_name(pkg_key.split("@")[0])
        underscore_name = _underscore_name(pkg_key.split("@")[0])
        pkg_version = pkg_key.split("@")[1]
        whldir_name = "{}-{}.whldir".format(underscore_name, pkg_version)

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

    # Unversioned pin aliases: _wheel:name -> _wheel:name@version
    for pin_name in sorted(pins.keys()):
        pin_target = pins[pin_name]
        pin_norm_name = _normalize_name(pin_target.split("@")[0])
        pin_version = pin_target.split("@")[1]
        wheel_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = ":{}@{}",'.format(pin_norm_name, pin_version),
            ")",
            "",
        ])

        sdist_file = packages[pin_target].get("sdist_file")
        if sdist_file:
            sdist_lines.extend([
                "alias(",
                '    name = "{}",'.format(pin_name),
                '    actual = "//_lock:_sdist_{}",'.format(pin_target),
                ")",
                "",
            ])

    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_lines) + "\n")
    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_lines) + "\n")

    # 5. _backend/ directory
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
                tool_deps_labels.append("//{}:pkg".format(_underscore_name(pkg)))

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
            doc = "For hub repos: maps member repo names to their resolved lock file labels.",
            default = {},
        ),
    },
)
