"""An internal repo rule that wraps a pycross lock structure.

The file structure is as follows:
- WORKSPACE.bazel       - The workspace root marker.
- BUILD.bazel           - The root build file.
- defs.bzl              - A defs file that provides an `install_deps` macro in some contexts. May be empty.
- _pkg/BUILD.bazel      - Contains instantiations of all of the definitions in `lock.bzl`.
- _pkg/lock.bzl         - The rendered lock file. This is where most of the "meat" is.
- <package>/BUILD.bazel - Contains aliases to targets under //_pkg. Most notably, an alias named <package>
                          is what most people will want to import.

From a target perspective:
- //:package            - The pycross_wheel_library target.
- //package:lib         - Same as above.
- //package:wheel       - The package's wheel file.

The idea is that, for a repo named "pypi", something will depend on e.g. `@pypi//:numpy` or `@pypi//:pandas`.

The package names in the root of the repo are all normalized per
https://packaging.python.org/en/latest/specifications/name-normalization.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "CREATE_REPOS_ATTRS", "handle_create_repos_attrs")

_install_deps_bzl = """\
load("//_pkg:lock.bzl", _install_deps = "repositories")

install_deps = _install_deps
"""

_workspace = """\
# DO NOT EDIT: automatically generated WORKSPACE file for package_repo rule
workspace(name = "{repo_name}")
"""

_pkg_build = """\
package(default_visibility = ["//:__subpackages__"])

load("//_pkg:lock.bzl", "targets")

targets()
"""

_pin_tmpl = """\
package(default_visibility = ["//visibility:public"])

alias(
    name = "lib",
    actual = "//_pkg:{package_key}",
)

alias(
    name = "wheel",
    actual = "//_pkg:_wheel_{package_key}",
)
"""

def _root_build(pins):
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl"])',
        "",
    ]

    for pin_name, pin_target in pins.items():
        lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = "//_pkg:{}",'.format(pin_target),
            ")",
            "",
        ])

    return "\n".join(lines)

def _generate_lock_bzl(rctx, lock_json_path, lock_bzl_path):
    args = [
        "--pycross-repo-name",
        "@rules_pycross",
        "--no-pins",
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
    lock_bzl_path = rctx.path("_pkg/lock.bzl")

    lock = json.decode(rctx.read(lock_json_path))

    rctx.file("_pkg/BUILD.bazel", _pkg_build)
    rctx.file("WORKSPACE.bazel", _workspace.format(repo_name = rctx.name))
    if rctx.attr.write_install_deps:
        rctx.file("defs.bzl", _install_deps_bzl)
    else:
        rctx.file("defs.bzl")  # Empty file

    _generate_lock_bzl(rctx, lock_json_path, lock_bzl_path)

    for pin, pin_target in lock["pins"].items():
        pin_content = _pin_tmpl.format(package_name = pin, package_key = pin_target)
        rctx.file(paths.join(pin, "BUILD.bazel"), pin_content)

    rctx.file("BUILD.bazel", _root_build(lock["pins"]))

package_repo = repository_rule(
    implementation = _package_repo_impl,
    attrs = dict(
        resolved_lock_file = attr.label(mandatory = True),
        repo_map = attr.string_dict(),
        write_install_deps = attr.bool(),
    ) | CREATE_REPOS_ATTRS,
)
