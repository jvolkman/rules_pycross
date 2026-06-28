"""musllinux platform tag generation.

Derived from pypa/packaging: packaging/_musllinux.py (Apache 2.0 / BSD).
See README.md for details.
"""

def musllinux_platforms(version, arch):
    """Generates musllinux platforms.

    Args:
        version: The musl version tuple (major, minor).
        arch: The architecture string.

    Returns:
        A list of musllinux platform strings.
    """
    platforms = []
    major = version[0]
    minor = version[1]
    for m in range(minor, -1, -1):
        platforms.append("musllinux_{}_{}_{}".format(major, m, arch))
    return platforms
