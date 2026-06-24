"""Wheel chooser rule for selecting the best-matching wheel at analysis time.

Given a JSON-encoded list of pre-parsed wheel candidates and the current
platform's PEP 508 marker values (provided via select() on @platforms
constraints), this rule picks the best compatible wheel and returns its
filename through config_common.FeatureFlagInfo.

The selection algorithm:
  1. Filter candidates by platform, python, and ABI tag compatibility.
  2. Score remaining candidates by specificity (more specific = higher).
  3. Return the highest-scoring candidate's filename, or
     "__no_matching_wheel__" if nothing matches.
"""

load(":pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "marker_value_attrs")

# ---------------------------------------------------------------------------
# Tag compatibility helpers
# ---------------------------------------------------------------------------

def _platform_tag_matches(platform_tag, sys_platform, platform_machine, libc = ""):
    """Check whether a wheel's platform_tag is compatible with the host.

    Args:
        platform_tag: The wheel's platform tag string (e.g. "manylinux_2_28_x86_64").
        sys_platform: The host sys.platform value (e.g. "linux", "darwin", "win32").
        platform_machine: The host platform.machine value (e.g. "x86_64", "aarch64").
        libc: The host libc variant ("glibc", "musl", or "" for unknown/non-Linux).

    Returns:
        True if the wheel can run on this platform.
    """
    if platform_tag == "any":
        return True

    # OS match
    os_ok = False
    if "linux" in platform_tag and sys_platform == "linux":
        os_ok = True
    elif "macosx" in platform_tag and sys_platform == "darwin":
        os_ok = True
    elif "win" in platform_tag and sys_platform == "win32":
        os_ok = True

    if not os_ok:
        return False

    # Libc match: manylinux wheels require glibc, musllinux wheels require musl.
    if libc:
        if "manylinux" in platform_tag and libc != "glibc":
            return False
        if "musllinux" in platform_tag and libc != "musl":
            return False

    # Architecture match
    if "x86_64" in platform_tag or "amd64" in platform_tag:
        return platform_machine == "x86_64" or platform_machine == "amd64"
    elif "aarch64" in platform_tag or "arm64" in platform_tag:
        return platform_machine in ("aarch64", "arm64")
    elif "i686" in platform_tag or "x86" in platform_tag:
        return platform_machine in ("i686", "x86", "i386")

    # Platform tag specifies OS but no recognisable arch — accept any arch.
    return True

def _single_python_tag_matches(tag, python_version, freethreaded = "no"):
    """Check whether a single (non-compound) python tag matches.

    Args:
        tag: A single python tag like "cp311", "py3", "py2", "cp313t".
        python_version: The host python version as "X.Y". May be empty.
        freethreaded: "yes" if the host Python is freethreaded, "no" otherwise.

    Returns:
        True if the tag is compatible.
    """
    if tag == "py3":
        return not python_version or python_version.startswith("3")
    if tag == "py2":
        return python_version.startswith("2") if python_version else False

    if not python_version:
        return False

    # cpXY / cpXYZ style — e.g. "cp311" for CPython 3.11, "cp313t" for freethreaded.
    if tag.startswith("cp"):
        tag_rest = tag[2:]
        is_free = tag_rest.endswith("t")
        tag_digits = tag_rest[:-1] if is_free else tag_rest

        # Freethreaded tags only match freethreaded builds and vice versa.
        if is_free and freethreaded != "yes":
            return False
        if not is_free and freethreaded == "yes":
            # Non-freethreaded cpXYZ tags don't match freethreaded builds
            # (freethreaded builds need cp313t, not cp313).
            # Exception: "cp3" without version digits is a generic tag.
            if tag_digits.isdigit() and len(tag_digits) >= 2:
                return False

        if len(tag_digits) >= 2:
            expected = tag_digits[0] + "." + tag_digits[1:]
            return python_version == expected

    # pyXY style — e.g. "py311". These are version-generic, never freethreaded.
    if tag.startswith("py") and len(tag) > 2:
        tag_digits = tag[2:]
        if tag_digits.isdigit() and len(tag_digits) >= 1:
            expected = tag_digits[0] + "." + tag_digits[1:]
            return python_version == expected or python_version.startswith(tag_digits[0] + ".")

    return False

def _python_tag_matches(python_tag, python_version, freethreaded = "no"):
    """Check whether a wheel's python_tag is compatible with the host Python.

    Args:
        python_tag: The wheel's python tag (e.g. "cp311", "py3", "py2.py3").
                    May be a compound dot-separated tag.
        python_version: The host python version as "X.Y" (e.g. "3.11").
                        May be empty if unknown.
        freethreaded: "yes" if the host Python is freethreaded, "no" otherwise.

    Returns:
        True if the wheel can run on this Python.
    """

    # Handle compound tags (e.g. "py2.py3", "cp39.cp310") by checking each subtag.
    if "." in python_tag:
        subtags = python_tag.split(".")

        # Only split if it looks like multiple tags (each starts with py/cp).
        is_compound = len(subtags) > 1
        for s in subtags:
            if not (s.startswith("py") or s.startswith("cp")):
                is_compound = False
                break
        if is_compound:
            for s in subtags:
                if _single_python_tag_matches(s, python_version, freethreaded):
                    return True
            return False

    return _single_python_tag_matches(python_tag, python_version, freethreaded)

def _abi_tag_matches(abi_tag, python_version, freethreaded = "no"):
    """Check whether a wheel's abi_tag is compatible.

    Args:
        abi_tag: The wheel's ABI tag (e.g. "cp311", "abi3", "none", "cp313t").
        python_version: The host python version as "X.Y". May be empty.
        freethreaded: "yes" if the host Python is freethreaded, "no" otherwise.

    Returns:
        True if the ABI is compatible.
    """
    if abi_tag == "none":
        return True
    if abi_tag == "abi3":
        # Stable ABI — compatible with any non-freethreaded CPython >= 3.2.
        # Freethreaded builds don't support the stable ABI yet.
        if freethreaded == "yes":
            return False
        return not python_version or python_version.startswith("3")

    # Version-specific ABI tags require a known python_version.
    if not python_version:
        return False

    if abi_tag.startswith("cp"):
        tag_digits = abi_tag[2:]
        if len(tag_digits) >= 2:
            expected = tag_digits[0] + "." + tag_digits[1:]
            return python_version == expected
    return False

# ---------------------------------------------------------------------------
# Scoring helpers
# ---------------------------------------------------------------------------

def _python_tag_score(python_tag):
    """Score a python tag by specificity (higher = more specific).

    Args:
        python_tag: The wheel's python tag string.

    Returns:
        Integer score.
    """
    if python_tag == "py2.py3":
        return 0
    if python_tag == "py3":
        return 1
    if python_tag.startswith("cp") and len(python_tag) == 3:
        # e.g. "cp3" — version-major only.
        return 2
    if python_tag.startswith("cp"):
        # e.g. "cp311" — fully pinned.
        return 3
    return 1

def _abi_tag_score(abi_tag):
    """Score an ABI tag by specificity.

    Args:
        abi_tag: The wheel's ABI tag string.

    Returns:
        Integer score.
    """
    if abi_tag == "none":
        return 1
    if abi_tag == "abi3":
        return 2
    if abi_tag.startswith("cp"):
        return 3
    return 1

def _manylinux_version(platform_tag):
    """Extract a (major, minor) version tuple from a manylinux tag.

    Args:
        platform_tag: A platform tag string.

    Returns:
        A (major, minor) tuple, or None if not a manylinux tag.
    """
    prefix = "manylinux_"
    idx = platform_tag.find(prefix)
    if idx == -1:
        return None

    rest = platform_tag[idx + len(prefix):]

    # rest is e.g. "2_28_x86_64"; we want the first two _-separated parts.
    parts = rest.split("_")
    if len(parts) >= 2:
        major = parts[0]
        minor = parts[1]
        if major.isdigit() and minor.isdigit():
            return (int(major), int(minor))
    return None

def _platform_tag_score(platform_tag):
    """Score a platform tag by specificity.

    Args:
        platform_tag: The wheel's platform tag string.

    Returns:
        Integer score.
    """
    if platform_tag == "any":
        return 0

    base_score = 2
    ml = _manylinux_version(platform_tag)
    if ml != None:
        # Higher manylinux version = higher score.
        # e.g. manylinux_2_28 scores higher than manylinux_2_17.
        base_score = 2 + ml[0] * 100 + ml[1]
    return base_score

def _candidate_score(candidate):
    """Compute an overall priority score for a candidate.

    Args:
        candidate: A candidate dict with "python_tag", "abi_tag", "platform_tag".

    Returns:
        A list of integers suitable for comparison (higher = better).
    """
    return [
        _python_tag_score(candidate["python_tag"]),
        _platform_tag_score(candidate["platform_tag"]),
        _abi_tag_score(candidate["abi_tag"]),
    ]

# ---------------------------------------------------------------------------
# Public selection entry point
# ---------------------------------------------------------------------------

def select_best_wheel(candidates, sys_platform, platform_machine, python_version, libc = "", freethreaded = "no"):
    """Select the best-matching wheel from a list of candidates.

    Args:
        candidates: List of candidate dicts, each with keys "filename",
            "python_tag", "abi_tag", "platform_tag", and optionally
            "requires_python".
        sys_platform: The host sys.platform value (e.g. "linux").
        platform_machine: The host platform.machine (e.g. "x86_64").
        python_version: The host Python version as "X.Y" (e.g. "3.11").
        libc: The host libc variant ("glibc", "musl", or "").
        freethreaded: "yes" if the host Python is freethreaded, "no" otherwise.

    Returns:
        The best candidate dict, or None if no candidate is compatible.
    """
    best = None
    best_score = None

    for candidate in candidates:
        ptag = candidate.get("platform_tag", "any")
        pytag = candidate.get("python_tag", "py3")
        atag = candidate.get("abi_tag", "none")

        if not _platform_tag_matches(ptag, sys_platform, platform_machine, libc):
            continue
        if not _python_tag_matches(pytag, python_version, freethreaded):
            continue
        if not _abi_tag_matches(atag, python_version, freethreaded):
            continue

        score = _candidate_score(candidate)
        if best == None or _score_gt(score, best_score):
            best = candidate
            best_score = score

    return best

def _score_gt(a, b):
    """Return True if score list `a` is strictly greater than `b`.

    Compares element-by-element from most significant to least.

    Args:
        a: A list of integers.
        b: A list of integers.

    Returns:
        True if a > b lexicographically.
    """
    for i in range(len(a)):
        if a[i] > b[i]:
            return True
        if a[i] < b[i]:
            return False
    return False

# ---------------------------------------------------------------------------
# Rule implementation
# ---------------------------------------------------------------------------

def _pycross_wheel_chooser_impl(ctx):
    candidates = json.decode(ctx.attr.candidates)
    markers = collect_markers(ctx)

    best = select_best_wheel(
        candidates = candidates,
        sys_platform = markers["sys_platform"],
        platform_machine = markers["platform_machine"],
        python_version = markers["python_version"],
        libc = ctx.attr.libc,
        freethreaded = ctx.attr.freethreaded,
    )

    if best:
        value = best["filename"]
    else:
        value = "__no_matching_wheel__"

    return [config_common.FeatureFlagInfo(value = value)]

_pycross_wheel_chooser = rule(
    implementation = _pycross_wheel_chooser_impl,
    attrs = dict(
        candidates = attr.string(
            mandatory = True,
            doc = (
                "JSON-encoded list of wheel candidates. Each candidate is an " +
                "object with keys: filename, python_tag, abi_tag, platform_tag, " +
                "and optionally requires_python."
            ),
        ),
        libc = attr.string(
            default = "",
            doc = "The host libc variant: 'glibc', 'musl', or '' (unknown/non-Linux).",
        ),
        freethreaded = attr.string(
            default = "no",
            doc = "'yes' if the host Python is freethreaded, 'no' otherwise.",
        ),
        **marker_value_attrs()
    ),
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
)

def pycross_wheel_chooser(name, **kwargs):
    """Select the best-matching wheel from a list of candidates.

    This macro wraps the private _pycross_wheel_chooser rule. It takes a
    JSON-encoded list of pre-parsed wheel candidates and PEP 508 marker
    dimension values (typically provided via select()), and produces a
    config_common.FeatureFlagInfo whose value is the filename of the best
    matching wheel.

    Args:
        name: The target name.
        **kwargs: Forwarded to _pycross_wheel_chooser.
    """
    _pycross_wheel_chooser(name = name, **kwargs)
