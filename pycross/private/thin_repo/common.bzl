"""Shared constants and small helpers for thin package repo generation."""

load("//pycross/private:util.bzl", "base_package_key", "is_platform_specific", "parse_package_key")

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
        return is_platform_specific(packages.get(base_package_key(pkg_key), {}))
    return False

def effective_base_target_dict(group, resolution_marker_exprs = None, variant_constraints = None):
    """Return constraint -> base lock key for a grouped pin, including constraints only present on extras.

    Skips injecting extra constraints already subsumed by an existing base
    constraint for the same base package key (an unconditional `""` default,
    a parent `variant` or `marker` of a compound resolution marker, or a
    non-variant base constraint when the extra constraint is variant-gated),
    avoiding ambiguous `select()` matches and spurious `_unselected_` checks.

    Args:
        group: Grouped pin dict with `base_target` and `extras`.
        resolution_marker_exprs: Optional lock `resolution_marker_exprs` dict.
        variant_constraints: Optional set/dict of variant-gated constraint names
            (e.g. `no_variant_fallbacks.sets`).

    Returns:
        Constraint-to-package-key dict, or None if neither base nor extras are present.
    """
    base_target_dict = group["base_target"]
    extras = group["extras"]
    if not extras:
        return base_target_dict

    derived = dict(base_target_dict) if base_target_dict else {}
    default_base = base_target_dict.get("") if base_target_dict else None
    if default_base == None:
        for _extra_name, extra_target_dict in sorted(extras.items()):
            if "" in extra_target_dict:
                default_base = base_package_key(extra_target_dict[""])
                derived.setdefault("", default_base)
                break

    res_exprs = resolution_marker_exprs or {}
    non_variant_bases = {}
    if base_target_dict and variant_constraints != None:
        for base_c, base_k in base_target_dict.items():
            if base_c not in variant_constraints:
                non_variant_bases[base_k] = True

    for _extra_name, extra_target_dict in sorted(extras.items()):
        for constraint, extra_target in sorted(extra_target_dict.items()):
            base_key = base_package_key(extra_target)
            if default_base != None and base_key == default_base:
                continue
            if base_target_dict:
                expr = res_exprs.get(constraint)
                if type(expr) == "dict":
                    if base_target_dict.get(expr.get("marker")) == base_key or base_target_dict.get(expr.get("variant")) == base_key:
                        continue
                if variant_constraints != None and constraint in variant_constraints and base_key in non_variant_bases:
                    continue
            derived.setdefault(constraint, base_key)
    return derived
