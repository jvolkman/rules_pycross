"""Shared Starlark primitives for lockfile translators.

Provides package name canonicalization, synthetic file entry builders,
PEP 508 requirement parsing, marker combination, root marker and edge
testonly classification, and raw lock serialization.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@pypackaging.bzl", "pypackaging")

def is_external_member_path(path):
    """Return True if a member path escapes the lock directory or is absolute.

    Checks Windows drive-letter prefixes (such as `C:\\libs\\ext`, `C:\\..\\ext`,
    or `C:/foo/../../ext`) before POSIX normalization so `..` segments cannot
    erase the drive prefix, while relative paths containing colons (such as
    `./a:b` or `1:2/pkg`) stay internal.

    Args:
        path: Member path string from a lockfile.

    Returns:
        True if the path is absolute or escapes the lock directory, False otherwise.
    """
    slash_path = path.replace("\\", "/")
    if len(slash_path) >= 2 and slash_path[0].isalpha() and slash_path[1] == ":":
        return True
    norm = paths.normalize(slash_path)
    return norm.startswith("/") or paths.starts_with(norm, "..")

def canonicalize_name(name):
    """Canonicalize a Python package name per PEP 503."""
    return pypackaging.utils.canonicalize_name(name)

def _archive_extension(url):
    """Return the filename suffix for an sdist synthesized from a direct URL.

    The build tooling picks the archive extractor by suffix, so a .zip archive
    must keep its extension.
    """
    path = url.split("#")[0].split("?")[0]
    return ".zip" if path.lower().endswith(".zip") else ".tar.gz"

def _sha256_from_string(s):
    """Generate a deterministic 64-character hex string from a string input.

    Used to create stable cache keys from git commit hashes because Starlark
    does not expose a cryptographic hash library.
    """
    if len(s) >= 64:
        return s[:64]

    result = s
    for _ in range(10):
        if len(result) >= 64:
            break
        result = result + s
    return result[:64]

def strip_sha256_prefix(file_hash, required = True):
    """Strip a `sha256:` prefix from `file_hash`.

    Args:
        file_hash: Hash string (for example, `"sha256:abcd..."`).
        required: If True, fail when the `sha256:` prefix is absent or the
            digest is empty.

    Returns:
        Hex digest without prefix, or `""` when not required and absent.
    """
    if file_hash and file_hash.startswith("sha256:"):
        digest = file_hash[len("sha256:"):]
        if digest:
            return digest
    if required:
        fail("Expected sha256: prefix with non-empty digest on hash: {}".format(file_hash))
    return ""

def make_file_entry(name, sha256, package_name, package_version, urls = None, index = None):
    """Build a raw_lock file entry dict, omitting empty `urls` and falsy `index`.

    Args:
        name: Distribution filename.
        sha256: Hex sha256 digest.
        package_name: Canonicalized package name.
        package_version: Package version string.
        urls: Optional list of download URLs.
        index: Optional package index URL.

    Returns:
        File entry dict for `raw_lock`.
    """
    entry = {
        "name": name,
        "sha256": sha256,
        "package_name": package_name,
        "package_version": package_version,
    }
    if urls:
        entry["urls"] = urls
    if index:
        entry["index"] = index
    return entry

def make_git_file_entry(package_name, package_version, git_url, commit, full_url = None):
    """Build a synthetic sdist file entry for a pinned git dependency.

    Args:
        package_name: Canonicalized package name.
        package_version: Package version string.
        git_url: Repository URL without the `git+` scheme prefix.
        commit: Pinned git commit SHA.
        full_url: Optional full URL overriding `git+<git_url>#<commit>`.

    Returns:
        File entry dict for `raw_lock`.
    """
    url = full_url if full_url != None else "git+{}#{}".format(git_url, commit)
    return make_file_entry(
        name = "{}-{}.tar.gz".format(package_name, package_version),
        sha256 = _sha256_from_string(commit),
        package_name = package_name,
        package_version = package_version,
        urls = [url],
    )

def make_archive_file_entry(package_name, package_version, url, sha256, index = None):
    """Build a synthetic sdist file entry for a direct-URL source archive.

    Args:
        package_name: Canonicalized package name.
        package_version: Package version string.
        url: Archive download URL.
        sha256: Hex sha256 digest.
        index: Optional package index URL.

    Returns:
        File entry dict for `raw_lock`.
    """
    return make_file_entry(
        name = "{}-{}{}".format(package_name, package_version, _archive_extension(url)),
        sha256 = sha256,
        package_name = package_name,
        package_version = package_version,
        urls = [url],
        index = index,
    )

def parse_pep508_requirement(req_str):
    """Parse a PEP 508 requirement string into structured components.

    Handles formats such as:
        "requests>=2.23.0,<3.0.0"
        "requests (>=2.23.0,<3.0.0)"
        "requests[security]>=2.0; python_version >= '3.6'"
        "urllib3<3,>=1.21.1"

    Args:
        req_str: The PEP 508 requirement string.

    Returns:
        A struct with `name`, `extras` (list), `specifier` (string), and
        `marker` (string).
    """
    req_str = req_str.strip()

    # Strip editable markers (PDM legacy)
    if req_str.startswith("-e "):
        req_str = req_str[3:].strip()

    parsed = pypackaging.requirements.parse(req_str)

    specifier_str = ""
    if parsed.specifier and parsed.specifier.specs:
        specifier_str = ",".join(["{}{}".format(s.operator, s.version) for s in parsed.specifier.specs])

    return struct(
        name = parsed.name,
        extras = parsed.extras,
        specifier = specifier_str,
        marker = parsed.marker_str or "",
    )

def combine_markers(parent_marker, dep_marker):
    """Combine two PEP 508 marker strings with `and`, simplifying empty or equal sides.

    Args:
        parent_marker: Outer marker string (may be `""`).
        dep_marker: Inner dependency marker string (may be `""`).

    Returns:
        Combined PEP 508 marker string.
    """
    if not parent_marker:
        return dep_marker
    if not dep_marker or parent_marker == dep_marker:
        return parent_marker
    return "({}) and ({})".format(parent_marker, dep_marker)

def record_root_marker(root_dependency_markers, name, marker):
    """Accumulate the environment markers on a root project dependency.

    A name maps to the list of markers from its root edges, or to `None` once
    any unmarked (unconditional) edge is seen.

    Args:
        root_dependency_markers: Dict mapping pin names to list of marker strings or `None`.
        name: Canonicalized package or extra pin name.
        marker: PEP 508 environment marker string.
    """
    if name in root_dependency_markers and root_dependency_markers[name] == None:
        return
    if not marker:
        root_dependency_markers[name] = None
        return
    existing = root_dependency_markers.get(name, [])
    if marker not in existing:
        root_dependency_markers[name] = existing + [marker]

def record_edge_testonly(edge, direct_testonly, expanded_testonly, non_testonly, direct_pin_testonly_set = None):
    """Classify an expanded root edge into direct-testonly, expanded-testonly, or non-testonly sets.

    When `direct_pin_testonly_set` is `None` (UV), direct testonly edges record
    only the package's base name. When provided (PDM and Poetry), direct
    testonly edges record `edge.pin_name` and also record the base name if it
    appears in `direct_pin_testonly_set`.

    Args:
        edge: Expanded root edge struct with `pin_name`, `is_testonly`, and `from_local`.
        direct_testonly: Dict mutated in place with directly testonly pin names.
        expanded_testonly: Dict mutated in place with base names reached as testonly via local packages.
        non_testonly: Dict mutated in place with base names reached from non-testonly edges.
        direct_pin_testonly_set: Optional dict of explicitly testonly pin names.
    """
    base = edge.pin_name.split("[")[0]
    if not edge.is_testonly:
        non_testonly[base] = True
        return
    if edge.from_local:
        expanded_testonly[base] = True
        return
    if direct_pin_testonly_set == None:
        direct_testonly[base] = True
        return
    direct_testonly[edge.pin_name] = True
    if base in direct_pin_testonly_set:
        direct_testonly[base] = True

def format_raw_lock(
        packages,
        pins,
        testonly_pins = None,
        variants = None,
        resolution_marker_exprs = None,
        root_dependency_markers = None):
    """Serialize translated lock data into the canonical `raw_lock.json` dict.

    Args:
        packages: Dict mapping package key -> raw package dict.
        pins: Dict mapping pin name -> pkg_key string or `{constraint: pkg_key}`.
        testonly_pins: Optional list of testonly pin names.
        variants: Optional list of variant set dicts.
        resolution_marker_exprs: Optional dict of constraint name -> marker expression or compound dict.
        root_dependency_markers: Optional dict of pin name -> marker list (or `None`, omitted).

    Returns:
        A dict in raw_lock.json format.
    """
    simplified_pins = {}
    for name, pin in pins.items():
        if type(pin) == "dict" and sorted(pin.keys()) == [""]:
            simplified_pins[name] = pin[""]
        else:
            simplified_pins[name] = pin

    result = {
        "packages": packages,
        "pins": simplified_pins,
        "testonly_pins": testonly_pins or [],
    }
    if variants:
        result["variants"] = variants
    if resolution_marker_exprs:
        result["resolution_marker_exprs"] = resolution_marker_exprs

    filtered_markers = {
        name: markers
        for name, markers in (root_dependency_markers or {}).items()
        if markers != None
    }
    if filtered_markers:
        result["root_dependency_markers"] = filtered_markers
    return result
