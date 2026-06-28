"""Compatible platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

def _py_interpreter_range(python_version):
    versions = []
    if len(python_version) > 1:
        versions.append("py" + "".join([str(p) for p in python_version[:2]]))
    versions.append("py" + str(python_version[0]))
    if len(python_version) > 1:
        for minor in range(python_version[1] - 1, -1, -1):
            versions.append("py" + "".join([str(python_version[0]), str(minor)]))
    return versions

def compatible_tags(python_version, interpreter, platforms):
    """Generates compatible tags.

    Args:
        python_version: The Python version tuple.
        interpreter: The interpreter string (e.g., "cp311").
        platforms: A list of platforms.

    Returns:
        A list of compatible tag strings.
    """
    tags = []
    for version in _py_interpreter_range(python_version):
        for platform in platforms:
            tags.append("{}-none-{}".format(version, platform))

    if interpreter:
        tags.append("{}-none-any".format(interpreter))

    for version in _py_interpreter_range(python_version):
        tags.append("{}-none-any".format(version))

    return tags
