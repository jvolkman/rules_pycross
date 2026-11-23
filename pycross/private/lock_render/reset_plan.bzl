"""Variant-reset planning and `_lock/reset.bzl` rendering.

A repo's transition sets pycross's variant settings (`//_lock:_state` and the
repos' `_variants` flags). A package whose install and
whole dependency closure don't depend on them is installed with those settings
reset (`pycross_reset_wheel_library`), so every repo shares one install.
Packages that may fall back to an sdist build only reset where a wheel
matches: the build's tools can depend on the variant. Packages in cycles, with
post-install patches or a custom build target, or with variant-gated edges stay
in the caller's configuration, and so does everything that depends on them.
"""

load("@pypackaging.bzl", "pypackaging")
load("//pycross/private:build_text.bzl", "config_setting_group", "flag_setting")
load("//pycross/private:util.bzl", "base_package_key", "has_build_fallback", "is_universal_py3_wheel", "marker_evaluator_name", "parse_package_key")
load(":wheels.bzl", "resolved_wheel_candidates", "wheel_match_condition")

_VARIANT_TOKEN_PREFIX = "-variant-"  # `__variant_<qname>` after PEP 685 normalization

def variant_token(item):
    """The variant token an `extra == / != '__variant_...'` item tests, as `(token, positive)`.

    Args:
        item: Parsed marker comparison tuple `(lhs, op, rhs)`.

    Returns:
        `(token, positive)` tuple, or None if `item` does not test a variant token.
    """
    lhs, op, rhs = item
    if op not in ("==", "!="):
        return None
    if lhs.type == "variable" and lhs.value == "extra" and rhs.type == "string":
        value = rhs.value
    elif rhs.type == "variable" and rhs.value == "extra" and lhs.type == "string":
        value = lhs.value
    else:
        return None
    if not value.startswith(_VARIANT_TOKEN_PREFIX):
        return None
    return (value, op == "==")

def fold_marker(elements, conflict_pairs):
    """Folds one parenthesized level of a parsed marker.

    Args:
        elements: Items (tuples), "and"/"or", and folded child results.
        conflict_pairs: {(token, token): True} of variant tokens that are never
            active together.

    Returns:
        "T" (always true), "F" (never true), "V" (depends on a variant) or
        "N" (doesn't depend on a variant).
    """
    groups = [[]]
    for e in elements:
        if e == "or":
            groups.append([])
        elif e != "and":
            groups[-1].append(e)

    results = []
    for group in groups:
        positive = {}
        negative = {}
        result = "T"
        for e in group:
            if e in ("T", "F", "V", "N"):
                if e == "F":
                    result = "F"
                    break
                if e == "V" or (e == "N" and result == "T"):
                    result = e
                continue
            token = variant_token(e)
            if token:
                (positive if token[1] else negative)[token[0]] = True
                result = "V"
            elif result == "T":
                result = "N"
        if result != "F":
            for token in positive:
                if token in negative:
                    result = "F"
                    break
                for other in positive:
                    if (token, other) in conflict_pairs:
                        result = "F"
                        break
                if result == "F":
                    break
        results.append(result)

    if "T" in results:
        return "T"
    kept = [r for r in results if r != "F"]
    if not kept:
        return "F"
    return "V" if "V" in kept else "N"

def marker_depends_on_variants(marker, conflict_pairs):
    """Whether a marker's value can depend on the selected variants.

    Clauses that require two items of one conflict set (which uv emits, e.g.
    `extra == 'group-5-app-a-test' and extra == 'group-5-app-b-test'`) can never
    be true, so they don't count.

    Args:
        marker: PEP 508 marker expression string.
        conflict_pairs: `{(token, token): True}` of mutually exclusive variant tokens.

    Returns:
        True if the marker's result can vary with the selected variants.
    """
    if "__variant_" not in marker:
        return False
    tree = pypackaging.markers.parse(marker)
    stack = [[tree, 0, []]]
    for _ in range(1 << 20):
        frame = stack[-1]
        node = frame[0]
        if frame[1] < len(node):
            element = node[frame[1]]
            frame[1] += 1
            if type(element) == "list":
                stack.append([element, 0, []])
            else:
                frame[2].append(element)
            continue
        stack.pop()
        folded = fold_marker(frame[2], conflict_pairs) if frame[2] else "T"
        if not stack:
            return folded == "V"
        stack[-1][2].append(folded)
    fail("marker too deeply nested: " + marker)

