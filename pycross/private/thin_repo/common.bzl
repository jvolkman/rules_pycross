"""Shared constants and small helpers for thin package repo generation."""

load("//pycross/private:util.bzl", "is_platform_specific", "parse_package_key")

NO_MATCH_ERROR_TARGET = "@rules_pycross//pycross/private:no_match_error"

# Per-repo "no variant selected" targets, emitted in _variants/BUILD.bazel with this repo's flag names.
NO_VARIANT_PREFIX = "//_variants:_no_variant_"

def safe_name(pin_name, name):
    """Avoid colliding a helper target name with the package's own pin name."""
    return name + "_" if pin_name == name else name

def is_key_platform_specific(packages, pkg_key):
    """Like is_platform_specific, but an extras key also inherits its base package's availability.

    Args:
        packages: Lock packages dict keyed by package key.
        pkg_key: Package key to check.

    Returns:
        True if the package (or its base package for an extras key) is platform-specific.
    """
    if is_platform_specific(packages.get(pkg_key, {})):
        return True
    parts = parse_package_key(pkg_key)
    if parts.extra:
        return is_platform_specific(packages.get("{}@{}".format(parts.name, parts.version), {}))
    return False

def aggregated_key(pkg_key, aggregated_keys):
    """Return the [_all_] aggregate key for pkg_key, unless aggregated_keys says it has no extras.

    Args:
        pkg_key: Base package key.
        aggregated_keys: Set/dict of base keys that have extras, or None.

    Returns:
        The aggregated lock key or `pkg_key` unchanged.
    """
    parts = parse_package_key(pkg_key)
    if aggregated_keys != None and "{}@{}".format(parts.name, parts.version) not in aggregated_keys:
        return pkg_key
    return "{}[_all_]@{}".format(parts.name, parts.version)

def effective_base_target_dict(group):
    """Return group['base_target'], or derive base lock keys from extras for extras-only pins.

    Args:
        group: Grouped pin dict with `base_target` and `extras`.

    Returns:
        Constraint-to-package-key dict, or None if neither base nor extras are present.
    """
    base_target_dict = group["base_target"]
    if base_target_dict or not group["extras"]:
        return base_target_dict
    derived = {}
    for _extra_name, extra_target_dict in sorted(group["extras"].items()):
        for constraint, extra_target in extra_target_dict.items():
            parts = parse_package_key(extra_target)
            derived.setdefault(constraint, "{}@{}".format(parts.name, parts.version))
    return derived
