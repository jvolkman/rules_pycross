"""PEP 440 Version handling.

Derived from pypa/packaging: packaging/version.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load("@re.bzl", "re")

def _fail_invalid_version(version):
    fail("Invalid version: {}".format(version))

# Simplified pattern for Starlark and re.bzl
_VERSION_PATTERN = r"""
    v?
    (?:
        (?:(?P<epoch>[0-9]+)!)?
        (?P<release>[0-9]+(?:\.[0-9]+)*)
        (?P<pre>
            [._-]?
            (?P<pre_l>alpha|a|beta|b|preview|pre|c|rc)
            [._-]?
            (?P<pre_n>[0-9]+)?
        )?
        (?P<post>
            (?:-(?P<post_n1>[0-9]+))
            |
            (?:
                [._-]?
                (?P<post_l>post|rev|r)
                [._-]?
                (?P<post_n2>[0-9]+)?
            )
        )?
        (?P<dev>
            [._-]?
            (?P<dev_l>dev)
            [._-]?
            (?P<dev_n>[0-9]+)?
        )?
    )
    (?:[+]
        (?P<local>
            [a-z0-9]+
            (?:[._-][a-z0-9]+)*
        )
    )?
"""

# Pre-compile regex
_VERSION_RE = re.compile(_VERSION_PATTERN, re.X | re.I)

# Sort ranks for pre-release: dev-only < a < b < rc < stable (no pre-release).
_PRE_RANK = {"a": 0, "b": 1, "rc": 2}
_PRE_RANK_DEV_ONLY = -1  # sorts before a(0)
_PRE_RANK_STABLE = 3  # sorts after rc(2)

# In local version segments, strings sort before ints per PEP 440.
_LOCAL_STR_RANK = -1  # sorts before all non-negative ints

# Pre-computed suffix for stable releases (no pre, post, or dev segments).
_STABLE_SUFFIX = (_PRE_RANK_STABLE, 0, 0, 0, 1, 0)

def _cmpkey(epoch, release, pre, post, dev, local):
    # Strip trailing zeros: 1.0.0 compares equal to 1.
    len_release = len(release)
    i = len_release
    for _ in range(len_release):
        if i and release[i - 1] == 0:
            i -= 1
        else:
            break
    trimmed = release if i == len_release else release[:i]

    # Fast path: stable release with no local segment.
    if pre == None and post == None and dev == None and local == None:
        return (epoch, trimmed, _STABLE_SUFFIX)

    if pre == None and post == None and dev != None:
        # dev-only (e.g. 1.0.dev1) sorts before all pre-releases.
        pre_rank, pre_n = _PRE_RANK_DEV_ONLY, 0
    elif pre == None:
        pre_rank, pre_n = _PRE_RANK_STABLE, 0
    else:
        pre_rank, pre_n = _PRE_RANK[pre[0]], pre[1]

    post_rank = 0 if post == None else 1
    post_n = 0 if post == None else post[1]

    dev_rank = 1 if dev == None else 0
    dev_n = 0 if dev == None else dev[1]

    suffix = (pre_rank, pre_n, post_rank, post_n, dev_rank, dev_n)

    if local == None:
        return (epoch, trimmed, suffix)

    cmp_local = []
    for seg in local:
        if type(seg) == type(0):
            cmp_local.append((seg, ""))
        else:
            cmp_local.append((_LOCAL_STR_RANK, seg))

    return (epoch, trimmed, suffix, tuple(cmp_local))

_LETTER_NORMALIZATION = {
    "alpha": "a",
    "beta": "b",
    "c": "rc",
    "pre": "rc",
    "preview": "rc",
    "rev": "post",
    "r": "post",
}

def _parse_letter_version(letter, number):
    if letter:
        letter = letter.lower()
        letter = _LETTER_NORMALIZATION.get(letter, letter)
        return (letter, int(number) if number else 0)
    if number:
        return ("post", int(number))
    return None

def _parse_local_version(local):
    if local == None:
        return None

    # Normalize separators to '.'
    normalized = local.replace("_", ".").replace("-", ".")
    parts = normalized.split(".")

    result = []
    for part in parts:
        if part.isdigit():
            result.append(int(part))
        else:
            result.append(part.lower())
    return tuple(result)

def get_public_key(v):
    """Returns the comparison key for the public version (without local segment)."""
    if v.local == None:
        return v.key
    return _cmpkey(v.epoch, v.release, v.pre, v.post, v.dev, None)

def make_version(epoch, release, pre, post, dev, local, version_str = ""):
    """Creates a Version struct and calculates its key."""
    key = _cmpkey(epoch, release, pre, post, dev, local)
    return struct(
        version_str = version_str,
        epoch = epoch,
        release = release,
        pre = pre,
        post = post,
        dev = dev,
        local = local,
        key = key,
        is_prerelease = (pre != None or dev != None),
        is_postrelease = (post != None),
        is_devrelease = (dev != None),
    )

def parse_version(version_str):
    """Parses a version string into a struct.

    Args:
        version_str: The version string to parse.

    Returns:
        A struct representing the parsed version.
    """
    m = _VERSION_RE.fullmatch(version_str)
    if not m:
        _fail_invalid_version(version_str)
        return None  # Unreachable

    epoch_str = m.group("epoch")
    epoch = int(epoch_str) if epoch_str else 0

    release_str = m.group("release")
    release = tuple([int(p) for p in release_str.split(".")])

    pre_l = m.group("pre_l")
    pre_n = m.group("pre_n")
    pre = _parse_letter_version(pre_l, pre_n)

    post_l = m.group("post_l")
    post_n1 = m.group("post_n1")
    post_n2 = m.group("post_n2")
    post_n = post_n1 if post_n1 else post_n2
    post = _parse_letter_version(post_l, post_n)

    dev_l = m.group("dev_l")
    dev_n = m.group("dev_n")
    dev = _parse_letter_version(dev_l, dev_n)

    local_str = m.group("local")
    local = _parse_local_version(local_str)

    return make_version(epoch, release, pre, post, dev, local, version_str)
