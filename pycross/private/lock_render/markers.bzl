"""PEP 508 dependency and resolution-marker evaluator rendering for `_lock/lock.bzl`."""

load("//pycross/private:build_text.bzl", "config_setting_group", "flag_setting")
load("//pycross/private:lock_contract.bzl", "constraint_setting_name", "marker_match_target_name")
load("//pycross/private:util.bzl", "marker_evaluator_name", "marker_uses_extra", "parse_package_key")
load(":common.bzl", "ind")

VARIANT_STATE_ATTR = 'variants = [":_variant_state"],'

def collect_unique_markers(packages):
    """Collect all unique `(marker, extra)` pairs across packages.

    The extra is derived from the package key (e.g. `'foo[test]@1.0'` -> `'test'`).

    Args:
        packages: Lock packages dict keyed by package key.

    Returns:
        List of unique `(marker_string, extra_value)` tuples.
    """
    markers = {}
    for pkg_key, pkg in packages.items():
        extra = parse_package_key(pkg_key).extra
        for md in pkg.get("marker_dependencies", []):
            marker = md.get("marker")
            if not marker:
                continue

            # Optimization: if the marker doesn't reference `extra`, share a
            # single evaluator by setting extra to "".
            effective_extra = extra if (extra and marker_uses_extra(marker)) else ""
            markers[(marker, effective_extra)] = True

        # Availability markers come from root project dependency edges, which
        # never reference `extra`, so they share the extra-free evaluators.
        for marker in pkg.get("availability_markers", []):
            markers[(marker, "")] = True
    return markers.keys()

def _render_evaluator_and_setting(lines, eval_name, expr, setting_name, extra = None, has_variants = False):
    """Append a `pycross_pep508_evaluator` and its matching `native.config_setting`."""
    lines.extend([
        ind("pycross_pep508_evaluator("),
        ind("name = {},".format(json.encode(eval_name)), 2),
        ind("expr = {},".format(json.encode(expr)), 2),
    ])
    if extra:
        lines.append(ind("extra = {},".format(json.encode(extra)), 2))
    if has_variants and expr and "__variant_" in expr:
        lines.append(ind(VARIANT_STATE_ATTR, 2))
    lines.extend([
        ind(")"),
        "",
    ])
    lines.extend(flag_setting(setting_name, ":" + eval_name, "true", indent = 1, use_native = True))

def render_marker_evaluators(lines, unique_markers, has_variants = False):
    """Render deduped pycross_pep508_evaluator and config_setting targets.

    Args:
        lines: Output lines list.
        unique_markers: Iterable of (marker_str, extra) tuples.
        has_variants: Whether the workspace defines a `:_variant_state` target.
    """
    for marker_str, extra in sorted(unique_markers):
        eval_name = marker_evaluator_name(marker_str, extra)
        _render_evaluator_and_setting(
            lines,
            eval_name,
            marker_str,
            marker_match_target_name(eval_name),
            extra = extra,
            has_variants = has_variants,
        )

def render_resolution_marker_evaluators(lines, resolution_marker_exprs, has_variants = False, loads = None):
    """Render pycross_pep508_evaluator + config_setting for resolution-marker forks.

    Entries in ``resolution_marker_exprs`` are either:
    - A string (simple fork): generates an evaluator + config_setting.
    - A dict with ``variant`` and ``marker`` keys (compound fork): generates a
      config_setting_group that matches both the variant and the marker.

    Args:
        lines: Output lines list.
        resolution_marker_exprs: Dict mapping constraint_name to either a
            PEP 508 marker expression string or a compound dict.
        has_variants: Whether the workspace defines a `:_variant_state` target.
        loads: Optional dict tracking emitted helper loads (`"selects"`).
    """
    for constraint_name, entry in sorted(resolution_marker_exprs.items()):
        if type(entry) == "dict":
            # Compound constraint: combine variant + marker config_settings.
            # Both is_<variant> and is_<marker> must already exist.
            lines.extend(config_setting_group(
                constraint_setting_name(constraint_name),
                "match_all",
                [constraint_setting_name(entry["variant"]), constraint_setting_name(entry["marker"])],
                indent = 1,
            ))
            if loads != None:
                loads["selects"] = True
        else:
            eval_name = "_res_eval_{}".format(constraint_name)
            _render_evaluator_and_setting(
                lines,
                eval_name,
                entry,
                constraint_setting_name(constraint_name),
                has_variants = has_variants,
            )
