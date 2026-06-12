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

def _normalize_name(name):
    """PEP 503 normalization: lowercase, replace [_-.] with -, collapse runs."""
    name = name.replace("_", "-").replace(".", "-").lower()
    for _i in range(len(name)):
        if "--" in name:
            name = name.replace("--", "-")
        else:
            break
    return name

def _underscore_name(name):
    """rules_python-style normalization: lowercase, replace [-. ] with _."""
    return _normalize_name(name).replace("-", "_")

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

def _pin_build(target_name, original_pin_name, pin_target, package):
    """Generates the BUILD file for a pin directory (//package/)."""
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        # //package -> //package:package -> //_lock:<pin_target>
        "alias(",
        '    name = "{}",'.format(target_name),
        '    actual = "//_lock:{}",'.format(pin_target),
        ")",
        "",
        # //package:pkg -> //_lock:<pin_target>
        "alias(",
        '    name = "{}",'.format(_safe_name(target_name, "pkg")),
        '    actual = "//_lock:{}",'.format(pin_target),
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
        '    actual = "//_lock:{}",'.format(pin_target),
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
            '    actual = "//_lock:{}[{}]",'.format(pin_target, extra_name),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

def _package_repo_impl(rctx):
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock = json.decode(rctx.read(lock_json_path))
    packages = lock["packages"]
    pins = lock["pins"]

    # 0. Read inspection.json from wheel repos to populate top_level_packages.
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

    for pkg_key, pkg in packages.items():
        # Skip if the user explicitly overrode top_level_packages via annotation.
        if pkg.get("top_level_packages"):
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
                    if "top_level_packages" in inspection_data:
                        pkg["top_level_packages"] = inspection_data["top_level_packages"]
                break

    # 0.5. Generate modules_mapping.json
    modules_mapping = {}
    for pin_name, pin_target in pins.items():
        pkg = packages.get(pin_target)
        if pkg:
            tlps = pkg.get("top_level_packages", [])
            for tlp in tlps:
                module_name = tlp.replace("/", ".")
                modules_mapping[module_name] = pin_name

    rctx.file("modules_mapping.json", json.encode(modules_mapping))

    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")  # Empty file for compatibility
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

    # 1. Render _lock/lock.bzl and _lock/BUILD.bazel
    rctx.file("_lock/lock.bzl", render_lock_bzl(lock, repo_map, rctx.name))
    rctx.file("_lock/BUILD.bazel", "\n".join([
        'package(default_visibility = ["//:__subpackages__"])',
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
        package = packages[pins[pin_name]]

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
        rctx.file("{}/BUILD.bazel".format(underscore_name), _pin_build(underscore_name, pin_name, pin_target, package))

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
        "backend_configs": attr.string_dict(
            doc = "Maps pycross rule names to JSON-encoded config dicts with 'rule_bzl' and 'tool_packages'.",
        ),
    },
)
