"""A pure-Starlark hub repository rule that wraps a pycross lock structure.

The file structure is as follows:
- REPO.bazel            - The repository root marker.
- BUILD.bazel           - The root build file.
- defs.bzl              - A defs file that provides an `install_deps` macro in some contexts. May be empty.
- requirements.bzl      - A defs file that provides the traditional `requirement` and `all_requirements`.
- _lock/BUILD.bazel     - Contains pure-Starlark instantiations of all package targets.
- _sdist/BUILD.bazel    - Version-aware aliases to package sdist targets.
- _wheel/BUILD.bazel    - Version-aware aliases to package wheel targets.
- <package>/BUILD.bazel - Contains aliases to targets under //_lock. Most notably, an alias named <package>
                          is what most people will want to import.

From a target perspective:
- //:package               - The pycross_wheel_library target.
- //package:sdist          - The package's sdist file.
- //package:wheel          - The package's wheel file.
- //_sdist:package@version - The sdist for a specific version of package.
- //_wheel:package@version - The wheel for a specific version of package.

The idea is that, for a repo named "pypi", something will depend on e.g. `@pypi//:numpy` or `@pypi//:pandas`.

The package names in the root of the repo are all normalized per
https://packaging.python.org/en/latest/specifications/name-normalization.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":util.bzl", "sanitize_name")

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
    lines.extend([
        "",
        "# All wheel requirements",
        "all_whl_requirements = [",
    ])
    for pin in sorted(pins.keys()):
        lines.append('    "@@{repo_name}//_wheel:{pin}",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")

    return "\n".join(lines) + "\n"

def _pin_build(pkg_sanitized, sdist_label = None):
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        "alias(",
        '    name = "wheel",',
        '    actual = "//_lock:{}_raw_wheel",'.format(pkg_sanitized),
        ")",
        "",
    ]
    if sdist_label:
        lines.extend([
            "alias(",
            '    name = "sdist",',
            '    actual = "{}",'.format(sdist_label),
            ")",
            "",
        ])
    return "\n".join(lines) + "\n"

def _package_repo_impl(rctx):
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock = json.decode(rctx.read(lock_json_path))
    packages = lock["packages"]
    pins = lock["pins"]
    environments = lock.get("environments", {})

    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")  # Empty file for compatibility
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

    # 1. Write _lock/BUILD.bazel containing all the target definitions.
    lock_build_lines = [
        'load("@rules_pycross//pycross:defs.bzl", "pycross_wheel_library")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    for pkg_key, pkg in sorted(packages.items()):
        pkg_name = pkg_key.split("@")[0]
        pkg_sanitized = sanitize_name(pkg_name)
        sdist_file = pkg.get("sdist_file")
        sdist_file_key = sdist_file["key"] if sdist_file else None

        select_cases = {}
        raw_wheel_select_cases = {}

        # Loop through each environment
        for env_name, env_file_ref in sorted(pkg.get("environment_files", {}).items()):
            env_info = environments[env_name]
            config_setting = env_info["config_setting_label"]

            file_key = env_file_ref.get("key")

            # If the package resolves to an sdist in this environment
            if sdist_file_key and file_key == sdist_file_key:
                # It's a source build! Point to the sdist repo target, or the user's custom build target.
                build_target = pkg.get("build_target")
                if build_target:
                    sdist_repo_target = build_target
                else:
                    sdist_repo_target = "@@{}_sdist_{}_{}//:pkg".format(
                        rctx.name,
                        sanitize_name(pkg_key),
                        sanitize_name(env_name),
                    )
                target_name = "_{}_sdist_{}".format(pkg_sanitized, sanitize_name(env_name))
                lock_build_lines.extend([
                    "alias(",
                    '    name = "{}",'.format(target_name),
                    '    actual = "{}",'.format(sdist_repo_target),
                    ")",
                    "",
                ])
                select_cases[config_setting] = ":" + target_name

                parts = sdist_repo_target.rsplit(":", 1)
                if len(parts) == 2:
                    sdist_repo_target_wheel = parts[0] + ":wheel"
                else:
                    sdist_repo_target_wheel = sdist_repo_target + ":wheel"
                raw_wheel_select_cases[config_setting] = sdist_repo_target_wheel

            else:
                # It's a pre-built wheel! Define a pycross_wheel_library target.
                wheel_label = env_file_ref.get("label")
                if not wheel_label:
                    if not file_key:
                        fail("Environment file reference has neither label nor key")
                    wheel_label = rctx.attr.repo_map.get(file_key)
                    if not wheel_label:
                        fail("Missing repo map entry for file key: " + file_key)

                # Collect runtime dependencies for this environment
                deps = []
                for dep in pkg.get("common_dependencies", []):
                    dep_name = dep.split("@")[0]
                    deps.append(":{}".format(sanitize_name(dep_name)))
                for dep in pkg.get("environment_dependencies", {}).get(env_name, []):
                    dep_name = dep.split("@")[0]
                    deps.append(":{}".format(sanitize_name(dep_name)))

                target_name = "_{}_wheel_{}".format(pkg_sanitized, sanitize_name(env_name))
                lock_build_lines.extend([
                    "pycross_wheel_library(",
                    '    name = "{}",'.format(target_name),
                    '    wheel = "{}",'.format(wheel_label),
                    "    deps = {},".format(deps),
                    ")",
                    "",
                ])
                select_cases[config_setting] = ":" + target_name
                raw_wheel_select_cases[config_setting] = wheel_label

        # Write the main package select alias
        select_dict_lines = []
        for cfg, target in sorted(select_cases.items()):
            select_dict_lines.append('        "{}": "{}",'.format(cfg, target))

        lock_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pkg_sanitized),
            "    actual = select({",
            "\n".join(select_dict_lines),
            "    }),",
            ")",
            "",
        ])

        # Write the raw wheel select alias
        raw_wheel_select_dict_lines = []
        for cfg, target in sorted(raw_wheel_select_cases.items()):
            raw_wheel_select_dict_lines.append('        "{}": "{}",'.format(cfg, target))

        lock_build_lines.extend([
            "alias(",
            '    name = "{}_raw_wheel",'.format(pkg_sanitized),
            "    actual = select({",
            "\n".join(raw_wheel_select_dict_lines),
            "    }),",
            ")",
            "",
        ])

    rctx.file("_lock/BUILD.bazel", "\n".join(lock_build_lines))

    # 2. Write the root BUILD.bazel with the user-facing pin aliases.
    root_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl", "requirements.bzl"])',
        "",
    ]

    for pin_name, pin_target in sorted(pins.items()):
        root_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(sanitize_name(pin_name)),
            '    actual = "//_lock:{}",'.format(sanitize_name(pin_target.split("@")[0])),
            ")",
            "",
        ])

    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # 3. Write helper _sdist and _wheel directories for compatibility/clean aliases
    sdist_build_lines = ['package(default_visibility = ["//visibility:public"])', ""]
    wheel_build_lines = ['package(default_visibility = ["//visibility:public"])', ""]

    for pkg_key, pkg in sorted(packages.items()):
        pkg_name = pkg_key.split("@")[0]
        pkg_sanitized = sanitize_name(pkg_name)

        sdist_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pkg_sanitized),
            '    actual = "//_lock:{}",'.format(pkg_sanitized),
        ])

        # If it has an sdist, we can also alias it
        if pkg.get("sdist_file"):
            sdist_build_lines.append(")")
        else:
            sdist_build_lines.append("    # no sdist available")
            sdist_build_lines.append(")")
        sdist_build_lines.append("")

        wheel_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pkg_sanitized),
            '    actual = "//_lock:{}",'.format(pkg_sanitized),
            ")",
            "",
        ])

    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_build_lines))
    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_build_lines))

    # 4. Write package BUILD subdirectories containing aliases for wheel/sdist
    for pin, pin_target in sorted(pins.items()):
        package = lock["packages"][pin_target]
        sdist_file = package.get("sdist_file")
        sdist_label = None
        if sdist_file:
            sdist_label = rctx.attr.repo_map.get(sdist_file["key"])
        rctx.file(paths.join(pin, "BUILD.bazel"), _pin_build(sanitize_name(pin), sdist_label))

    # 5. Write _builtins/BUILD.bazel
    _STANDARD_TOOLS = ["meson", "ninja", "setuptools", "wheel", "meson-python", "scikit-build-core"]
    builtins_build_lines = [
        'load("@rules_pycross//pycross/private/build:missing_dependency.bzl", "pycross_missing_dependency")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    # Get a dict of all sanitized package names
    locked_sanitized_names = {}
    for pkg_key in packages.keys():
        pkg_name = pkg_key.split("@")[0]
        locked_sanitized_names[sanitize_name(pkg_name)] = True

    for tool in _STANDARD_TOOLS:
        sanitized_tool = sanitize_name(tool)
        if sanitized_tool in locked_sanitized_names:
            builtins_build_lines.extend([
                "alias(",
                '    name = "{}",'.format(tool),
                '    actual = "//:{}",'.format(sanitized_tool),
                ")",
                "",
            ])
        else:
            builtins_build_lines.extend([
                "pycross_missing_dependency(",
                '    name = "{}",'.format(tool),
                '    tool_name = "{}",'.format(tool),
                '    lock_repo = "@{}",'.format(rctx.name),
                ")",
                "",
            ])

    rctx.file("_builtins/BUILD.bazel", "\n".join(builtins_build_lines))

package_repo = repository_rule(
    implementation = _package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "repo_map": attr.string_dict(),
        "write_install_deps": attr.bool(),
    },
)