def compute_reset_plan(packages, repo_map, conflict_pairs, gate_lines, loads = None):
    """Decides which packages install with reset variant settings, and their gates.

    Args:
        packages: The lock's packages.
        repo_map: File key -> label.
        conflict_pairs: {(token, token): True} (see fold_marker).
        gate_lines: Output lines for the gate config_setting(_group)s.
        loads: Optional dict tracking emitted helper loads (`"selects"`, `"wheel_matched"`).

    Returns:
        {pkg_key: struct(ok, gate)}. `gate` is a label that must match for the
        reset to apply (None means always).
    """
    plan = {}
    nomatch = {}  # marker evaluator names that need an `_nomatch` config_setting
    edge_gates = {}  # (eval_name, dep_key) -> label, shared across packages

    def group(name, kind, labels):
        gate_lines.extend(config_setting_group(name, kind, labels, indent = 1))
        if loads != None:
            loads["selects"] = True
        return ":" + name

    def compute(key):
        no = struct(ok = False, gate = None)
        pkg = packages[key]
        parts = parse_package_key(key)
        resolved = resolved_wheel_candidates(pkg, repo_map)
        is_extras_proxy = not pkg.get("wheel_candidates") and parts.extra
        if pkg.get("cycle_group") or pkg.get("post_install_patches") or pkg.get("build_target"):
            return no
        base = None
        if is_extras_proxy:
            base = plan.get(base_package_key(key))
            if not base or not base.ok:
                return no
        elif not resolved:
            return no

        deps = pkg.get("marker_dependencies", [])
        for md in deps:
            if md.get("marker") and marker_depends_on_variants(md["marker"], conflict_pairs):
                return no
            dep = plan.get(md["key"])
            if not dep or not dep.ok:
                if not md.get("marker"):
                    return no

        items = []
        if is_extras_proxy:
            if base.gate:
                items.append(base.gate)
        elif pkg.get("sdist_file") and pkg["sdist_file"].get("key") and has_build_fallback(pkg):
            all_resolved = len(resolved) == len(pkg.get("wheel_candidates", []))
            if not (all_resolved and any([is_universal_py3_wheel(c["filename"]) for c in resolved])):
                items.append(wheel_match_condition(
                    gate_lines,
                    key,
                    [c["filename"] for c in resolved],
                    all_resolved,
                    "_reset_wheel_" + key,
                    require_target = False,
                    loads = loads,
                ))

        for md in deps:
            dep = plan.get(md["key"])
            if not dep or not dep.ok:
                # Conditional non-variant edge to a non-resettable dep: safe to
                # reset whenever the marker does not match.
                effective_extra = parts.extra if "extra" in md["marker"] else ""
                eval_name = marker_evaluator_name(md["marker"], effective_extra)
                nomatch[eval_name] = True
                items.append(":{}_nomatch".format(eval_name))
                continue
            if not dep.gate:
                continue
            if not md.get("marker"):
                items.append(dep.gate)
                continue

            # A conditional edge only needs the dep's gate where the edge applies.
            effective_extra = parts.extra if "extra" in md["marker"] else ""
            eval_name = marker_evaluator_name(md["marker"], effective_extra)
            nomatch[eval_name] = True
            edge_key = (eval_name, md["key"])
            if edge_key not in edge_gates:
                edge_gates[edge_key] = group(
                    "_reset_edge_{}_{}".format(eval_name, md["key"]),
                    "match_any",
                    [":{}_nomatch".format(eval_name), dep.gate],
                )
            items.append(edge_gates[edge_key])

        items = {i: True for i in items}.keys()
        if not items:
            return struct(ok = True, gate = None)
        if len(items) == 1:
            return struct(ok = True, gate = items[0])
        return struct(ok = True, gate = group("_reset_ok_" + key, "match_all", items))

    for root in sorted(packages.keys()):
        if root in plan:
            continue
        stack = [(root, False)]
        visiting = {}
        for _ in range(1 << 20):
            if not stack:
                break
            key, expanded = stack.pop()
            if key in plan:
                continue
            if key not in packages:
                plan[key] = struct(ok = False, gate = None)
                continue
            if expanded:
                plan[key] = compute(key)
                continue
            if key in visiting:
                continue
            visiting[key] = True
            stack.append((key, True))
            parts = parse_package_key(key)
            if not packages[key].get("wheel_candidates") and parts.extra:
                stack.append((base_package_key(key), False))
            for md in packages[key].get("marker_dependencies", []):
                if md["key"] not in plan and md["key"] not in visiting:
                    stack.append((md["key"], False))

    for eval_name in sorted(nomatch):
        gate_lines.extend(flag_setting("{}_nomatch".format(eval_name), ":" + eval_name, "false", indent = 1, use_native = True))
    return plan

