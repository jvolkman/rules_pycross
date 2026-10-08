"""Tests for Simple Repository API parsing in pypi_file.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:pypi_file.bzl", "find_simple_index_file", "parse_simple_index", "resolve_url")

_SHA_A = "a" * 64
_SHA_B = "b" * 64

_HTML_PAGE = """<!DOCTYPE html>
<html>
  <head><meta name="pypi:repository-version" content="1.1"><title>Links for foo</title></head>
  <body>
    <h1>Links for foo</h1>
    <a href="https://files.example.com/packages/ab/cd/foo-1.0.tar.gz#sha256={sha_a}" data-requires-python="&gt;=3.8">foo-1.0.tar.gz</a><br />
    <A HREF='../../packages/foo-1.0-py3-none-any.whl?a=1&amp;b=2#md5=00&amp;sha256={sha_b}' >foo-1.0-py3-none-any.whl</A><br />
    <a data-yanked="" href=/abs/foo-0.9.tar.gz>foo-0.9.tar.gz</a>
    <a name="anchor-without-href">ignored</a>
  </body>
</html>
""".format(sha_a = _SHA_A, sha_b = _SHA_B)

_JSON_PAGE = json.encode({
    "meta": {"api-version": "1.1"},
    "name": "foo",
    "files": [
        {"filename": "foo-1.0.tar.gz", "url": "https://files.example.com/foo-1.0.tar.gz", "hashes": {"sha256": _SHA_A.upper()}},
        {"filename": "foo-1.0-py3-none-any.whl", "url": "../../packages/foo-1.0-py3-none-any.whl", "hashes": {}},
    ],
})

def _unit_test(name, impl):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = impl)

# buildifier: disable=unused-variable
def _test_parse_html_impl(env, target):
    files = parse_simple_index(_HTML_PAGE)
    env.expect.that_collection(files).contains_exactly([
        {
            "filename": "foo-1.0.tar.gz",
            "url": "https://files.example.com/packages/ab/cd/foo-1.0.tar.gz#sha256=" + _SHA_A,
            "sha256": _SHA_A,
        },
        {
            "filename": "foo-1.0-py3-none-any.whl",
            "url": "../../packages/foo-1.0-py3-none-any.whl?a=1&b=2#md5=00&sha256=" + _SHA_B,
            "sha256": _SHA_B,
        },
        {
            "filename": "foo-0.9.tar.gz",
            "url": "/abs/foo-0.9.tar.gz",
            "sha256": None,
        },
    ]).in_order()

def _test_parse_html(name):
    _unit_test(name, _test_parse_html_impl)

# buildifier: disable=unused-variable
def _test_parse_json_impl(env, target):
    files = parse_simple_index("\n  " + _JSON_PAGE)
    env.expect.that_collection(files).contains_exactly([
        {"filename": "foo-1.0.tar.gz", "url": "https://files.example.com/foo-1.0.tar.gz", "sha256": _SHA_A},
        {"filename": "foo-1.0-py3-none-any.whl", "url": "../../packages/foo-1.0-py3-none-any.whl", "sha256": None},
    ]).in_order()

def _test_parse_json(name):
    _unit_test(name, _test_parse_json_impl)

# buildifier: disable=unused-variable
def _test_resolve_url_impl(env, target):
    base = "https://example.com/simple/foo/"
    cases = {
        "https://other.com/a.whl#sha256=x": "https://other.com/a.whl",
        "//cdn.example.com/a.whl": "https://cdn.example.com/a.whl",
        "/packages/a.whl": "https://example.com/packages/a.whl",
        "a.whl": "https://example.com/simple/foo/a.whl",
        "./a.whl": "https://example.com/simple/foo/a.whl",
        "../../packages/x/a.whl?q=1#sha256=x": "https://example.com/packages/x/a.whl?q=1",
        "../../../../a.whl": "https://example.com/a.whl",
    }
    for ref, expected in cases.items():
        env.expect.where(ref = ref).that_str(resolve_url(base, ref)).equals(expected)

    file_base = "file:///srv/index/foo/"
    env.expect.that_str(resolve_url(file_base, "../../files/a.whl")).equals("file:///srv/files/a.whl")
    env.expect.that_str(resolve_url(file_base, "/other/a.whl")).equals("file:///other/a.whl")

def _test_resolve_url(name):
    _unit_test(name, _test_resolve_url_impl)

# buildifier: disable=unused-variable
def _test_find_file_impl(env, target):
    page = "https://example.com/simple/foo/"

    # HTML, matched by anchor text, resolved relative to the page.
    found = find_simple_index_file(_HTML_PAGE, page, "foo-1.0-py3-none-any.whl", _SHA_B)
    env.expect.that_str(found.url).equals("https://example.com/packages/foo-1.0-py3-none-any.whl?a=1&b=2")

    # JSON, upper-case advertised hash still matches.
    found = find_simple_index_file(_JSON_PAGE, page, "foo-1.0.tar.gz", _SHA_A)
    env.expect.that_str(found.url).equals("https://files.example.com/foo-1.0.tar.gz")

    # No advertised hash: accepted; the download itself verifies sha256.
    found = find_simple_index_file(_HTML_PAGE, page, "foo-0.9.tar.gz", _SHA_A)
    env.expect.that_str(found.url).equals("https://example.com/abs/foo-0.9.tar.gz")

    # Advertised hash differs from the lock: skipped with a reason.
    found = find_simple_index_file(_HTML_PAGE, page, "foo-1.0.tar.gz", _SHA_B)
    env.expect.that_bool(found.url == None).equals(True)
    env.expect.that_str(found.reason).contains("listed with sha256 " + _SHA_A)

    # Not listed.
    found = find_simple_index_file(_JSON_PAGE, page, "foo-2.0.tar.gz", _SHA_A)
    env.expect.that_bool(found.url == None).equals(True)
    env.expect.that_str(found.reason).equals("file not listed")

    # Matched by the percent-decoded URL basename when the anchor text differs.
    torch = '<a href="/whl/cpu/torch-2.5.1%2Bcpu-cp312-cp312-linux_x86_64.whl#sha256={}">torch</a>'.format(_SHA_A)
    found = find_simple_index_file(torch, "https://download.pytorch.org/whl/cpu/torch/", "torch-2.5.1+cpu-cp312-cp312-linux_x86_64.whl", _SHA_A)
    env.expect.that_str(found.url).equals("https://download.pytorch.org/whl/cpu/torch-2.5.1%2Bcpu-cp312-cp312-linux_x86_64.whl")

def _test_find_file(name):
    _unit_test(name, _test_find_file_impl)

def pypi_file_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_parse_html,
            _test_parse_json,
            _test_resolve_url,
            _test_find_file,
        ],
    )
