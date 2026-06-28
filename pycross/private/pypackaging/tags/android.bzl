"""Android platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

def android_platforms(api_level, abi):
    platforms = []
    for ver in range(api_level, 15, -1):
        platforms.append("android_{}_{}".format(ver, abi))
    return platforms
