"""macOS platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

def _mac_binary_formats(version, cpu_arch):
    formats = [cpu_arch]
    if cpu_arch == "x86_64":
        if version < (10, 4):
            return []
        formats.extend(["intel", "fat64", "fat32"])
    elif cpu_arch == "i386":
        if version < (10, 4):
            return []
        formats.extend(["intel", "fat32", "fat"])
    elif cpu_arch == "ppc64":
        if version > (10, 5) or version < (10, 4):
            return []
        formats.append("fat64")
    elif cpu_arch == "ppc":
        if version > (10, 6):
            return []
        formats.extend(["fat32", "fat"])

    if cpu_arch in ("arm64", "x86_64"):
        formats.append("universal2")

    if cpu_arch in ("x86_64", "i386", "ppc64", "ppc", "intel"):
        formats.append("universal")

    return formats

def mac_platforms(version, arch):
    """Generates macOS platforms.

    Args:
        version: The macOS version tuple (major, minor).
        arch: The architecture string.

    Returns:
        A list of macOS platform strings.
    """
    platforms = []
    if version >= (10, 0) and version < (11, 0):
        major_version = 10
        for minor_version in range(version[1], -1, -1):
            compat_version = (major_version, minor_version)
            binary_formats = _mac_binary_formats(compat_version, arch)
            for binary_format in binary_formats:
                platforms.append("macosx_{}_{}_{}".format(major_version, minor_version, binary_format))

    if version >= (11, 0):
        minor_version = 0
        for major_version in range(version[0], 10, -1):
            compat_version = (major_version, minor_version)
            binary_formats = _mac_binary_formats(compat_version, arch)
            for binary_format in binary_formats:
                platforms.append("macosx_{}_{}_{}".format(major_version, minor_version, binary_format))

        # Fallback to 10.x
        major_version = 10
        if arch == "x86_64":
            for minor_version in range(16, 3, -1):
                compat_version = (major_version, minor_version)
                binary_formats = _mac_binary_formats(compat_version, arch)
                for binary_format in binary_formats:
                    platforms.append("macosx_{}_{}_{}".format(major_version, minor_version, binary_format))
        else:
            for minor_version in range(16, 3, -1):
                binary_format = "universal2"
                platforms.append("macosx_{}_{}_{}".format(major_version, minor_version, binary_format))

    return platforms
