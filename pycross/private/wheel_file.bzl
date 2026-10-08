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
    package_name = "{package_name}",
    package_version = "{package_version}",
    site_paths = {site_paths},
    bin_paths = {bin_paths},
    data_paths = {data_paths},
    include_paths = {include_paths},
)
"""

def _render_wheel_file_build(filename, package_name, package_version, inspection_data):
    return _BUILD_TEMPLATE.format(
        filename = filename,
        package_name = package_name or "",
        package_version = package_version or "",
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
    result = exec_internal_tool(
        rctx,
        rctx.attr._inspect_tool,
        [
            "--wheel",
            rctx.attr.filename,
            "--output",
            "inspection.json",
        ],
    )

    if result.return_code != 0:
        # Non-fatal: if inspection fails, write empty result
        # Note: exec_internal_tool will actually fail() if return_code != 0,
        # but if we somehow bypass it or change it, we write a fallback.
        inspection_data = {
            "site_paths": [],
            "bin_paths": [],
            "data_paths": [],
            "include_paths": [],
        }
        rctx.file("inspection.json", json.encode(inspection_data))
    else:
        inspection_data = json.decode(rctx.read("inspection.json"))

    rctx.file("BUILD.bazel", _render_wheel_file_build(
        filename = rctx.attr.filename,
        package_name = rctx.attr.package_name,
        package_version = rctx.attr.package_version,
        inspection_data = inspection_data,
    ))

    if not hasattr(rctx, "repo_metadata"):
        return None

    # Everything this repo contains is determined by the recorded inputs:
    # the wheel itself is pinned by the mandatory sha256, and inspection.json
    # plus BUILD.bazel are derived from the wheel bytes and the rule's attrs.
    # inspect_package.py reads only the zip entry names and entry_points.txt
    # and sorts every list it emits, so its output does not vary between runs
    # or machines for a given wheel.
    return rctx.repo_metadata(reproducible = True)

pycross_wheel_file = repository_rule(
    implementation = _pycross_wheel_file_impl,
    attrs = {
        "urls": attr.string_list(doc = "Direct download URLs. If empty, the file is looked up in `indexes`."),
        "sha256": attr.string(mandatory = True),
        "filename": attr.string(mandatory = True, doc = "The wheel filename."),
        "package_name": attr.string(doc = "Package name (required for index lookup)."),
        "package_version": attr.string(doc = "Package version."),
        "indexes": attr.string_list(default = [DEFAULT_INDEX], doc = "Simple Repository API index URLs, tried in order."),
        "_inspect_tool": attr.label(default = "//pycross/private/tools:inspect_package.py"),
    },
)

# Visible for testing
render_wheel_file_build_for_testing = _render_wheel_file_build
