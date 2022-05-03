load("@bazel_tools//tools/build_defs/repo:utils.bzl", "update_attrs")

_PYPI_FILE_BUILD = """\
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

def _pypi_file_impl(ctx):
    """Implementation of the pypi_file rule."""

    index_url = ctx.attr.index
    if not index_url.endswith("/"):
        index_url = index_url + "/"

    index_url += "pypi/{}/{}/json".format(
        ctx.attr.package_name,
        ctx.attr.package_version,
    )

    ctx.download(
        index_url,
        "pypi_metadata.json",
    )
    metadata = json.decode(ctx.read("pypi_metadata.json"))

    if not ctx.attr.keep_metadata:
        ctx.delete("pypi_metadata.json")

    if ctx.attr.package_version not in metadata["releases"]:
        fail(
            "Version {} of package {} does not exist in index {}".format(
                ctx.attr.package_version,
                ctx.attr.package_name,
                ctx.attr.index,
            )
        )

    release_files = metadata["releases"][ctx.attr.package_version]
    url = None
    for release_file in release_files:
        if release_file["filename"] == ctx.attr.filename:
            url = release_file["url"]
            break

    if not url:
        fail(
            "File {} does not exist for version {} of package {} in index {}".format(
                ctx.attr.filename,
                ctx.attr.package_version,
                ctx.attr.package_name,
                ctx.attr.index,
            )
        )

    download_info = ctx.download(
        url,
        "file/" + ctx.attr.filename,
        ctx.attr.sha256,
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
