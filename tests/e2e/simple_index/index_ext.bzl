"""Creates pypi_file / pycross_wheel_file repos backed by the local static indexes."""

load("@rules_pycross//pycross:defs.bzl", "pypi_file")

# buildifier: disable=bzl-visibility
load("@rules_pycross//pycross/private:wheel_file.bzl", "pycross_wheel_file")

_FILENAME = "cowsay-6.1-py3-none-any.whl"
_SHA256 = "274b1e6fc1b966d53976333eb90ac94cb07a450a700b455af9fbdf882244b30a"

def _index_ext_impl(mctx):
    root = "file://{}/index".format(mctx.path(Label("//:MODULE.bazel")).dirname)
    missing = root + "/missing"  # No such directory: the fetch fails.
    mismatch = root + "/mismatch"  # Lists the file with a different sha256.
    html = root + "/html"  # PEP 503 HTML.
    json_index = root + "/json"  # PEP 691 JSON.

    common = dict(
        filename = _FILENAME,
        sha256 = _SHA256,
        package_name = "Cowsay",  # Exercises PEP 503 name normalization.
        package_version = "6.1",
    )

    # Falls through a missing index and a hash-mismatched one to the HTML index.
    pycross_wheel_file(
        name = "wheel_html_fallback",
        indexes = [missing, mismatch, html],
        **common
    )
    pypi_file(
        name = "file_json",
        indexes = [json_index],
        **common
    )

    # Fetched only by run.sh, which expects it to fail.
    pypi_file(
        name = "file_not_found",
        indexes = [missing, mismatch],
        **common
    )

index_ext = module_extension(implementation = _index_ext_impl)
