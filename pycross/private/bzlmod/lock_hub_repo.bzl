"""A simple hub repo that stores a list of resolved lock files and hub memberships."""

_root_build = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "locks.bzl",
    "hubs.bzl",
])
"""

def _lock_hub_repo_impl(rctx):
    bzl_lines = ["locks = {"]
    for repo_name in sorted(rctx.attr.repo_files):
        repo_file = rctx.attr.repo_files[repo_name]
        bzl_lines.append('    "{}": Label("{}"),'.format(repo_name, repo_file))
    bzl_lines.append("}")

    hub_lines = ["hub_memberships = {"]
    for repo_name in sorted(rctx.attr.hub_memberships):
        hub_name = rctx.attr.hub_memberships[repo_name]
        hub_lines.append('    "{}": "{}",'.format(repo_name, hub_name))
    hub_lines.append("}")

    rctx.file("locks.bzl", "\n".join(bzl_lines) + "\n")
    rctx.file("hubs.bzl", "\n".join(hub_lines) + "\n")
    rctx.file("BUILD.bazel", _root_build)

lock_hub_repo = repository_rule(
    implementation = _lock_hub_repo_impl,
    attrs = {
        "repo_files": attr.string_dict(),
        "hub_memberships": attr.string_dict(
            doc = "Maps repo_name to hub_name for repos that share a hub.",
            default = {},
        ),
    },
)
