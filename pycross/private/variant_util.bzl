"""UV conflict-variant naming, marker-folding, and `//_lock:_state` codec helpers."""

load("@pypackaging.bzl", "pypackaging")
load(":lock_contract.bzl", "VARIANT_STATE_USABLE_PREFIX")

def variant_item_qname(item):
    """Return the internal name for a variant item.

    Names are package-qualified (e.g. `extra_my-app_cpu`, `package_my-app`) so they're unique
    across a workspace lock. Users don't see these: each generated repo has its own
    `_variants` flags (the item's `flag`, e.g. `extra_cpu`).
    """
    if item["kind"] == "project":
        return "package_{}".format(item["package"])
    return "{}_{}_{}".format(item["kind"], item["package"], item["name"])

def variant_set_suffix(qnames):
    """Return the canonical conflict set suffix (`_`-joined sorted qnames)."""
    return "_".join(sorted(qnames))

def split_variant_tokens(value):
    """Split a comma-separated `//_variants` string flag value into non-empty stripped tokens."""
    if not value:
        return []
    return [t.strip() for t in value.split(",") if t.strip()]

def excluded_variant_items(conflict_sets, selected):
    """Return `{qname: True}` for every variant item conflicting with an item in `selected`.

    Two distinct items conflict when they appear together in at least one set in
    `conflict_sets`.

    Args:
        conflict_sets: Iterable of lists of variant item qnames (one list per
            conflict set).
        selected: Iterable (list or dict) of selected variant item qnames.

    Returns:
        Dict `{qname: True}` of every item that conflicts with at least one item
        in `selected`.
    """
    excluded = {}
    for qnames in conflict_sets:
        for qname in selected:
            if qname not in qnames:
                continue
            for other in qnames:
                if other != qname:
                    excluded[other] = True
    return excluded

_VARIANT_TOKEN_PREFIX = "-variant-"  # `__variant_<qname>` after PEP 685 normalization

def marker_mentions_variant(marker, qname):
    """Return True if `marker` contains a quoted `__variant_<qname>` token.

    Args:
        marker: PEP 508 marker string (may be `""`).
        qname: Variant item qualified name.

    Returns:
        Bool indicating whether `'__variant_<qname>'` or `"__variant_<qname>"` appears in `marker`.
    """
    if not marker:
        return False
    tok = "__variant_{}".format(qname)
    return "'{}'".format(tok) in marker or '"{}"'.format(tok) in marker

