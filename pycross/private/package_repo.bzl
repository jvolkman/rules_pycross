"""A pure-Starlark hub repository rule that wraps a pycross lock structure.

The file structure is as follows:
- REPO.bazel               - The repository root marker.
- BUILD.bazel              - The root build file with //:package aliases.
- defs.bzl                 - Compatibility file (may be empty).
- requirements.bzl         - Provides `requirement()` and `all_requirements`.
- _lock/lock.bzl           - Generated Starlark with all package targets.
- _lock/BUILD.bazel        - Loads lock.bzl and calls targets().
- _wheel/BUILD.bazel       - Versioned wheel aliases.
- _sdist/BUILD.bazel       - Versioned sdist aliases.
- _backend/<rule>.bzl      - Backend macros with pre-configured tool deps.
- <package>/BUILD.bazel    - Pin aliases pointing to //_lock targets.

From a target perspective:
- //:package             - Alias to the pycross_wheel_library target.
- //package:pkg          - The pycross_wheel_library target (pinned version).
- //package:whl          - The wheel file (pinned version).
- //package:sdist        - The sdist file (pinned version, if available).
- //package:dist_info    - The dist-info files (for py_console_script_binary).
- //package:data         - The package data (alias for :pkg, rules_python compat).
- //package:[extra]      - Extra dependency group (pinned version).
- //_wheel:package       - Pinned wheel file.
- //_wheel:package@ver   - Specific version wheel file.
- //_sdist:package       - Pinned sdist file.
- //_sdist:package@ver   - Specific version sdist file.

The idea is that, for a repo named "pypi", something will depend on
e.g. `@pypi//:numpy`, `@pypi//numpy:pkg`, or `@pypi//numpy`.

The package names in the root of the repo are all normalized per
https://packaging.python.org/en/latest/specifications/name-normalization.
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

    # Convert given name into normalized package name.
    # https://packaging.python.org/en/latest/specifications/name-normalization/#name-normalization
    pkg = pkg.replace("_", "-").replace(".", "-").lower()
    for i in range(len(pkg)):
        if "--" in pkg:
            pkg = pkg.replace("--", "-")
        else:
            break

    if extra:
        return "@@{repo_name}//%s:[%s]" % (pkg, extra)
    return "@@{repo_name}//%s:pkg" % pkg
"""

def _requirements_bzl(rctx, pins):
    lines = [
        _requirement_func.format(repo_name = rctx.name),
        "",
        "# All pinned requirements",
        "all_requirements = [",
    ]
    for pin in sorted(pins.keys()):
        lines.append('    "@@{repo_name}//{pin}:pkg",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")
    lines.extend([
        "",
        "# All wheel requirements",
        "all_whl_requirements = [",
    ])
    for pin in sorted(pins.keys()):
        lines.append('    "@@{repo_name}//_wheel:{pin}",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")

    return "\n".join(lines) + "\n"

def _pin_build(pin_name, pin_target, package):
    """Generates the BUILD file for a pin directory (//package/)."""
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        # //package -> //package:package -> //_lock:<pin_target>
        "alias(",
        '    name = "{}",'.format(pin_name),
        '    actual = "//_lock:{}",'.format(pin_target),
        ")",
        "",
        # //package:pkg -> //_lock:<pin_target>
        "alias(",
        '    name = "pkg",',
        '    actual = "//_lock:{}",'.format(pin_target),
        ")",
        "",
        # //package:whl -> //_lock:_wheel_<pin_target>
        "alias(",
        '    name = "whl",',
        '    actual = "//_lock:_wheel_{}",'.format(pin_target),
        ")",
        "",
        # //package:dist_info -> //_lock:_dist_info_<pin_target>
        "alias(",
        '    name = "dist_info",',
        '    actual = "//_lock:_dist_info_{}",'.format(pin_target),
        ")",
        "",
        # //package:data -> //_lock:<pin_target> (rules_python compat)
        "alias(",
        '    name = "data",',
        '    actual = "//_lock:{}",'.format(pin_target),
        ")",
        "",
    ]

    sdist_file = package.get("sdist_file")
    if sdist_file:
        lines.extend([
            "alias(",
            '    name = "sdist",',
            '    actual = "//_lock:_sdist_{}",'.format(pin_target),
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

    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")  # Empty file for compatibility
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

    # 1. Render _lock/lock.bzl and _lock/BUILD.bazel
    rctx.file("_lock/lock.bzl", render_lock_bzl(lock, rctx.attr.repo_map, rctx.name))
    rctx.file("_lock/BUILD.bazel", "\n".join([
        'package(default_visibility = ["//:__subpackages__"])',
        "",
        'load(":lock.bzl", "targets")',
        "",
        "targets()",
        "",
    ]))

    # 2. Root BUILD.bazel with //:package aliases
    root_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl", "requirements.bzl"])',
        "",
    ]
    for pin_name in sorted(pins.keys()):
        root_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = "//{}:pkg",'.format(pin_name),
            ")",
            "",
        ])
    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # 3. Pin directories: //package/ with aliases to //_lock targets
    for pin_name, pin_target in sorted(pins.items()):
        package = packages[pin_target]
        rctx.file("{}/BUILD.bazel".format(pin_name), _pin_build(pin_name, pin_target, package))

        # Also create a rules_python-compatible underscore directory if different
        underscore_name = _underscore_name(pin_name)
        if underscore_name != pin_name:
            rctx.file("{}/BUILD.bazel".format(underscore_name), _pin_build(underscore_name, pin_target, package))

    # 4. _wheel/ and _sdist/ directories for versioned artifact access
    wheel_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    sdist_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    for pkg_key in sorted(packages.keys()):
        norm_name = _normalize_name(pkg_key.split("@")[0])
        pkg_version = pkg_key.split("@")[1]

        # Versioned alias: _wheel:name@version -> //_lock:_wheel_<key>
        wheel_lines.extend([
            "alias(",
            '    name = "{}@{}",'.format(norm_name, pkg_version),
            '    actual = "//_lock:_wheel_{}",'.format(pkg_key),
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

    # Unversioned pin aliases: _wheel:name -> //name:whl
    for pin_name in sorted(pins.keys()):
        wheel_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = "//{}:whl",'.format(pin_name),
            ")",
            "",
        ])

        pin_target = pins[pin_name]
        sdist_file = packages[pin_target].get("sdist_file")
        if sdist_file:
            sdist_lines.extend([
                "alias(",
                '    name = "{}",'.format(pin_name),
                '    actual = "//{}:sdist",'.format(pin_name),
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
                tool_deps_labels.append("//{}:pkg".format(norm_pkg))

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
        "repo_map": attr.string_dict(),
        "backend_configs": attr.string_dict(
            doc = "Maps pycross rule names to JSON-encoded config dicts with 'rule_bzl' and 'tool_packages'.",
        ),
        "write_install_deps": attr.bool(),
        "legacy_naming": attr.bool(
            doc = "Unused, kept for compatibility.",
        ),
    },
)
