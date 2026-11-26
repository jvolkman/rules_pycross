"""PEP 508 dependency and resolution-marker evaluator rendering for `_lock/lock.bzl`."""

load("//pycross/private:build_text.bzl", "config_setting_group", "flag_setting")
load("//pycross/private:lock_contract.bzl", "constraint_setting_name", "marker_match_target_name")
load("//pycross/private:util.bzl", "marker_evaluator_name", "marker_uses_extra", "parse_package_key")
load("//pycross/private:variant_util.bzl", "marker_mentions_variant")
load(":common.bzl", "ind")

def format_variants_attr(resolvers):
    """Format a `variants = [...]` attribute line for evaluator and cycle targets.

    Args:
        resolvers: Non-empty iterable of variant_resolver target labels.

    Returns:
        Attribute string `variants = ["...", ...],`.
    """
    return "variants = [{}],".format(", ".join([json.encode(r) for r in resolvers]))

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

def matching_variant_resolvers(markers, variant_resolvers):
    """Return the subset of variant_resolvers referenced by markers.

    Args:
        markers: Iterable of PEP 508 marker strings.
        variant_resolvers: Either a list of resolver target labels (all returned
            when any marker references `__variant_`) or a dict mapping
            resolver target label -> list of item qualified names.

    Returns:
        List of matching resolver target labels.
    """
    if not variant_resolvers:
        return []
    variant_markers = [m for m in markers if m and "__variant_" in m]
    if not variant_markers:
        return []
    if type(variant_resolvers) != "dict":
        return variant_resolvers

    matched = []
    for label, qnames in sorted(variant_resolvers.items()):
        found = False
        for q in qnames:
            for m in variant_markers:
                if marker_mentions_variant(m, q):
                    found = True
                    break
            if found:
                break
        if found:
            matched.append(label)
    return matched if matched else sorted(variant_resolvers.keys())

def _render_evaluator_and_setting(lines, eval_name, expr, setting_name, extra = None, resolvers = None):
    """Append a `pycross_pep508_evaluator` and its matching `native.config_setting`."""
    lines.extend([
        ind("pycross_pep508_evaluator("),
        ind("name = {},".format(json.encode(eval_name)), 2),
        ind("expr = {},".format(json.encode(expr)), 2),
    ])
    if extra:
        lines.append(ind("extra = {},".format(json.encode(extra)), 2))
    if resolvers:
        lines.append(ind(format_variants_attr(resolvers), 2))
    lines.extend([
        ind(")"),
        "",
    ])
    lines.extend(flag_setting(setting_name, ":" + eval_name, "true", indent = 1, use_native = True))

def render_marker_evaluators(lines, unique_markers, variant_resolvers = None):
    """Render deduped pycross_pep508_evaluator and config_setting targets.

    Args:
        lines: Output lines list.
        unique_markers: Iterable of (marker_str, extra) tuples.
        variant_resolvers: Optional list of variant_resolver target labels, or
            dict mapping resolver label -> list of item qualified names.
    """
    for marker_str, extra in sorted(unique_markers):
        eval_name = marker_evaluator_name(marker_str, extra)
        resolvers = matching_variant_resolvers([marker_str], variant_resolvers)
        _render_evaluator_and_setting(
            lines,
            eval_name,
            marker_str,
            marker_match_target_name(eval_name),
            extra = extra,
            resolvers = resolvers,
        )

def render_resolution_marker_evaluators(lines, resolution_marker_exprs, variant_resolvers = None, loads = None):
    """Render pycross_pep508_evaluator + config_setting for resolution-marker forks.

    Entries in ``resolution_marker_exprs`` are either:
    - A string (simple fork): generates an evaluator + config_setting.
    - A dict with ``variant`` and ``marker`` keys (compound fork): generates a
      config_setting_group that matches both the variant and the marker.

    Args:
        lines: Output lines list.
        resolution_marker_exprs: Dict mapping constraint_name to either a
            PEP 508 marker expression string or a compound dict.
        variant_resolvers: Optional list of variant_resolver target labels, or
            dict mapping resolver label -> list of item qualified names.
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
            resolvers = matching_variant_resolvers([entry], variant_resolvers)
            _render_evaluator_and_setting(
                lines,
                eval_name,
                entry,
                constraint_setting_name(constraint_name),
                resolvers = resolvers,
            )
