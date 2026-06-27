"""PEP 440 Version Specifiers.

Derived from pypa/packaging: packaging/specifiers.py (Apache 2.0 / BSD).
"""

load("@re.bzl", "re")
load("//pycross/private/packaging/version:version.bzl", "get_public_key", "make_version", "parse_version")

def _fail_invalid_specifier(spec):
    fail("Invalid specifier: {}".format(spec))

def _post_base(v):
    return make_version(v.epoch, v.release, v.pre, None, None, None)

def _earliest_prerelease(v):
    return make_version(v.epoch, v.release, v.pre, v.post, ("dev", 0), None)

_specifier_regex_str = r"""
(?:
    (?:
        ===
        \s*
        [^\s;)]*
    )
    |
    (?:
        (?:==|!=)
        \s*
        v?
        (?:[0-9]+!)?
        [0-9]+(?:\.[0-9]+)*
        (?:
            \.\*
            |
            (?:
                [-_\.]?
                (alpha|beta|preview|pre|a|b|c|rc)
                [-_\.]?
                [0-9]*
            )?
            (?:
                (?:-[0-9]+)|(?:[-_\.]?(post|rev|r)[-_\.]?[0-9]*)
            )?
            (?:[-_\.]?dev[-_\.]?[0-9]*)?
            (?:\+[a-z0-9]+(?:[-_\.][a-z0-9]+)*)?
        )?
    )
    |
    (?:
        (?:~=)
        \s*
        v?
        (?:[0-9]+!)?
        [0-9]+(?:\.[0-9]+)+
        (?:
            [-_\.]?
            (alpha|beta|preview|pre|a|b|c|rc)
            [-_\.]?
            [0-9]*
        )?
        (?:
            (?:-[0-9]+)|(?:[-_\.]?(post|rev|r)[-_\.]?[0-9]*)
        )?
        (?:[-_\.]?dev[-_\.]?[0-9]*)?
    )
    |
    (?:
        (?:<=|>=|<|>)
        \s*
        v?
        (?:[0-9]+!)?
        [0-9]+(?:\.[0-9]+)*
        (?:
            [-_\.]?
            (alpha|beta|preview|pre|a|b|c|rc)
            [-_\.]?
            [0-9]*
        )?
        (?:
            (?:-[0-9]+)|(?:[-_\.]?(post|rev|r)[-_\.]?[0-9]*)
        )?
        (?:[-_\.]?dev[-_\.]?[0-9]*)?
    )
)
"""

_SPECIFIER_RE = re.compile(r"\s*" + _specifier_regex_str + r"\s*", re.X | re.I)

def parse_specifier(spec_str):
    """Parses a single specifier string.

    Args:
        spec_str: The specifier string to parse.

    Returns:
        A struct representing the parsed specifier.
    """
    if not _SPECIFIER_RE.fullmatch(spec_str):
        _fail_invalid_specifier(spec_str)

    spec_str = spec_str.strip()
    if spec_str.startswith("==="):
        operator, version = spec_str[:3], spec_str[3:].strip()
    elif spec_str.startswith(("~=", "==", "!=", "<=", ">=")):
        operator, version = spec_str[:2], spec_str[2:].strip()
    else:
        operator, version = spec_str[:1], spec_str[1:].strip()

    return struct(
        operator = operator,
        version = version,
    )

def specifier_contains(spec, version_str):
    """Checks if a version satisfies a specifier.

    Args:
        spec: The specifier struct.
        version_str: The version string to check.

    Returns:
        True if the version satisfies the specifier, False otherwise.
    """
    if spec.operator == "===":
        return version_str.lower() == spec.version.lower()

    v1 = parse_version(version_str)

    if spec.operator == "==":
        if spec.version.endswith(".*"):
            spec_v = parse_version(spec.version[:-2])
            if v1.epoch != spec_v.epoch:
                return False

            # Pad v1.release with zeros if it is shorter than spec_v.release
            v1_release = list(v1.release)
            if len(v1_release) < len(spec_v.release):
                v1_release.extend([0] * (len(spec_v.release) - len(v1_release)))

            return tuple(v1_release[:len(spec_v.release)]) == spec_v.release
        else:
            v2 = parse_version(spec.version)
            v1_key = get_public_key(v1) if not v2.local else v1.key
            return v1_key == v2.key

    if spec.operator == "!=":
        if spec.version.endswith(".*"):
            spec_v = parse_version(spec.version[:-2])
            if v1.epoch != spec_v.epoch:
                return True

            # Pad v1.release with zeros if it is shorter than spec_v.release
            v1_release = list(v1.release)
            if len(v1_release) < len(spec_v.release):
                v1_release.extend([0] * (len(spec_v.release) - len(v1_release)))

            return tuple(v1_release[:len(spec_v.release)]) != spec_v.release
        else:
            v2 = parse_version(spec.version)
            v1_key = get_public_key(v1) if not v2.local else v1.key
            return v1_key != v2.key

    v2 = parse_version(spec.version)

    if spec.operator == ">=":
        return get_public_key(v1) >= v2.key

    if spec.operator == "<=":
        return get_public_key(v1) <= v2.key

    if spec.operator == ">":
        if not v1.key > v2.key:
            return False

        if not v2.is_postrelease and v1.is_postrelease and _post_base(v1).key == v2.key:
            return False

        if v1.local != None and get_public_key(v1) == v2.key:
            return False

        return True

    if spec.operator == "<":
        if not v1.key < v2.key:
            return False

        if not v2.is_prerelease and v1.is_prerelease and v1.key >= _earliest_prerelease(v2).key:
            return False

        return True

    if spec.operator == "~=":
        if len(v2.release) < 2:
            fail("Compatible operator ~= requires at least two release segments")

        if not (get_public_key(v1) >= v2.key):
            return False

        prefix_release = v2.release[:-1]

        if v1.epoch != v2.epoch:
            return False
        if len(v1.release) < len(prefix_release):
            return False
        return v1.release[:len(prefix_release)] == prefix_release

    fail("Operator {} not implemented".format(spec.operator))

def parse_specifier_set(spec_set_str):
    """Parses a comma-separated set of specifiers.

    Args:
        spec_set_str: The specifier set string to parse.

    Returns:
        A struct representing the parsed specifier set.
    """
    if not spec_set_str:
        return struct(specs = [])

    spec_strs = [s.strip() for s in spec_set_str.split(",")]
    specs = [parse_specifier(s) for s in spec_strs]

    return struct(
        specs = specs,
    )

def specifier_set_contains(spec_set, version_str):
    """Checks if a version satisfies all specifiers in the set.

    Args:
        spec_set: The specifier set struct.
        version_str: The version string to check.

    Returns:
        True if the version satisfies all specifiers, False otherwise.
    """
    for spec in spec_set.specs:
        if not specifier_contains(spec, version_str):
            return False
    return True
