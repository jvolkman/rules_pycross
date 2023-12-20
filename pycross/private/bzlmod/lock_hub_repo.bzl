"""A simple hub repo that stores a list of resolved lock files."""

_root_build = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "locks.bzl",
])
"""

def _lock_hub_repo_impl(rctx):
    bzl_lines = ["locks = {"]
    for repo_name in sorted(rctx.attr.repo_files):
        repo_file = rctx.attr.repo_files[repo_name]
        bzl_lines.append('    "{}": Label("{}"),'.format(repo_name, repo_file))
    bzl_lines.append("}")

    rctx.file("locks.bzl", "\n".join(bzl_lines) + "\n")
    rctx.file("BUILD.bazel", _root_build)

lock_hub_repo = repository_rule(
    implementation = _lock_hub_repo_impl,
    attrs = {
        "repo_files": attr.string_dict(),
    },
)
