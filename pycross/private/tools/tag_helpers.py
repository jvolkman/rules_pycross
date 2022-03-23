from packaging import tags
from pip._internal.models.target_python import TargetPython
from typing import List, Tuple


def parse_tag(tag: str) -> List[tags.Tag]:
    """Decompresses the given possibly-compressed PEP 425 tag into multiple simple tags."""
    # See https://peps.python.org/pep-0425/#compressed-tag-sets

    try:
        parsed = tags.parse_tag(tag)
    except ValueError:
        raise ValueError(f"Invalid PEP 425 tag: {tag}")

    return list(parsed)


def get_implementation_and_version_info(pytag: str) -> Tuple[str, Tuple[int, ...]]:
    """Splits the given platform tag into implementation and version tuple."""
    # Adopted from pip._internal.cli.cmdoptions._convert_python_version

    m = re.match("([a-z_]+)([0-9]+)", pytag)
    if not m:
        raise ValueError(f"Invalid PEP 425 python tag: {pytag}")

    impl = m.group(1)
    ver = m.group(2)
    if len(ver) > 1:
        version_info = (int(ver[0]), int(ver[1:]))
    else:
        version_info = (int(ver),)

    return impl, version_info


def tag_to_target_python(tag: str) -> TargetPython:
    tag = tag.lower().strip()
    parsed_tags = parse_tag(tag)

    pythons = set()
    abis = set()
    platforms = set()

    for single_tag in parsed_tags:
        pythons.add(single_tag.interpreter)
        abis.add(single_tag.abi)
        platforms.add(single_tag.platform)

    # TargetPlatform can take multiple abis and platforms, but just one python.
    if len(pythons) > 1:
        raise ValueError(f"Tag targets multiple python implementations/versions: {tag}")

    pytag = pythons.pop()
    impl, version_info = get_implementation_and_version_info(pytag)

    return TargetPython(
        platforms=list(platforms),
        py_version_info=version_info,
        abis=list(abis),
        implementation=impl,
    )
