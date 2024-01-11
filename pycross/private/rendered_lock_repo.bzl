"""An internal repo rule that wraps a pycross lock structure."""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "CREATE_REPOS_ATTRS", "handle_create_repos_attrs")

_defs_bzl = """\
load("//lock:lock.bzl", "repositories")

install_deps = repositories
"""

_lock_build = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "lock.bzl",
])
"""

_root_build = """\
package(default_visibility = ["//visibility:public"])

load("//lock:lock.bzl", "targets")

targets()

exports_files([
    "defs.bzl",
])
"""

def _generate_lock_bzl(rctx, lock_json_path, lock_bzl_path):
    args = [
        "--pycross-repo-name",
        "@rules_pycross",
        "--build-prefix",
        "_build",
        "--environment-prefix",
        "_env",
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

def _rendered_lock_repo_impl(rctx):
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock_bzl_path = rctx.path("lock/lock.bzl")

    rctx.file("lock/BUILD.bazel", _lock_build)
    rctx.file("BUILD.bazel", _root_build)
    rctx.file("defs.bzl", _defs_bzl)

    _generate_lock_bzl(rctx, lock_json_path, lock_bzl_path)

rendered_lock_repo = repository_rule(
    implementation = _rendered_lock_repo_impl,
    attrs = dict(
        resolved_lock_file = attr.label(mandatory = True),
        repo_map = attr.string_dict(),
    ) | CREATE_REPOS_ATTRS,
)
