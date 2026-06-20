"""Rule to download files from pypi."""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "update_attrs", "use_netrc")

_PYPI_FILE_BUILD = """\
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

def get_pypi_file_url(rctx, netrc, index_url, package_name, package_version, filename, keep_metadata = False):
    """Fetches package metadata from the PyPI JSON API and resolves the URL for the specified file.

    Args:
        rctx: The repository context.
        netrc: The parsed netrc file.
        index_url: The URL of the PyPI index.
        package_name: The name of the package.
        package_version: The version of the package.
        filename: The filename to download.
        keep_metadata: Whether to keep the downloaded metadata.

    Returns:
        The URL to the file.
    """
    index_url = index_url.rstrip("/")
    api_url = "{}/pypi/{}/{}/json".format(
        index_url,
        package_name,
        package_version,
    )

    rctx.download(
        api_url,
        "pypi_metadata.json",
        auth = use_netrc(netrc, [api_url], {}),
    )
    metadata = json.decode(rctx.read("pypi_metadata.json"))

    if not keep_metadata:
        rctx.delete("pypi_metadata.json")

    release_files = metadata.get("urls", [])
    url = None
    for release_file in release_files:
        if release_file["filename"] == filename:
            url = release_file["url"]
            break

    if not url:
        fail(
            "File {} does not exist for version {} of package {} in index {}".format(
                filename,
                package_version,
                package_name,
                index_url,
            ),
        )

    # Resolve relative URLs. These relative paths return by JSON API are the same as
    # those returned by HTML index paths. So they are relative to the simple index path,
    # not the JSON API path.
    if not url.startswith("http://") and not url.startswith("https://"):
        simple_base = index_url + "/simple/" + package_name
        base_parts = simple_base.split("/")
        for part in url.split("/"):
            if part == "..":
                base_parts = base_parts[:-1]
            elif part != ".":
                base_parts.append(part)
        url = "/".join(base_parts)

    return url

def _pypi_file_impl(ctx):
    """Implementation of the pypi_file rule."""

    netrc = read_user_netrc(ctx)
    url = get_pypi_file_url(
        ctx,
        netrc,
        ctx.attr.index,
        ctx.attr.package_name,
        ctx.attr.package_version,
        ctx.attr.filename,
        keep_metadata = ctx.attr.keep_metadata,
    )

    download_info = ctx.download(
        url,
        "file/" + ctx.attr.filename,
        ctx.attr.sha256,
        auth = use_netrc(netrc, [url], {}),
    )
    ctx.file("file/BUILD.bazel", _PYPI_FILE_BUILD.format(ctx.attr.filename))

    return update_attrs(ctx.attr, _pypi_file_attrs.keys(), {"sha256": download_info.sha256})

_pypi_file_attrs = {
    "sha256": attr.string(
        doc = "The expected SHA-256 of the file downloaded.",
        mandatory = True,
    ),
    "index": attr.string(
        doc = "The base URL of the PyPI-compatible package index to use. Defaults to pypi.org.",
        default = "https://pypi.org",
    ),
    "package_name": attr.string(
        doc = "The package name.",
        mandatory = True,
    ),
    "package_version": attr.string(
        doc = "The package version.",
        mandatory = True,
    ),
    "filename": attr.string(
        doc = "The name of the file to download.",
        mandatory = True,
    ),
    "keep_metadata": attr.bool(
        doc = "Whether to store the pypi_metadata.json file for debugging.",
    ),
}

pypi_file = repository_rule(
    implementation = _pypi_file_impl,
    attrs = _pypi_file_attrs,
    doc = "Downloads a file from a PyPI-compatible package index.",
)
