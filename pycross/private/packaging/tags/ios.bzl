"""iOS platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

def ios_platforms(major, minor, multiarch):
    """Generates iOS platforms.

    Args:
        major: The major version of iOS.
        minor: The minor version of iOS.
        multiarch: The multiarch string.

    Returns:
        A list of iOS platform strings.
    """
    if major < 12:
        return []

    platforms = []
    platforms.append("ios_{}_{}_{}".format(major, minor, multiarch))

    for m in range(minor - 1, -1, -1):
        platforms.append("ios_{}_{}_{}".format(major, m, multiarch))

    for maj in range(major - 1, 11, -1):
        for m in range(9, -1, -1):
            platforms.append("ios_{}_{}_{}".format(maj, m, multiarch))
    return platforms
