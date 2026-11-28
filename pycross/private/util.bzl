"""Shared utilities"""

load("@pypackaging.bzl", "pypackaging")

def sanitize_name(val):
    """Sanitize a string into a valid Bazel repository and target name identifier.

    Lowercases and replaces every character outside `[a-z0-9_]` with `_`.

    Args:
        val: The string to sanitize.

    Returns:
        The sanitized string.
    """
    out = []
    for c in val.lower().elems():
        if ("a" <= c and c <= "z") or ("0" <= c and c <= "9") or c == "_":
            out.append(c)
        else:
            out.append("_")
    return "".join(out)

def marker_uses_extra(marker_str, cache = None):
    """Returns True if `marker_str` references the PEP 508 `extra` variable.

    Args:
        marker_str: The PEP 508 marker expression string.
        cache: Optional dict mapping marker strings to booleans. When provided,
            parsed results are read from and stored in this dict so repeated
            calls for the same marker string avoid re-parsing.

    Returns:
        Bool indicating whether the marker AST references `extra`.
    """
    if not marker_str or "extra" not in marker_str:
        return False
    if cache != None:
        cached = cache.get(marker_str)
        if cached != None:
            return cached
    result = "extra" in pypackaging.markers.variables(pypackaging.markers.parse(marker_str))
    if cache != None:
        cache[marker_str] = result
    return result

def marker_evaluator_name(marker_str, extra = "", extra_cache = None):
    """Generate a deterministic target name for a PEP 508 marker evaluator.

    Args:
        marker_str: The PEP 508 marker expression.
        extra: The PEP 508 extra value (e.g. 'test'), or '' for no extra.
        extra_cache: Optional dict passed to `marker_uses_extra` to memoize
            whether each marker string references `extra`.

    Returns:
        The deterministic target name string (e.g. '_marker_eval_<san>_<hash>').
    """

    # Starlark's hash() is deterministic within a build invocation.
    # We sanitize the marker string for readability and add the hash for uniqueness.
    effective_extra = extra if (extra and marker_uses_extra(marker_str, cache = extra_cache)) else ""
    key = marker_str if not effective_extra else "{}|extra={}".format(marker_str, effective_extra)
    san_chars = []
    for c in key.lower().elems():
        if c in (" ", "\"", "'"):
            continue
        if ("a" <= c and c <= "z") or ("0" <= c and c <= "9") or c == "_":
            san_chars.append(c)
        else:
            san_chars.append("_")
    san = "".join(san_chars)

    # Truncate to keep target names reasonable
    if len(san) > 40:
        san = san[:40]
    return "_marker_eval_{}_{}".format(san, hash(key))

def underscore_name(name):
    """rules_python-style normalization: lowercase, replace [-. ] with _."""
    return pypackaging.utils.canonicalize_name(name).replace("-", "_")

def extract_pep508_name(spec):
    """Extract the PEP 503 normalized package name from a PEP508 requirement line.

    Args:
        spec: The PEP508 requirement string to parse.

    Returns:
        The PEP 503 normalized package name (with hyphens) as a string.
    """
    return pypackaging.requirements.parse(spec).name

def hex_hash8(val):
    """Return a deterministic 8-character lowercase hex digest of `val`."""
    return ("00000000" + ("%x" % (hash(val) & 0xffffffff)))[-8:]

def resolution_marker_constraint_name(marker_expr):
    """Generate a deterministic, version-free constraint name for a PEP 508 marker expression.

    Used when a package has multiple versions (or sources at the same version)
    resolved for different environments, or when a dependency edge carries a
    resolution marker.

    Args:
        marker_expr: PEP 508 marker expression string.

    Returns:
        A content-hashed constraint name like `"res_a1b2c3d4"`.
    """
    return "res_{}".format(hex_hash8(marker_expr))

def format_package_key(name, version = "", extra = "", tag = ""):
    """Format a package key from its components.

    Args:
        name: Canonicalized package name.
        version: Optional version string.
        extra: Optional extra name.
        tag: Optional disambiguating source tag (omitted when empty).

    Returns:
        Formatted key string such as `name@version`, `name[extra]@version`,
        or `name@version~tag`.
    """
    base = "{}[{}]".format(name, extra) if extra else name
    if not version:
        return base
    if tag:
        return "{}@{}~{}".format(base, version, tag)
    return "{}@{}".format(base, version)

