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
load(":resolved_lock_renderer.bzl", "render_lock_bzl")

def _label_to_workspace_path(label_str):
    if not label_str:
        return None
    if label_str.startswith("@@//"):
        label_str = label_str[4:]
    elif label_str.startswith("@//"):
        label_str = label_str[3:]
    elif label_str.startswith("//"):
        label_str = label_str[2:]
    elif label_str.startswith("@"):
        # External repo label, we can't write to it.
        return None
    if label_str.startswith(":"):
        return label_str[1:]
    return label_str.replace(":", "/")

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

def _pin_build(pkg_key, sdist_label = None):
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        "alias(",
        '    name = "wheel",',
        '    actual = "//_lock:_wheel_{}",'.format(pkg_key),
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

    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")  # Empty file for compatibility
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

    # 1. Render the lock.bzl file
    rctx.file("_lock/lock.bzl", render_lock_bzl(lock, rctx.attr.repo_map, rctx.name))

    # 1b. Write _lock/BUILD.bazel that calls the generated targets macro
    lock_build = [
        'package(default_visibility = ["//:__subpackages__"])',
        "",
        'load(":lock.bzl", "targets")',
        "",
        "targets()",
        "",
    ]
    rctx.file("_lock/BUILD.bazel", "\n".join(lock_build))

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
            '    name = "{}",'.format(pin_name),
            '    actual = "//_lock:{}",'.format(pin_target),
            ")",
            "",
        ])

    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # 3. Write helper _sdist and _wheel directories for compatibility/clean aliases
    sdist_build_lines = ['package(default_visibility = ["//visibility:public"])', ""]
    wheel_build_lines = ['package(default_visibility = ["//visibility:public"])', ""]

    for pkg_key, pkg in sorted(packages.items()):
        sdist_file = pkg.get("sdist_file")
        if sdist_file:
            sdist_build_lines.extend([
                "alias(",
                '    name = "{}",'.format(pkg_key),
                '    actual = "//_lock:_sdist_{}",'.format(pkg_key),
                ")",
                "",
            ])

        wheel_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pkg_key),
            '    actual = "//_lock:_wheel_{}",'.format(pkg_key),
            ")",
            "",
        ])

    rctx.file("_sdist/BUILD.bazel", "\n".join(sdist_build_lines))

    for pin_name, pin_target in sorted(pins.items()):
        if pin_name != pin_target:
            wheel_build_lines.extend([
                "alias(",
                '    name = "{}",'.format(pin_name),
                '    actual = ":{}",'.format(pin_target),
                ")",
                "",
            ])

    rctx.file("_wheel/BUILD.bazel", "\n".join(wheel_build_lines))

    # 3c. Write _cargo_lock/BUILD.bazel
    # TODO: This section hardcodes "maturin_build" knowledge into the hub repo.
    # Ideally, backends would register their own helper target generators, but
    # _cargo_lock is inherently a Rust/maturin concept and the practical benefit
    # of generalizing this is low.
    cargo_lock_build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'load("@rules_pycross//pycross:defs.bzl", "pycross_generate_cargo_lock")',
        "",
    ]

    has_cargo_lock_targets = False
    for pkg_key, pkg in sorted(packages.items()):
        if pkg.get("build_backend") != "maturin_build":
            continue
        sdist_file = pkg.get("sdist_file")
        if not sdist_file:
            continue

        has_cargo_lock_targets = True
        cargo_lock_json = pkg.get("backend_attrs", {}).get("cargo_lock")
        cargo_lock_val = json.decode(cargo_lock_json) if cargo_lock_json else None
        output_path = _label_to_workspace_path(cargo_lock_val)

        cargo_lock_build_lines.extend([
            "pycross_generate_cargo_lock(",
            '    name = "{}",'.format(pkg_key),
            '    sdist = "//_sdist:{}",'.format(pkg_key),
        ])
        if output_path:
            cargo_lock_build_lines.append('    output = "{}",'.format(output_path))
        cargo_lock_build_lines.extend([
            ")",
            "",
        ])

    if has_cargo_lock_targets:
        rctx.file("_cargo_lock/BUILD.bazel", "\n".join(cargo_lock_build_lines))

    # 4. Write package BUILD subdirectories containing aliases for wheel/sdist
    for pin, pin_target in sorted(pins.items()):
        package = lock["packages"][pin_target]
        sdist_file = package.get("sdist_file")
        actual_sdist = "//_lock:_sdist_{}".format(pin_target) if sdist_file else None
        rctx.file(paths.join(pin, "BUILD.bazel"), _pin_build(pin_target, actual_sdist))

    # 5. Write _backend/ directory
    #
    # _backend/BUILD.bazel       — package root
    # _backend/<backend>.bzl     — symbolic macros wrapping backend rules with
    #                              tool defaults pre-filled from this lock repo

    # Build a set of PEP 503 normalized package names present in the lockfile.
    locked_package_names = {}
    for pkg_key in packages.keys():
        pkg_name = pkg_key.split("@")[0]
        locked_package_names[pkg_name] = True

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
            if pkg in locked_package_names:
                tool_deps_labels.append("//:{}".format(pkg))

        lines = [
            '"""Backend macro with pre-configured tool defaults for this lock repo."""',
            "",
            'load("{rule_bzl}", _{macro_name} = "{macro_name}")'.format(
                rule_bzl = rule_bzl,
                macro_name = macro_name,
            ),
            "",
            "def _impl(name, visibility, **kwargs):",
            "    _{macro_name}(name = name, visibility = visibility, **kwargs)".format(macro_name = macro_name),
            "",
        ]

        if tool_deps_labels:
            attr_lines = ["        \"tool_deps\": attr.label_list(default = ["]
            for label in tool_deps_labels:
                attr_lines.append("            Label(\"{}\"),".format(label))
            attr_lines.append("        ]),")

            lines.extend([
                "{macro_name} = macro(".format(macro_name = macro_name),
                "    implementation = _impl,",
                "    inherit_attrs = _{macro_name},".format(macro_name = macro_name),
                "    attrs = {",
            ] + attr_lines + [
                "    },",
                ")",
                "",
            ])
        else:
            lines.extend([
                "{macro_name} = macro(".format(macro_name = macro_name),
                "    implementation = _impl,",
                "    inherit_attrs = _{macro_name},".format(macro_name = macro_name),
                ")",
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
    },
)
