"""Repository rule that downloads a wheel and inspects it."""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:pypi_file.bzl", "DEFAULT_INDEX", "get_pypi_file_url")

_BUILD_TEMPLATE = """\
load("@rules_pycross//pycross/private:wheel_library.bzl", "pycross_wheel_metadata")

package(default_visibility = ["//visibility:public"])

exports_files(["inspection.json"])

pycross_wheel_metadata(
    name = "wheel",
    wheel = "{filename}",
    site_paths = {site_paths},
    bin_paths = {bin_paths},
    data_paths = {data_paths},
    include_paths = {include_paths},
)
"""

def _render_wheel_file_build(filename, inspection_data):
    return _BUILD_TEMPLATE.format(
        filename = filename,
        site_paths = inspection_data.get("site_paths", []),
        bin_paths = inspection_data.get("bin_paths", []),
        data_paths = inspection_data.get("data_paths", []),
        include_paths = inspection_data.get("include_paths", []),
    )

def _pycross_wheel_file_impl(rctx):
    netrc = read_user_netrc(rctx)

    urls = rctx.attr.urls
    if not urls:
        urls = [get_pypi_file_url(
            rctx,
            netrc,
            rctx.attr.indexes,
            rctx.attr.package_name,
            rctx.attr.filename,
            rctx.attr.sha256,
        )]

    # Download the wheel file directly
    rctx.download(
        urls,
        rctx.attr.filename,
        rctx.attr.sha256,
        auth = use_netrc(netrc, urls, {}),
    )

    # Inspect the wheel for site_paths, bin_paths, data_paths, and include_paths
    exec_internal_tool(
        rctx,
        rctx.attr._inspect_tool,
        [
            "--wheel",
            rctx.attr.filename,
            "--output",
            "inspection.json",
        ],
    )
    inspection_data = json.decode(rctx.read("inspection.json"))

    rctx.file("BUILD.bazel", _render_wheel_file_build(
        filename = rctx.attr.filename,
        inspection_data = inspection_data,
    ))

    if not hasattr(rctx, "repo_metadata"):
        return None

    # Everything this repo contains is determined by the recorded inputs when
    # the wheel is pinned by a sha256: inspection.json and BUILD.bazel are
    # derived from the wheel bytes and the rule's attrs, and inspect_package.py
    # sorts every list it emits. Without a sha256, remote bytes can change, so
    # the repo must not be marked reproducible.
    return rctx.repo_metadata(reproducible = bool(rctx.attr.sha256))

pycross_wheel_file = repository_rule(
    implementation = _pycross_wheel_file_impl,
    attrs = {
        "urls": attr.string_list(doc = "Direct download URLs. If empty, the file is looked up in `indexes`."),
        "sha256": attr.string(default = "", doc = "Optional expected SHA-256 digest of the wheel."),
        "filename": attr.string(mandatory = True, doc = "The wheel filename."),
        "package_name": attr.string(doc = "Package name (required for index lookup)."),
        "indexes": attr.string_list(default = [DEFAULT_INDEX], doc = "Simple Repository API index URLs, tried in order."),
        "_inspect_tool": attr.label(default = "//pycross/private/tools:inspect_package.py"),
    },
)

# Visible for testing
render_wheel_file_build_for_testing = _render_wheel_file_build
