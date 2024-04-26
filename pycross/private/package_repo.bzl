"""An internal repo rule that wraps a pycross lock structure.

The file structure is as follows:
- WORKSPACE.bazel       - The workspace root marker.
- BUILD.bazel           - The root build file.
- defs.bzl              - A defs file that provides an `install_deps` macro in some contexts. May be empty.
- requirements.bzl      - A defs file that provides the traditional `requirement` and `all_requirements`.
- _lock/BUILD.bazel     - Contains instantiations of all of the definitions in `lock.bzl`.
- _lock/lock.bzl        - The rendered lock file. This is where most of the "meat" is.
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
load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "CREATE_REPOS_ATTRS", "handle_create_repos_attrs")

_install_deps_bzl = """\
load("//_lock:lock.bzl", _install_deps = "repositories")

install_deps = _install_deps
"""

_workspace = """\
# DO NOT EDIT: automatically generated WORKSPACE file for package_repo rule
workspace(name = "{repo_name}")
"""

_lock_build = """\
package(default_visibility = ["//:__subpackages__"])

load("//_lock:lock.bzl", "targets")

targets()
"""

def _pin_build(package):
    package_key = package["key"]
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        "alias(",
        '    name = "wheel",',
        '    actual = "//_lock:_wheel_{}",'.format(package_key),
        ")",
        "",
    ]

    if package.get("sdist_file", {}).get("key"):
        lines.extend([
            "alias(",
            '    name = "sdist",',
            '    actual = "//_lock:_sdist_{}",'.format(package_key),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

def _wheel_build(packages):
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    for pkg in packages:
        package_key = pkg["key"]
        lines.extend([
            "alias(",
            '    name = "{}",'.format(package_key),
            '    actual = "//_lock:_wheel_{}",'.format(package_key),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

def _sdist_build(packages):
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    for pkg in packages:
        package_key = pkg["key"]
        lines.extend([
            "alias(",
            '    name = "{}",'.format(package_key),
            '    actual = "//_lock:_sdist_{}",'.format(package_key),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

def _root_build(pins):
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl", "requirements.bzl"])',
        "",
    ]

    for pin_name, pin_target in pins.items():
        lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = "//_lock:{}",'.format(pin_target),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

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
    for pin in pins:
        lines.append('    "@@{repo_name}//:{pin}",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")
    lines.extend([
        "",
        "# All wheel requirements",
        "all_whl_requirements = [",
    ])
    for pin in pins.values():
        lines.append('    "@@{repo_name}//_wheel:{pin}",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")

    return "\n".join(lines) + "\n"

def _generate_lock_bzl(rctx, lock_json_path, lock_bzl_path):
    args = [
        "--pycross-repo-name",
        "@rules_pycross",
        "--no-pins",
        "--repo-prefix",
        rctx.attr.name.lower().replace("-", "_"),
        "--resolved-lock",
        lock_json_path,
        "--output",
        lock_bzl_path,
    ] + handle_create_repos_attrs(rctx.attr)

    for file_key, label in rctx.attr.repo_map.items():
        args.extend(["--repo", file_key, label])

    exec_internal_tool(
        rctx,
        Label("//pycross/private/tools:resolved_lock_renderer.py"),
        args,
    )

def _package_repo_impl(rctx):
    # To ensure that none of the extra files and directories in the root conflict with actual packages, they all
    # either contain a period or start with an underscore. This works because Python package names cannot start
    # with `_`, and any periods in the name would be replaced with `-` during name normalization. Theoretically
    # https://pypi.org/project/workspace/ would conflict with the repo's WORKSPACE file on a case-insensitive
    # filesystem, so we instead write WORKSPACE.bazel. A package named `WORKSPACE.bazel` would be normalized to
    # `workspace-bazel`.

    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock_bzl_path = rctx.path("_lock/lock.bzl")

    lock = json.decode(rctx.read(lock_json_path))
    packages = lock["packages"].values()

    rctx.file("WORKSPACE.bazel", _workspace.format(repo_name = rctx.name))
    rctx.file("_lock/BUILD.bazel", _lock_build)
    rctx.file("_sdist/BUILD.bazel", _sdist_build(packages))
    rctx.file("_wheel/BUILD.bazel", _wheel_build(packages))

    if rctx.attr.write_install_deps:
        rctx.file("defs.bzl", _install_deps_bzl)
    else:
        rctx.file("defs.bzl")  # Empty file

    rctx.file("requirements.bzl", _requirements_bzl(rctx, lock["pins"]))

    _generate_lock_bzl(rctx, lock_json_path, lock_bzl_path)

    for pin, pin_target in lock["pins"].items():
        package = lock["packages"][pin_target]
        rctx.file(paths.join(pin, "BUILD.bazel"), _pin_build(package))

    rctx.file("BUILD.bazel", _root_build(lock["pins"]))

package_repo = repository_rule(
    implementation = _package_repo_impl,
    attrs = dict(
        resolved_lock_file = attr.label(mandatory = True),
        repo_map = attr.string_dict(),
        write_install_deps = attr.bool(),
    ) | CREATE_REPOS_ATTRS,
)
