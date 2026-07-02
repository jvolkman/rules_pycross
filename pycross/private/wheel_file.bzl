"""Repository rule that downloads a wheel and inspects it."""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:pypi_file.bzl", "get_pypi_file_url")

_BUILD_TEMPLATE = """\
load("@rules_pycross//pycross/private:wheel_library.bzl", "pycross_wheel_metadata")

package(default_visibility = ["//visibility:public"])

exports_files(["inspection.json"])

pycross_wheel_metadata(
    name = "wheel",
    wheel = "{filename}",
    package_name = "{package_name}",
    package_version = "{package_version}",
    site_paths = {site_paths},
)
"""

def _pycross_wheel_file_impl(rctx):
    netrc = read_user_netrc(rctx)

    urls = rctx.attr.urls
    if not urls:
        urls = [get_pypi_file_url(
            rctx,
            netrc,
            rctx.attr.index,
            rctx.attr.package_name,
            rctx.attr.package_version,
            rctx.attr.filename,
        )]

    # Download the wheel file directly
    rctx.download(
        urls,
        rctx.attr.filename,
        rctx.attr.sha256,
        auth = use_netrc(netrc, urls, {}),
    )

    # Inspect the wheel for site_paths
    result = exec_internal_tool(
        rctx,
        rctx.attr._inspect_tool,
        [
            "--wheel",
            rctx.attr.filename,
            "--output",
            "inspection.json",
        ],
        extra_wheels = [Label("@pycross_internal_deps//packaging:wheel")],
    )

    if result.return_code != 0:
        # Non-fatal: if inspection fails, write empty result
        # Note: exec_internal_tool will actually fail() if return_code != 0,
        # but if we somehow bypass it or change it, we write a fallback.
        rctx.file("inspection.json", json.encode({"site_paths": []}))
        site_paths = []
    else:
        inspection_data = json.decode(rctx.read("inspection.json"))
        site_paths = inspection_data.get("site_paths", [])

    rctx.file("BUILD.bazel", _BUILD_TEMPLATE.format(
        filename = rctx.attr.filename,
        package_name = rctx.attr.package_name or "",
        package_version = rctx.attr.package_version or "",
        site_paths = site_paths,
    ))

pycross_wheel_file = repository_rule(
    implementation = _pycross_wheel_file_impl,
    attrs = {
        "urls": attr.string_list(doc = "Direct download URLs. If empty, uses PyPI JSON API."),
        "sha256": attr.string(mandatory = True),
        "filename": attr.string(mandatory = True, doc = "The wheel filename."),
        "package_name": attr.string(doc = "PyPI package name (for JSON API mode)."),
        "package_version": attr.string(doc = "Package version (for JSON API mode)."),
        "index": attr.string(default = "https://pypi.org", doc = "PyPI index URL."),
        "_inspect_tool": attr.label(default = "//pycross/private/tools:inspect_package.py"),
    },
)