def conflict_pairs(conflict_sets):
    """Build `{(token_a, token_b): True}` of mutually exclusive normalized variant tokens.

    Args:
        conflict_sets: Iterable of lists of variant qualified names.

    Returns:
        Dict of incompatible normalized variant token pairs.
    """
    tokens = [
        [pypackaging.utils.canonicalize_name("__variant_" + qname) for qname in qnames]
        for qnames in conflict_sets
    ]
    pairs = {}
    for set_tokens in tokens:
        for a in set_tokens:
            for b in set_tokens:
                if a != b:
                    pairs[(a, b)] = True
    return pairs

def render_reset_bzl(flag_labels, string_flag_labels = None):
    """Renders `_lock/reset.bzl`: the variant-reset transition and rule.

    Args:
        flag_labels: Every member repo's `_variants` bool_flag labels.
        string_flag_labels: Optional list of member repos' `_variants` string_flag labels.

    Returns:
        The file content.
    """
    outputs = [(json.encode("//_lock:_state"), '""')]
    for label in sorted({label: True for label in flag_labels}.keys()):
        outputs.append((json.encode(label), "False"))
    for label in sorted({label: True for label in (string_flag_labels or [])}.keys()):
        outputs.append((json.encode(label), '""'))
    lines = [
        "# This file is generated by rules_pycross.",
        '"""Installs packages with pycross\'s variant settings reset (see resolved_lock_renderer.bzl)."""',
        "",
        'load("@rules_pycross//pycross/private:wheel_library.bzl", "make_wheel_library_rule", "pycross_wheel_library")',
        "",
        "_RESET = {",
    ] + ["    {}: {},".format(k, v) for k, v in outputs] + [
        "}",
        "",
        "def _reset_variants_impl(_settings, _attr):",
        "    return _RESET",
        "",
        "_reset_variants = transition(",
        "    implementation = _reset_variants_impl,",
        "    inputs = [],",
        "    outputs = _RESET.keys(),",
        ")",
        "",
        "pycross_reset_wheel_library = make_wheel_library_rule(cfg = _reset_variants)",
        "",
        "def pycross_resettable_wheel_library(name, reset_gate, **kwargs):",
        '    """A wheel library that installs with variant settings reset where `reset_gate` matches."""',
        "    if not reset_gate:",
        "        pycross_reset_wheel_library(name = name, **kwargs)",
        "        return",
        '    pycross_reset_wheel_library(name = "_reset_" + name, **kwargs)',
        '    pycross_wheel_library(name = "_unreset_" + name, **kwargs)',
        "    native.alias(",
        "        name = name,",
        "        actual = select({",
        '            reset_gate: ":_reset_" + name,',
        '            "//conditions:default": ":_unreset_" + name,',
        "        }),",
        "    )",
        "",
    ]
    return "\n".join(lines)
