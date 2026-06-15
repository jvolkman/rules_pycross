"""A simple universe repo that stores a list of resolved lock files and universe memberships."""

_root_build = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "locks.bzl",
    "universes.bzl",
])
"""

def _lock_universe_repo_impl(rctx):
    bzl_lines = ["locks = {"]
    for repo_name in sorted(rctx.attr.repo_files):
        repo_file = rctx.attr.repo_files[repo_name]
        bzl_lines.append('    "{}": Label("{}"),'.format(repo_name, repo_file))
    bzl_lines.append("}")

    universe_lines = ["universe_memberships = {"]
    for repo_name in sorted(rctx.attr.universe_memberships):
        universe_name = rctx.attr.universe_memberships[repo_name]
        universe_lines.append('    "{}": "{}",'.format(repo_name, universe_name))
    universe_lines.append("}")

    rctx.file("locks.bzl", "\n".join(bzl_lines) + "\n")
    rctx.file("universes.bzl", "\n".join(universe_lines) + "\n")
    rctx.file("BUILD.bazel", _root_build)

lock_universe_repo = repository_rule(
    implementation = _lock_universe_repo_impl,
    attrs = {
        "repo_files": attr.string_dict(),
        "universe_memberships": attr.string_dict(
            doc = "Maps repo_name to universe_name for repos that share a universe.",
            default = {},
        ),
    },
)