def _extract_variant_token(item):
    """Return `(normalized_token, is_positive)` for an `extra ==/!= '__variant_...'` item, or None.

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

def variant_conflict_pairs(conflict_sets):
    """Build `{(token_a, token_b): True}` of mutually exclusive normalized variant tokens.

    Args:
        conflict_sets: Iterable of lists of variant qualified names.

    Returns:
        Dict of incompatible normalized variant token pairs.
    """
    pairs = {}
    for qnames in conflict_sets:
        norm = [pypackaging.utils.canonicalize_name("__variant_" + q) for q in qnames]
        for a in norm:
            for b in norm:
                if a != b:
                    pairs[(a, b)] = True
    return pairs

def _fold_variant_level(elements, true_tokens, false_tokens, conflict_pairs):
    """Fold one parenthesized marker level into `"T"`, `"F"`, `"V"`, or `"N"`."""
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
            tok = _extract_variant_token(e)
            if not tok:
                if result == "T":
                    result = "N"
                continue
            token, is_pos = tok
            if token in true_tokens:
                if not is_pos:
                    result = "F"
                    break
                continue
            if token in false_tokens:
                if is_pos:
                    result = "F"
                    break
                continue
            (positive if is_pos else negative)[token] = True
            result = "V"

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

def fold_variant_marker(marker, conflict_pairs = None, active_qnames = (), conflict_sets = None):
    """Fold a PEP 508 marker over uv conflict variant tokens into `"T"`, `"F"`, `"V"`, or `"N"`.

    Evaluates `__variant_<qname>` comparisons under optional fixed variant
    selections (`active_qnames` and their rivals in `conflict_sets`) and folds
    contradictions from `conflict_pairs`/`conflict_sets`.

    Args:
        marker: PEP 508 marker string (with uv conflict tokens rewritten to
            `__variant_<qname>`).
        conflict_pairs: Optional precomputed `{(token_a, token_b): True}` from
            `variant_conflict_pairs`. Computed from `conflict_sets` if omitted.
        active_qnames: Optional iterable of variant qualified names assumed
            active simultaneously.
        conflict_sets: Optional iterable of lists of variant qualified names
            (used to derive rivals of `active_qnames`, and `conflict_pairs` when
            not provided).

    Returns:
        - `"T"` if always true under the given assumptions.
        - `"F"` if unsatisfiable.
        - `"V"` if the result can still vary with an unfixed variant token.
        - `"N"` if the result depends only on non-variant environment values.
    """
    if not marker:
        return "T"
    marker_lower = marker.lower()
    if "__variant_" not in marker_lower and _VARIANT_TOKEN_PREFIX not in marker_lower:
        return "N"

    true_tokens = {}
    false_tokens = {}
    active = [q for q in active_qnames if q]
    if active:
        for q in active:
            true_tokens[pypackaging.utils.canonicalize_name("__variant_" + q)] = True
        for rival in excluded_variant_items(conflict_sets or [], active).keys():
            false_tokens[pypackaging.utils.canonicalize_name("__variant_" + rival)] = True
        for token in true_tokens:
            if token in false_tokens:
                return "F"

    pairs = conflict_pairs if conflict_pairs != None else variant_conflict_pairs(conflict_sets or [])

    tree = pypackaging.markers.parse(marker)
    stack = [[tree, 0, []]]
    for _ in range(2 * len(marker) + 1):
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
        if stack and frame[2] and "or" not in frame[2]:
            # Flatten parenthesized conjunctions (e.g. `(A) and (B)` emitted by
            # combine_markers) so variant tokens are checked together.
            stack[-1][2].extend(frame[2])
            continue
        folded = _fold_variant_level(frame[2], true_tokens, false_tokens, pairs) if frame[2] else "T"
        if not stack:
            return folded
        stack[-1][2].append(folded)
    fail("fold_variant_marker exceeded step bound: " + marker)

def decode_variant_state(raw):
    """Decode a canonical `//_lock:_state` JSON string into a dict of overrides.

    Keys are `"p:<set>"` (pin), `"d:<set>"` (default), and `"u:<set>"` (usable
    items space-separated, `""` for none; absent means `"*"`, i.e. all usable).

    Args:
        raw: Canonical JSON string from `//_lock:_state`, or `""`.

    Returns:
        Dict of `{key: value}`.
    """
    if not raw:
        return {}
    return json.decode(raw)

def merge_variant_state(current_raw, overrides):
    """Merge a repo transition's owned variant-state keys over incoming `_state`.

    Unset keys in `overrides` pass through untouched from `current_raw` so
    downstream repos (such as `<ws>__build` with its own flags or defaults)
    inherit upstream pins. Default values (`""` for `p:`/`d:`, `"*"` for `u:`)
    are omitted and keys are sorted so identical effective states always encode
    to the same canonical string for Bazel configuration deduplication.

    Args:
        current_raw: Incoming `//_lock:_state` string (may be `""`).
        overrides: Dict `{key: value}` owned by the transitioning repo.

    Returns:
        Canonical encoded `//_lock:_state` string (`""` when empty).
    """
    merged = dict(decode_variant_state(current_raw))
    for k, v in overrides.items():
        if (k.startswith(VARIANT_STATE_USABLE_PREFIX) and v == "*") or (not k.startswith(VARIANT_STATE_USABLE_PREFIX) and not v):
            merged.pop(k, None)
        else:
            merged[k] = v
    if not merged:
        return ""
    return json.encode({k: merged[k] for k in sorted(merged.keys())})
