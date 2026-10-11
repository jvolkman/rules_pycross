"""Pure helpers for mapping Python versions to the interpreter versions rules_python registers.

The mappings come from the rules_python hub (`@pythons_hub//:versions.bzl`), which reflects the
root module's configuration, including versions added with `python.single_version_override`.
rules_python's built-in `@rules_python//python:versions.bzl` tables do not.
"""

def get_micro_version(version, minor_mapping, python_versions):
    """Returns the `X.Y.Z` interpreter version for `version`.

    Args:
        version: A version string, `X.Y` or `X.Y.Z`.
        minor_mapping: Dict of `X.Y` -> `X.Y.Z` (the hub's `MINOR_MAPPING`).
        python_versions: List of known `X.Y.Z` versions (the hub's `PYTHON_VERSIONS`).

    Returns:
        The `X.Y.Z` version string, or None if the version is unknown.
    """
    if version in minor_mapping:
        return minor_mapping[version]
    if version in python_versions:
        return version
    return None

def dedupe_versions(versions, minor_mapping, python_versions):
    """Returns `versions` deduped by resolved micro version, skipping unknown versions.

    E.g., if '3.10' and '3.10.6' resolve to the same micro version, only '3.10.6' is kept.
    Otherwise there would be ambiguous select() criteria.

    Args:
        versions: List of version strings.
        minor_mapping: Dict of `X.Y` -> `X.Y.Z` (the hub's `MINOR_MAPPING`).
        python_versions: List of known `X.Y.Z` versions (the hub's `PYTHON_VERSIONS`).

    Returns:
        A sorted list of version strings.
    """
    unique_versions = {}
    for version in sorted(versions):
        # Skip versions the hub doesn't know (e.g. EOL Python 3.8 still appears in the
        # python_versions hub's pip.bzl after rules_python dropped it).
        micro_version = get_micro_version(version, minor_mapping, python_versions)
        if not micro_version:
            continue

        # In sorted order, 3.10.6 will override 3.10.
        unique_versions[micro_version] = version

    return sorted(unique_versions.values())

def resolve_interpreter_version(value, default_version, minor_mapping, python_versions):
    """Maps the `python_version` flag value to the selected `X.Y.Z` interpreter version.

    Args:
        value: The `@rules_python//python/config_settings:python_version` value (may be empty).
        default_version: The `X.Y.Z` version to use when `value` is empty or unknown.
        minor_mapping: Dict of `X.Y` -> `X.Y.Z` (the hub's `MINOR_MAPPING`).
        python_versions: List of known `X.Y.Z` versions (the hub's `PYTHON_VERSIONS`).

    Returns:
        The `X.Y.Z` version string.
    """
    value = minor_mapping.get(value, value)
    if value not in python_versions:
        return default_version
    return value
