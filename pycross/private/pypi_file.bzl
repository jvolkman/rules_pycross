"""Rule to download files from pypi."""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "update_attrs", "use_netrc")
load("@pypackaging.bzl", "pypackaging")
load(":util.bzl", "url_decode_filename")

_PYPI_FILE_BUILD = """\
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

DEFAULT_INDEX = "https://pypi.org/simple"

# Prefer PEP 691 JSON, accept PEP 503 HTML. rctx.download does not expose the
# response Content-Type, so the body is sniffed instead.
_SIMPLE_ACCEPT = "application/vnd.pypi.simple.v1+json, application/vnd.pypi.simple.v1+html;q=0.2, text/html;q=0.01"

_HTML_ENTITIES = [
    ("&lt;", "<"),
    ("&gt;", ">"),
    ("&quot;", "\""),
    ("&#39;", "'"),
    ("&#x27;", "'"),
    ("&#43;", "+"),
    ("&#x2b;", "+"),
    ("&#x2B;", "+"),
    ("&amp;", "&"),  # Must be last.
]

def _html_unescape(s):
    for entity, char in _HTML_ENTITIES:
        s = s.replace(entity, char)
    return s

def _sha256_from_fragment(url):
    if "#" not in url:
        return None
    for part in url.split("#", 1)[1].split("&"):
        if part.startswith("sha256="):
            return part[len("sha256="):].lower()
    return None

def _parse_simple_html(content):
    """Parses a PEP 503 project page into a list of file dicts."""
    files = []
    lower = content.lower()
    pos = 0
    for _ in range(len(content)):
        start = lower.find("<a", pos)
        if start < 0:
            break
        pos = start + 2
        if pos >= len(content) or lower[pos] not in " \t\r\n>":
            continue
        end = lower.find(">", pos)
        if end < 0:
            break
        close = lower.find("</a>", end)
        if close < 0:
            break
        tag = content[pos:end]
        text = content[end + 1:close]
        pos = close + 4

        href = None
        tag_lower = tag.lower()
        idx = tag_lower.find("href")
        for _attempt in range(len(tag)):
            if idx < 0:
                break
            rest = tag[idx + 4:].lstrip()
            if (idx == 0 or tag[idx - 1] in " \t\r\n") and rest.startswith("="):
                rest = rest[1:].lstrip()
                if rest[:1] in ("\"", "'"):
                    href = rest[1:].split(rest[0], 1)[0]
                else:
                    href = rest.replace("\t", " ").replace("\r", " ").replace("\n", " ").split(" ", 1)[0]
                break
            idx = tag_lower.find("href", idx + 4)
        if href == None:
            continue
        href = _html_unescape(href.strip())
        files.append({
            "filename": _html_unescape(text.strip()),
            "url": href,
            "sha256": _sha256_from_fragment(href),
        })
    return files

def _parse_simple_json(content):
    """Parses a PEP 691 project page into a list of file dicts."""
    files = []
    for f in json.decode(content).get("files", []):
        sha256 = f.get("hashes", {}).get("sha256")
        files.append({
            "filename": f["filename"],
            "url": f["url"],
            "sha256": sha256.lower() if sha256 else None,
        })
    return files

def parse_simple_index(content):
    """Parses a Simple Repository API project page.

    Args:
        content: The page body, either PEP 691 JSON or PEP 503 HTML.

    Returns:
        A list of dicts with `filename`, `url` (as listed, possibly relative),
        and `sha256` (None if the index does not advertise one).
    """
    if content.lstrip().startswith("{"):
        return _parse_simple_json(content)
    return _parse_simple_html(content)

def resolve_url(base, ref):
    """Resolves a possibly-relative URL against a base URL, dropping any fragment.

    Args:
        base: The absolute URL of the page `ref` appeared on.
        ref: The URL to resolve.

    Returns:
        The absolute URL.
    """
    ref = ref.split("#", 1)[0]
    colon = ref.find(":")
    slash = ref.find("/")
    if colon > 0 and (slash < 0 or colon < slash):
        return ref

    scheme, _, rest = base.partition("://")
    authority, _, path = rest.partition("/")
    path = "/" + path.split("?", 1)[0].split("#", 1)[0]
    if ref.startswith("//"):
        return scheme + ":" + ref

    ref_path, sep, query = ref.partition("?")
    if ref_path.startswith("/"):
        joined = ref_path
    else:
        joined = path[:path.rfind("/") + 1] + ref_path

    segments = []
    parts = joined.split("/")[1:]
    for i, part in enumerate(parts):
        if part == "..":
            if segments:
                segments.pop()
            if i == len(parts) - 1:
                segments.append("")
        elif part == ".":
            if i == len(parts) - 1:
                segments.append("")
        else:
            segments.append(part)
    return scheme + "://" + authority + "/" + "/".join(segments) + sep + query

def find_simple_index_file(content, page_url, filename, sha256):
    """Locates a file on a Simple Repository API project page.

    Args:
        content: The page body.
        page_url: The URL the page was fetched from (base for relative URLs).
        filename: The exact filename to find.
        sha256: The expected sha256. Entries that advertise a different hash
            are ignored.

    Returns:
        A struct with `url` (None if not found) and `reason` (why not).
    """
    mismatch = None
    for f in parse_simple_index(content):
        url_name = url_decode_filename(f["url"].split("#", 1)[0].split("?", 1)[0].split("/")[-1])
        if filename not in (f["filename"], url_name):
            continue
        if f["sha256"] and sha256 and f["sha256"] != sha256.lower():
            mismatch = f["sha256"]
            continue
        return struct(url = resolve_url(page_url, f["url"]), reason = None)
    if mismatch:
        return struct(url = None, reason = "listed with sha256 {}, expected {}".format(mismatch, sha256))
    return struct(url = None, reason = "file not listed")

def get_pypi_file_url(rctx, netrc, indexes, package_name, filename, sha256, keep_metadata = False):
    """Resolves the URL of a file through the Simple Repository API.

    Each index is tried in order until one lists `filename`.

    Args:
        rctx: The repository context.
        netrc: The parsed netrc file.
        indexes: Simple API root URLs (e.g. https://pypi.org/simple), in priority order.
        package_name: The name of the package.
        filename: The filename to find.
        sha256: The expected sha256 of the file.
        keep_metadata: Whether to keep the downloaded index pages.

    Returns:
        The URL to the file.
    """
    project = pypackaging.utils.canonicalize_name(package_name)
    tried = []
    for i, index_url in enumerate(indexes):
        page_url = "{}/{}/".format(index_url.rstrip("/"), project)
        fetch_url = page_url

        # Static file:// indexes are directories; read their index.html like pip does.
        if page_url.startswith("file://"):
            fetch_url = page_url + "index.html"

        output = "simple_index/{}".format(i)
        result = rctx.download(
            fetch_url,
            output,
            allow_fail = True,
            headers = {"Accept": _SIMPLE_ACCEPT},
            auth = use_netrc(netrc, [fetch_url], {}),
        )
        if not result.success:
            tried.append("{}: could not fetch {}".format(index_url, fetch_url))
            continue

        found = find_simple_index_file(rctx.read(output), page_url, filename, sha256)
        if not keep_metadata:
            rctx.delete(output)
        if found.url:
            return found.url
        tried.append("{}: {}".format(index_url, found.reason))

    fail(
        ("File {} of package {} was not found in any index. Index URLs must be " +
         "Simple Repository API roots, e.g. {}. Tried:\n  {}").format(
            filename,
            package_name,
            DEFAULT_INDEX,
            "\n  ".join(tried),
        ),
    )

def _pypi_file_impl(ctx):
    """Implementation of the pypi_file rule."""

    netrc = read_user_netrc(ctx)
    url = get_pypi_file_url(
        ctx,
        netrc,
        ctx.attr.indexes,
        ctx.attr.package_name,
        ctx.attr.filename,
        ctx.attr.sha256,
        keep_metadata = ctx.attr.keep_metadata,
    )

    download_info = ctx.download(
        url,
        "file/" + ctx.attr.filename,
        ctx.attr.sha256,
        auth = use_netrc(netrc, [url], {}),
    )
    ctx.file("file/BUILD.bazel", _PYPI_FILE_BUILD.format(ctx.attr.filename))

    attrs = update_attrs(ctx.attr, _pypi_file_attrs.keys(), {"sha256": download_info.sha256})

    if not hasattr(ctx, "repo_metadata"):
        return attrs

    # sha256 is mandatory, so the downloaded file is pinned and the generated
    # BUILD file depends only on attrs. keep_metadata is the exception: it
    # retains the live index pages, which change as new releases are
    # published, so those repos stay non-reproducible.
    return ctx.repo_metadata(reproducible = not ctx.attr.keep_metadata)

_pypi_file_attrs = {
    "sha256": attr.string(
        doc = "The expected SHA-256 of the file downloaded.",
        mandatory = True,
    ),
    "indexes": attr.string_list(
        doc = "Simple Repository API (PEP 503/691) index URLs, tried in order until one lists the file.",
        default = [DEFAULT_INDEX],
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
        doc = "Whether to keep the downloaded index pages (under simple_index/) for debugging.",
    ),
}

pypi_file = repository_rule(
    implementation = _pypi_file_impl,
    attrs = _pypi_file_attrs,
    doc = "Downloads a file from a PyPI-compatible package index.",
)
