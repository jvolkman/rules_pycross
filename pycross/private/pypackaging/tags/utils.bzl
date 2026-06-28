"""Common utilities for platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

def version_nodot(version_tuple):
    return "".join([str(p) for p in version_tuple])

def get_python_version(version_str):
    if len(version_str) > 1:
        return (int(version_str[0]), int(version_str[1:]))
    else:
        return (int(version_str[0]),)
