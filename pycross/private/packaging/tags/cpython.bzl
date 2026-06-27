"""CPython platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

def _is_threaded_cpython(abis):
    if not abis:
        return False
    abi = abis[0]
    if not abi.startswith("cp"):
        return False
    return "t" in abi

def _abi3_applies(python_version, threading):
    return len(python_version) > 1 and python_version >= (3, 2) and not threading

def _abi3t_applies(python_version, threading):
    return len(python_version) > 1 and python_version >= (3, 2) and threading

def cpython_tags(python_version, abis, platforms):
    """Generates CPython tags.

    Args:
        python_version: The Python version tuple.
        abis: A list of ABIs.
        platforms: A list of platforms.

    Returns:
        A list of CPython tag strings.
    """
    tags = []
    version_str = "".join([str(p) for p in python_version[:2]])
    interpreter = "cp" + version_str

    explicit_abis = []
    if abis:
        for abi in abis:
            if abi not in ("abi3", "none"):
                explicit_abis.append(abi)

    for abi in explicit_abis:
        for platform in platforms:
            tags.append("{}-{}-{}".format(interpreter, abi, platform))

    threading = _is_threaded_cpython(abis)
    use_abi3 = _abi3_applies(python_version, threading)
    use_abi3t = _abi3t_applies(python_version, threading)

    if use_abi3:
        for platform in platforms:
            tags.append("{}-abi3-{}".format(interpreter, platform))
    if use_abi3t:
        for platform in platforms:
            tags.append("{}-abi3t-{}".format(interpreter, platform))

    for platform in platforms:
        tags.append("{}-none-{}".format(interpreter, platform))

    if use_abi3 or use_abi3t:
        for minor_version in range(python_version[1] - 1, 1, -1):
            prev_version_str = "".join([str(python_version[0]), str(minor_version)])
            prev_interpreter = "cp" + prev_version_str
            for platform in platforms:
                if use_abi3:
                    tags.append("{}-abi3-{}".format(prev_interpreter, platform))
                if use_abi3t:
                    tags.append("{}-abi3t-{}".format(prev_interpreter, platform))

    return tags