def parse_package_key(key):
    """Parses a package key or pin name into `(name, extra, version, tag)`.

    Supports formats:
      - name@version
      - name@version~tag
      - name[extra]@version
      - name[extra]@version~tag
      - name
      - name[extra]

    Args:
        key: The package key or pin name string.

    Returns:
        A struct of `(name, extra, version, tag)`. `name` is always present;
        `extra`, `version`, and `tag` are strings and empty when absent.
    """
    name_and_extra = key
    version = ""
    tag = ""
    if "@" in key:
        parts = key.split("@", 1)
        name_and_extra = parts[0]
        version = parts[1]
        if "~" in version:
            ver_parts = version.split("~", 1)
            version = ver_parts[0]
            tag = ver_parts[1]

    name = name_and_extra
    extra = ""
    if "[" in name_and_extra:
        if not name_and_extra.endswith("]"):
            fail("Invalid package key format: " + key)
        parts = name_and_extra.split("[", 1)
        name = parts[0]
        extra = parts[1][:-1]

    return struct(
        name = name,
        extra = extra,
        version = version,
        tag = tag,
    )

def base_package_key(pkg_key):
    """Return the base `name@version[~tag]` key for a package key (stripping any `[extra]`).

    Args:
        pkg_key: Package key string (e.g. `foo[bar]@1.0`, `foo[bar]@1.0~abcd1234`).

    Returns:
        Base package key string `name@version` or `name@version~tag`.
    """
    parts = parse_package_key(pkg_key)
    return format_package_key(parts.name, parts.version, tag = parts.tag)

def canonicalize_package_key(spec, allow_wildcard = False):
    """Canonicalize a package key or spec into structured components.

    Supports `'name'`, `'name[extra]'`, `'name@version'`, `'name[extra]@version'`,
    and `'name([extra])@version~tag'`, plus `'*'` when `allow_wildcard = True`.

    Args:
        spec: Package key or spec string.
        allow_wildcard: If True, `'*'` is accepted and returned as-is.

    Returns:
        A struct of `(canonical, name, extra, version, tag, has_version, has_tag)`.
    """
    if allow_wildcard and spec == "*":
        return struct(
            canonical = "*",
            name = "*",
            extra = "",
            version = "",
            tag = "",
            has_version = False,
            has_tag = False,
        )
    parts = parse_package_key(spec)
    norm_name = pypackaging.utils.canonicalize_name(parts.name)
    norm_extra = pypackaging.utils.canonicalize_name(parts.extra) if parts.extra else ""
    if "@" in spec:
        if not parts.version:
            fail("Invalid package key '{}': version cannot be empty after '@'".format(spec))
        if "~" in spec.split("@", 1)[1] and not parts.tag:
            fail("Invalid package key '{}': source tag cannot be empty after '~'".format(spec))
        canonical = format_package_key(norm_name, parts.version, extra = norm_extra, tag = parts.tag)
        return struct(
            canonical = canonical,
            name = norm_name,
            extra = norm_extra,
            version = parts.version,
            tag = parts.tag,
            has_version = True,
            has_tag = bool(parts.tag),
        )
    canonical = format_package_key(norm_name, extra = norm_extra)
    return struct(
        canonical = canonical,
        name = norm_name,
        extra = norm_extra,
        version = "",
        tag = "",
        has_version = False,
        has_tag = False,
    )

def sdist_builds_disallowed(pkg):
    """Whether build_mode = "never" forbids building this resolved package's sdist.

    A user-supplied build_target is exempt: it replaces the sdist build entirely.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if the package's sdist must not be built.
    """
    return pkg.get("build_mode") == "never" and not pkg.get("build_target")

def has_build_fallback(pkg):
    """Whether a resolved package can be built from source when no wheel matches.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if the package has a build_target, or an sdist that may be built.
    """
    if pkg.get("build_target"):
        return True
    return bool(pkg.get("sdist_file")) and not sdist_builds_disallowed(pkg)

def is_universal_py3_wheel(filename):
    """Return True if filename is a wheel containing the universal `py3-none-any` tag.

    A `py3-none-any` (or compressed `py2.py3-none-any`, etc.) wheel matches
    every Python 3 target platform unconditionally.

    Args:
        filename: Candidate wheel filename.

    Returns:
        True if the wheel contains the `py3-none-any` tag, False otherwise.
    """
    if not filename.lower().endswith(".whl"):
        return False
    parts = filename[:-4].split("-")
    if len(parts) not in (5, 6):
        return False
    py_tag, abi_tag, plat_tag = parts[-3].lower(), parts[-2].lower(), parts[-1].lower()
    return (
        "py3" in py_tag.split(".") and
        "none" in abi_tag.split(".") and
        "any" in plat_tag.split(".")
    )

