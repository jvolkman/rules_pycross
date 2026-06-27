"""manylinux platform tag generation.

Derived from pypa/packaging: packaging/_manylinux.py (Apache 2.0 / BSD).
See README.md for details.
"""

def manylinux_platforms(version, arch):
    """Generates manylinux platforms.

    Args:
        version: The glibc version tuple (major, minor).
        arch: The architecture string.

    Returns:
        A list of manylinux platform strings.
    """
    platforms = []

    too_old_glibc2_minor = 16
    if arch in ("x86_64", "i686"):
        too_old_glibc2_minor = 4

    if version[0] != 2:
        fail("Unsupported manylinux major version: {}".format(version[0]))

    legacy_map = {
        (2, 17): "manylinux2014",
        (2, 12): "manylinux2010",
        (2, 5): "manylinux1",
    }

    for minor in range(version[1], too_old_glibc2_minor, -1):
        platforms.append("manylinux_2_{}_{}".format(minor, arch))
        legacy = legacy_map.get((2, minor))
        if legacy:
            platforms.append("{}_{}".format(legacy, arch))

    return platforms
