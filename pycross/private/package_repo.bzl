"""A pure-Starlark hub repository rule that wraps a pycross lock structure.

The file structure is as follows:
- REPO.bazel               - The repository root marker.
- BUILD.bazel              - The root build file with pin aliases.
- defs.bzl                 - Compatibility file (may be empty).
- requirements.bzl         - Provides `requirement()` and `all_requirements`.
- _env/BUILD.bazel         - Environment config_settings.
- _cycles/BUILD.bazel      - Cycle group py_libraries (if any).
- _backend/<rule>.bzl      - Backend macros with pre-configured tool deps.
- <package>/BUILD.bazel    - Pin aliases pointing to the active version.
- <package>/v<ver>/BUILD.bazel - Actual pycross_wheel_library and file aliases.

From a target perspective:
- //package              - Alias to //package:package (the library target).
- //package:pkg          - The pycross_wheel_library target (pinned version).
- //package:whl          - The wheel file (pinned version).
- //package:sdist        - The sdist file (pinned version, if available).
- //package:dist_info    - The dist-info files (for py_console_script_binary compat).
- //package:[extra]      - Extra dependency group (pinned version).
- //_wheel:package       - Pinned wheel file.
- //_wheel:package@ver   - Specific version wheel file.
- //_sdist:package       - Pinned sdist file.
- //_sdist:package@ver   - Specific version sdist file.

When `legacy_naming = True`, the following additional targets are generated:
- //:package             - Root alias to //package:package (v1 pattern).

The idea is that, for a repo named "pypi", something will depend on e.g. `@pypi//:numpy` or `@pypi//numpy:pkg`.

The package names in the root of the repo are all normalized per
https://packaging.python.org/en/latest/specifications/name-normalization.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":resolved_lock_renderer.bzl", "render_lock_bzl")

_requirement_func = """\
def requirement(pkg):
    # Convert given name into normalized package name.
    # https://packaging.python.org/en/latest/specifications/name-normalization/#name-normalization
    pkg = pkg.replace("_", "-").replace(".", "-").lower()
    for i in range(len(pkg)):
        if "--" in pkg:
            pkg = pkg.replace("--", "-")
        else:
            break
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
        lines.append('    "@@{repo_name}//{pin}:whl",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")

    return "\n".join(lines) + "\n"

def _pin_build(pkg_name, pkg_key, package, sdist_file = None):
    _, package_version = pkg_key.split("@", 1)

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        "alias(",
        '    name = "{}",'.format(pkg_name),
        '    actual = "//{}/v{}:{}",'.format(pkg_name, package_version, pkg_name),
        ")",
        "",
        "alias(",
        '    name = "pkg",',
        '    actual = "//{}/v{}:pkg",'.format(pkg_name, package_version),
        ")",
        "",
        "alias(",
        '    name = "whl",',
        '    actual = "//{}/v{}:whl",'.format(pkg_name, package_version),
        ")",
        "",
        "alias(",
        '    name = "dist_info",',
        '    actual = "//{}/v{}:dist_info",'.format(pkg_name, package_version),
        ")",
        "",
    ]

    if sdist_file:
        lines.extend([
            "alias(",
            '    name = "sdist",',
            '    actual = "//{}/v{}:sdist",'.format(pkg_name, package_version),
            ")",
            "",
        ])
    for extra_name in sorted(package.get("extra_dependencies", {}).keys()):
        lines.extend([
            "alias(",
            '    name = "[{}]",'.format(extra_name),
            '    actual = "//{}/v{}:[{}]",'.format(pkg_name, package_version, extra_name),
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

    # 1. Render the lock files
    build_files = render_lock_bzl(lock, rctx.attr.repo_map, rctx.name)
    for path, build_content in build_files.items():
        rctx.file(path, build_content)

    # 2. Write the root BUILD.bazel.
    root_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl", "requirements.bzl"])',
        "",
    ]

    # Legacy naming: add //:package root aliases (v1 pattern).
    if rctx.attr.legacy_naming:
        for pin, pin_target in sorted(pins.items()):
            root_build_lines.extend([
                "alias(",
                '    name = "{}",'.format(pin),
                '    actual = "//{}:{}",'.format(pin, pin),
                ")",
                "",
            ])

    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # 4. Write package BUILD subdirectories containing aliases for wheel/sdist
    for pin, pin_target in sorted(pins.items()):
        package = lock["packages"][pin_target]
        sdist_file = package.get("sdist_file")
        rctx.file(paths.join(pin, "BUILD.bazel"), _pin_build(pin, pin_target, package, sdist_file))

    # 5. _wheel/ and _sdist/ directories for versioned artifact access
    wheel_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    sdist_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    for pkg_key in sorted(packages.keys()):
        pkg_name = pkg_key.split("@")[0]
        pkg_version = pkg_key.split("@")[1]

        # Normalize name
        norm_name = pkg_name.replace("_", "-").replace(".", "-").lower()
        for _i in range(len(norm_name)):
            if "--" in norm_name:
                norm_name = norm_name.replace("--", "-")
            else:
                break

        # Versioned alias: _wheel:name@version -> //name/vN:whl
        wheel_lines.extend([
            "alias(",
            '    name = "{}@{}",'.format(norm_name, pkg_version),
            '    actual = "//{}/v{}:whl",'.format(norm_name, pkg_version),
            ")",
            "",
        ])

        sdist_file = packages[pkg_key].get("sdist_file")
        if sdist_file:
            sdist_lines.extend([
                "alias(",
                '    name = "{}@{}",'.format(norm_name, pkg_version),
                '    actual = "//{}/v{}:sdist",'.format(norm_name, pkg_version),
                ")",
                "",
            ])

    # Unversioned pin aliases: _wheel:name -> //name:whl
    for pin in sorted(pins.keys()):
        wheel_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin),
            '    actual = "//{}:whl",'.format(pin),
            ")",
            "",
        ])

        pin_target = pins[pin]
        sdist_file = packages[pin_target].get("sdist_file")
        if sdist_file:
            sdist_lines.extend([
                "alias(",
                '    name = "{}",'.format(pin),
                '    actual = "//{}:sdist",'.format(pin),
                ")",
                "",
            ])

    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_lines) + "\n")
    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_lines) + "\n")

    # 6. Write _backend/ directory
    #
    # _backend/BUILD.bazel       — package root
    # _backend/<backend>.bzl     — symbolic macros wrapping backend rules with
    #                              tool defaults pre-filled from this lock repo

    # Build a set of PEP 503 normalized package names present in the lockfile.
    normalized_locked_package_names = {}
    for pkg_key in packages.keys():
        pkg_name = pkg_key.split("@")[0]
        norm_pkg = pkg_name.replace("_", "-").replace(".", "-").lower()
        for _i in range(len(norm_pkg)):
            if "--" in norm_pkg:
                norm_pkg = norm_pkg.replace("--", "-")
            else:
                break
        normalized_locked_package_names[norm_pkg] = True

    rctx.file("_backend/BUILD.bazel", 'package(default_visibility = ["//visibility:public"])\n')

    # Decode backend configs from the JSON-encoded attr.
    backend_configs = {}
    for name, config_json in rctx.attr.backend_configs.items():
        backend_configs[name] = json.decode(config_json)

    for macro_name, config in backend_configs.items():
        rule_bzl = config["rule_bzl"]

        # Resolve tool package names to lock-repo labels, keeping only
        # packages that actually exist in the lockfile.
        tool_deps_labels = []
        for pkg in config["tool_packages"]:
            norm_pkg = pkg.replace("_", "-").replace(".", "-").lower()
            for _i in range(len(norm_pkg)):
                if "--" in norm_pkg:
                    norm_pkg = norm_pkg.replace("--", "-")
                else:
                    break

            # Need to check locked_package_names. Wait, locked_package_names contains the names exactly as they are in pkg_key.
            # So let's build normalized locked names.
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
            doc = "Generate _wheel/ and _sdist/ directories with legacy versioned aliases.",
        ),
    },
)