def is_wheel_platform_specific(pkg):
    """Whether a resolved package's wheel selection alone can fail on some target platforms.

    True when the package has wheel candidates, no sdist/build_target fallback,
    and no universal py3-none-any candidate.

    Args:
        pkg: A resolved package dict (or slimmed thin-repo package dict).

    Returns:
        True if wheel selection may fail on some target platform.
    """
    if "wheel_platform_specific" in pkg:
        return pkg["wheel_platform_specific"]
    candidates = pkg.get("wheel_candidates", [])
    if not candidates or has_build_fallback(pkg):
        return False
    return not any([is_universal_py3_wheel(c["filename"]) for c in candidates])

def is_platform_specific(pkg):
    """Whether a resolved package may be unavailable in some target environments.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if the package may be unavailable on some target platform.
    """
    if pkg.get("availability_markers"):
        return True
    return is_wheel_platform_specific(pkg)

TRUE_FLAG_VALUES = ("True", "true", "1")
_FALSE_FLAG_VALUES = ("False", "false", "0")

def parse_flag_arg(flag):
    """Parse a CLI-style `--<flag>[=<value>]` repo flag string.

    Args:
        flag: Flag string starting with `--`.

    Returns:
        A struct of `(label, value, has_value)`:
          - `label`: The flag name/label after `--` (before `=`).
          - `value`: The value after `=`, or `"True"` when no `=` is present.
          - `has_value`: True if `=` was present in `flag`.
    """
    if not flag.startswith("--"):
        fail("Invalid repo flag {}: expected '--<flag>[=<value>]'".format(repr(flag)))
    label, sep, raw_value = flag[2:].partition("=")
    if not label:
        fail("Invalid repo flag {}: expected '--<flag>[=<value>]'".format(repr(flag)))
    return struct(
        label = label,
        value = raw_value if sep else "True",
        has_value = bool(sep),
    )

def coerce_transition_values(current, values):
    """Coerce raw repo transition values to the type of a setting's current value.

    Args:
        current: The setting's current value (determines the type).
        values: Raw string values, in order.

    Returns:
        All values for list settings; otherwise the last value as a bool, int or string.
    """
    t = type(current)
    if t == "list":
        return values
    value = values[-1]
    if t == "bool":
        if value in TRUE_FLAG_VALUES:
            return True
        if value in _FALSE_FLAG_VALUES:
            return False
        fail("Invalid boolean flag value: %r" % value)
    if t == "int":
        return int(value)
    return value

def split_setting_value(current, value):
    """Split a repo `settings` value like the command line: on commas for list settings.

    Args:
        current: The setting's current value (determines the type).
        value: The raw string value.

    Returns:
        A list of raw values for coerce_transition_values.
    """
    if type(current) == "list":
        return value.split(",") if value else []
    return [value]

# Mapping of common URL percent-encoded characters.
_URL_HEX_MAP = {
    "20": " ",
    "21": "!",
    "23": "#",
    "24": "$",
    "25": "%",
    "26": "&",
    "27": "'",
    "28": "(",
    "29": ")",
    "2B": "+",
    "2C": ",",
    "2D": "-",
    "2E": ".",
    "2F": "/",
    "3A": ":",
    "3B": ";",
    "3D": "=",
    "3F": "?",
    "40": "@",
    "5B": "[",
    "5D": "]",
    "5F": "_",
    "7E": "~",
}

def url_decode_filename(filename):
    """Decode percent-encoded characters in a URL-derived filename.

    Args:
        filename: A filename string potentially containing %XX sequences.

    Returns:
        The decoded filename string.
    """
    if "%" not in filename:
        return filename
    parts = []
    i = 0
    n = len(filename)
    for _ in range(n):
        if i >= n:
            break
        if filename[i] == "%" and i + 2 < n:
            hex_str = filename[i + 1:i + 3].upper()
            replacement = _URL_HEX_MAP.get(hex_str)
            if replacement:
                parts.append(replacement)
                i += 3
                continue
        parts.append(filename[i])
        i += 1
    return "".join(parts)

def url_filename(url):
    """Extract and percent-decode the filename component from a URL."""
    path_part = url.split("#", 1)[0].split("?", 1)[0]
    return url_decode_filename(path_part.split("/")[-1])
