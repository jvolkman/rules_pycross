"""Platform tag generation logic derived from pip and packaging.tags.

Derived from pypa/pip: pip/_internal/utils/compatibility_tags.py (MIT)
and pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

load("//pycross/private/packaging/tags:android.bzl", "android_platforms")
load("//pycross/private/packaging/tags:compatible.bzl", "compatible_tags")
load("//pycross/private/packaging/tags:cpython.bzl", "cpython_tags")
load("//pycross/private/packaging/tags:generic.bzl", "generic_tags")
load("//pycross/private/packaging/tags:ios.bzl", "ios_platforms")
load("//pycross/private/packaging/tags:macos.bzl", "mac_platforms")
load("//pycross/private/packaging/tags:manylinux.bzl", "manylinux_platforms")
load("//pycross/private/packaging/tags:musllinux.bzl", "musllinux_platforms")
load("//pycross/private/packaging/tags:utils.bzl", "get_python_version")

def _expand_platform(platform):
    if platform.startswith("macosx_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                arch = "_".join(parts[3:])
                return mac_platforms((major, minor), arch)
    elif platform.startswith("manylinux_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                arch = "_".join(parts[3:])
                return manylinux_platforms((major, minor), arch)
    elif platform.startswith("manylinux"):
        parts = platform.split("_", 1)
        if len(parts) == 2:
            prefix = parts[0]
            arch = parts[1]
            legacy_to_pep600 = {
                "manylinux1": (2, 5),
                "manylinux2010": (2, 12),
                "manylinux2014": (2, 17),
            }
            version = legacy_to_pep600.get(prefix)
            if version:
                return manylinux_platforms(version, arch)
    elif platform.startswith("musllinux_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                arch = "_".join(parts[3:])
                return musllinux_platforms((major, minor), arch)
    elif platform.startswith("android_"):
        parts = platform.split("_")
        if len(parts) >= 3:
            if parts[1].isdigit():
                api_level = int(parts[1])
                abi = "_".join(parts[2:])
                return android_platforms(api_level, abi)
    elif platform.startswith("ios_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                multiarch = "_".join(parts[3:])
                return ios_platforms(major, minor, multiarch)

    return [platform]

def _expand_allowed_platforms(platforms):
    if not platforms:
        return []

    seen = {}
    result = []

    for p in platforms:
        if p in seen:
            continue
        additions = _expand_platform(p)
        for add in additions:
            if add not in seen:
                seen[add] = True
                result.append(add)

    return result

def get_supported(version = None, platforms = None, impl = None, abis = None):
    """Return a list of supported tags.

    Args:
        version: The Python version string (e.g., "311").
        platforms: A list of allowed platforms.
        impl: The interpreter implementation prefix (e.g., "cp").
        abis: A list of ABIs.

    Returns:
        A list of compatibility tag strings.
    """
    supported = []

    if version:
        python_version = get_python_version(version)
    else:
        fail("version is required")

    if not impl:
        impl = "cp"

    interpreter = impl + "".join([str(p) for p in python_version[:2]])

    if not platforms:
        expanded_platforms = ["any"]
    else:
        expanded_platforms = _expand_allowed_platforms(platforms)

    is_cpython = impl == "cp"
    if is_cpython:
        supported.extend(cpython_tags(python_version, abis, expanded_platforms))
    else:
        supported.extend(generic_tags(interpreter, abis, expanded_platforms))

    supported.extend(compatible_tags(python_version, interpreter, expanded_platforms))

    return supported

def _make_tag(interpreter, abi, platform):
    return struct(
        interpreter = interpreter.lower(),
        abi = abi.lower(),
        platform = platform.lower(),
    )

def parse_tag(tag, validate_order = False):
    """Parses the provided tag into a list of Tag structs.

    Args:
        tag: The tag to parse (e.g., "py3-none-any").
        validate_order: Whether to check if compressed tag set components are in sorted order.

    Returns:
        A list of Tag structs.
    """
    component_parts = [component.split(".") for component in tag.split("-")]

    if len(component_parts) != 3:
        fail("Invalid tag: {}".format(tag))

    for parts in component_parts:
        if "" in parts:
            fail("Tag {} has an empty component".format(tag))

        # Starlark doesn't have sorted() that works on arbitrary lists easily without mutability?
        # Actually sorted() exists.
        if validate_order and parts != sorted(parts):
            fail("Tag component {} is not in sorted order".format(".".join(parts)))

    interpreters, abis, platforms = component_parts

    result = []
    for interpreter in interpreters:
        for abi in abis:
            for platform_ in platforms:
                result.append(_make_tag(interpreter, abi, platform_))

    return result

# Exported struct
tags = struct(
    get_supported = get_supported,
    parse_tag = parse_tag,
)
