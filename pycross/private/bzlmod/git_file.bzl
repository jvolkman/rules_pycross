"""A repository rule to fetch a git repository and create a tar.gz archive."""

def _pycross_git_file_impl(rctx):
    url = rctx.attr.url
    if url.startswith("git+"):
        url = url[4:]

    # Remove the fragment (commit hash) from the URL
    if "#" in url:
        url, commit = url.rsplit("#", 1)
    else:
        fail("Git URL must contain a commit hash in the fragment: " + url)

    # Remove query string like ?rev=...
    if "?" in url:
        url, _ = url.split("?", 1)

    # Note: we clone into a temporary directory
    res = rctx.execute(["git", "clone", url, "checkout"], quiet = False)
    if res.return_code != 0:
        fail("Failed to clone git repository: " + res.stderr)

    # We must explicitly checkout the commit if it's not the default branch.
    res = rctx.execute(["git", "-C", "checkout", "checkout", commit], quiet = False)
    if res.return_code != 0:
        fail("Failed to checkout commit " + commit + ": " + res.stderr)

    # Archive
    filename = rctx.attr.filename
    rctx.execute(["mkdir", "-p", "file"])
    res = rctx.execute(["git", "-C", "checkout", "archive", "--format=tar.gz", "--prefix=repo/", "-o", "../file/" + filename, "HEAD"], quiet = False)
    if res.return_code != 0:
        fail("Failed to create archive: " + res.stderr)

    # Clean up
    rctx.execute(["rm", "-rf", "checkout"])

    # Create BUILD
    rctx.file("file/BUILD.bazel", """
package(default_visibility = ["//visibility:public"])
exports_files(["{filename}"])
""".format(filename = filename))

pycross_git_file = repository_rule(
    implementation = _pycross_git_file_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "filename": attr.string(mandatory = True),
    },
)
