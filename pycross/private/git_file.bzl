"""A repository rule to fetch a git repository and create a tar.gz archive."""

load(":internal_repo.bzl", "exec_internal_tool")

def parse_git_url(url):
    """Splits a lock file git URL into its remote, commit and options.

    Args:
      url: a URL like `git+https://host/repo?lfs=true&rev=main#<commit>`. The
        `git+` prefix and the query are optional; the commit is required.

    Returns:
      A struct with `remote`, `commit` and `lfs` fields.
    """
    if url.startswith("git+"):
        url = url[4:]
    if "#" not in url:
        fail("Git URL must contain a commit hash in the fragment: " + url)
    url, commit = url.rsplit("#", 1)
    if not commit:
        fail("Git URL must contain a commit hash in the fragment: " + url)

    lfs = False
    if "?" in url:
        url, query = url.split("?", 1)
        for param in query.split("&"):
            if param == "lfs=true":
                lfs = True
    return struct(remote = url, commit = commit, lfs = lfs)

# Leave LFS pointers alone unless the lock asks for LFS objects, whether or
# not the host has git-lfs configured (uv does the same). Clearing the filter
# also keeps git from starting `git-lfs filter-process` at all; `-c` options
# carry over to the git processes that submodule commands start.
_NO_LFS_FILTER = ["-c", "filter.lfs.smudge=", "-c", "filter.lfs.process=", "-c", "filter.lfs.required=false"]

def _git(rctx, git_path, args, error = None, skip_smudge = True):
    """Runs git in the checkout; fails with `error` if set and git fails."""
    res = rctx.execute(
        [git_path, "-C", "checkout"] + (_NO_LFS_FILTER if skip_smudge else []) + args,
        environment = {"GIT_LFS_SKIP_SMUDGE": "1" if skip_smudge else "0"},
        quiet = True,
    )
    if error and res.return_code != 0:
        fail("{}: {}{}".format(error, res.stdout, res.stderr))
    return res

def _pycross_git_file_impl(rctx):
    git_path = rctx.which("git")
    if not git_path:
        fail("git executable not found in PATH")

    src = parse_git_url(rctx.attr.url)

    if src.lfs and rctx.execute([git_path, "lfs", "version"], quiet = True).return_code != 0:
        fail("{} sets lfs = true, but `git lfs` is not available. Install git-lfs to fetch this package.".format(src.remote))

    res = rctx.execute([git_path, "init", "-q", "checkout"], quiet = True)
    if res.return_code != 0:
        fail("Failed to initialize git repository: " + res.stderr)

    # Relative submodule URLs resolve against the origin remote.
    _git(rctx, git_path, ["remote", "add", "origin", src.remote], "Failed to add git remote")

    # Fetch only the locked commit. Servers that refuse requests for
    # unadvertised commits (protocol v0 without allowReachableSHA1InWant)
    # get a full fetch instead.
    if _git(rctx, git_path, ["fetch", "-q", "--depth", "1", "origin", src.commit]).return_code != 0:
        _git(
            rctx,
            git_path,
            ["fetch", "-q", "--tags", "origin", "+refs/heads/*:refs/remotes/origin/*"],
            "Failed to fetch " + src.remote,
        )
    _git(rctx, git_path, ["-c", "advice.detachedHead=false", "checkout", "-q", src.commit], "Failed to checkout commit " + src.commit)

    if rctx.path("checkout/.gitmodules").exists:
        submodule_update = ["submodule", "update", "-q", "--init", "--recursive"]
        if _git(rctx, git_path, submodule_update + ["--depth", "1"]).return_code != 0:
            # Retry from scratch with full clones, for servers that refuse
            # requests for commits that aren't advertised branch tips.
            _git(rctx, git_path, ["submodule", "deinit", "-q", "--all", "--force"])
            rctx.delete("checkout/.git/modules")
            _git(rctx, git_path, submodule_update, "Failed to update git submodules")

    if src.lfs:
        # `git lfs pull` only checks out objects in repos with LFS installed.
        _git(rctx, git_path, ["lfs", "install", "--local"], "Failed to set up Git LFS")
        _git(rctx, git_path, ["lfs", "pull"], "Failed to fetch Git LFS objects", skip_smudge = False)
        _git(
            rctx,
            git_path,
            ["submodule", "foreach", "-q", "--recursive", "git lfs install --local && git lfs pull"],
            "Failed to fetch Git LFS objects for submodules",
            skip_smudge = False,
        )

    # Record the commit time as every entry's mtime, as `git archive` does.
    mtime = _git(rctx, git_path, ["log", "-1", "--format=%ct", "HEAD"], "Failed to read commit time").stdout.strip()

    # Archive into the file/ subdirectory.
    filename = rctx.attr.filename
    rctx.file("file/BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])
exports_files(["{filename}"])
""".format(filename = filename))

    exec_internal_tool(
        rctx,
        Label("//pycross/private/tools:git_archive.py"),
        [
            "--source",
            str(rctx.path("checkout")),
            "--output",
            str(rctx.path("file/" + filename)),
            "--prefix",
            "repo",
            "--mtime",
            mtime,
        ],
    )

    # Clean up the git clone.
    rctx.delete("checkout")

pycross_git_file = repository_rule(
    implementation = _pycross_git_file_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "filename": attr.string(mandatory = True),
    },
)
