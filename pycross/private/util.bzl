"""Shared utilities"""

load("@pypackaging.bzl", "pypackaging")
load("@rules_python//python/api:api.bzl", "py_common")

def sanitize_name(val):
    """Sanitize a string into a valid Bazel repository and target name identifier.

    Lowercases and replaces every character outside `[a-z0-9_]` with `_`.

    Args:
        val: The string to sanitize.

    Returns:
        The sanitized string.
    """
    out = []
    for c in val.lower().elems():
        if ("a" <= c and c <= "z") or ("0" <= c and c <= "9") or c == "_":
            out.append(c)
        else:
            out.append("_")
    return "".join(out)

def marker_uses_extra(marker_str):
    """Returns True if `marker_str` references the PEP 508 `extra` variable.

    Args:
        marker_str: The PEP 508 marker expression string.

    Returns:
        Bool indicating whether the marker AST references `extra`.
    """
    if not marker_str or "extra" not in marker_str:
        return False
    return "extra" in pypackaging.markers.variables(pypackaging.markers.parse(marker_str))

def marker_evaluator_name(marker_str, extra = ""):
    """Generate a deterministic target name for a PEP 508 marker evaluator.

    Args:
        marker_str: The PEP 508 marker expression.
        extra: The PEP 508 extra value (e.g. 'test'), or '' for no extra.

    Returns:
        The deterministic target name string (e.g. '_marker_eval_<san>_<hash>').
    """

    # Starlark's hash() is deterministic within a build invocation.
    # We sanitize the marker string for readability and add the hash for uniqueness.
    effective_extra = extra if (extra and marker_uses_extra(marker_str)) else ""
    key = marker_str if not effective_extra else "{}|extra={}".format(marker_str, effective_extra)
    san_chars = []
    for c in key.lower().elems():
        if c in (" ", "\"", "'"):
            continue
        if ("a" <= c and c <= "z") or ("0" <= c and c <= "9") or c == "_":
            san_chars.append(c)
        else:
            san_chars.append("_")
    san = "".join(san_chars)

    # Truncate to keep target names reasonable
    if len(san) > 40:
        san = san[:40]
    return "_marker_eval_{}_{}".format(san, hash(key))

def underscore_name(name):
    """rules_python-style normalization: lowercase, replace [-. ] with _."""
    return pypackaging.utils.canonicalize_name(name).replace("-", "_")

def extract_pep508_name(spec):
    """Extract the PEP 503 normalized package name from a PEP508 requirement line.

    Args:
        spec: The PEP508 requirement string to parse.

    Returns:
        The PEP 503 normalized package name (with hyphens) as a string.
    """
    return pypackaging.requirements.parse(spec).name

def resolution_marker_constraint_name(name, version, tag = ""):
    """Generate a deterministic constraint name for a resolution-marker fork.

    Used when a package has multiple versions (or sources at the same version)
    resolved for different environments.

    Args:
        name: Canonical package name.
        version: Package version string.
        tag: Optional disambiguating source tag (omitted when empty).

    Returns:
        A constraint name like "res_numpy_2_3_4" or "res_torch_2_9_1_a1b2c3d4".
    """
    ver = "{}_{}".format(version, tag) if tag else version
    sanitized = (name + "_" + ver).replace("-", "_").replace(".", "_").replace("+", "_").replace("~", "_")
    return "res_{}".format(sanitized)

def format_package_key(name, version = "", extra = "", tag = ""):
    """Format a package key from its components.

    Args:
        name: Canonicalized package name.
        version: Optional version string.
        extra: Optional extra name.
        tag: Optional disambiguating source tag (omitted when empty).

    Returns:
        Formatted key string such as `name@version`, `name[extra]@version`,
        or `name@version~tag`.
    """
    base = "{}[{}]".format(name, extra) if extra else name
    if not version:
        return base
    if tag:
        return "{}@{}~{}".format(base, version, tag)
    return "{}@{}".format(base, version)

def parse_package_key(key):
    """Parses a package key or pin name into `(name, extra, version, tag)`.

    Supports formats:
      - name@version
      - name@version~tag
      - name[extra]@version
      - name[extra]@version~tag
      - name
      - name[extra]

    Args:
        key: The package key or pin name string.

    Returns:
        A struct of `(name, extra, version, tag)`. `name` is always present;
        `extra`, `version`, and `tag` are strings and empty when absent.
    """
    name_and_extra = key
    version = ""
    tag = ""
    if "@" in key:
        parts = key.split("@", 1)
        name_and_extra = parts[0]
        version = parts[1]
        if "~" in version:
            ver_parts = version.split("~", 1)
            version = ver_parts[0]
            tag = ver_parts[1]

    name = name_and_extra
    extra = ""
    if "[" in name_and_extra:
        if not name_and_extra.endswith("]"):
            fail("Invalid package key format: " + key)
        parts = name_and_extra.split("[", 1)
        name = parts[0]
        extra = parts[1][:-1]

    return struct(
        name = name,
        extra = extra,
        version = version,
        tag = tag,
    )

def base_package_key(pkg_key):
    """Return the base `name@version[~tag]` key for a package key (stripping any `[extra]`).

    Args:
        pkg_key: Package key string (e.g. `foo[bar]@1.0`, `foo[bar]@1.0~abcd1234`).

    Returns:
        Base package key string `name@version` or `name@version~tag`.
    """
    parts = parse_package_key(pkg_key)
    return format_package_key(parts.name, parts.version, tag = parts.tag)

def base_packages_with_extras(packages):
    """Group extra package keys in `packages` by their base `name@version[~tag]` key.

    Args:
        packages: Lock packages dict keyed by package key.

    Returns:
        Dict mapping base package key -> list of extra package keys.
    """
    result = {}
    for pkg_key in packages.keys():
        parts = parse_package_key(pkg_key)
        if not parts.extra:
            continue
        result.setdefault(base_package_key(pkg_key), []).append(pkg_key)
    return result

def sdist_builds_disallowed(pkg):
    """Whether build_mode = "never" forbids building this resolved package's sdist.

    A user-supplied build_target is exempt: it replaces the sdist build entirely.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if the package's sdist must not be built.
    """
    return pkg.get("build_mode") == "never" and not pkg.get("build_target")

def has_build_fallback(pkg):
    """Whether a resolved package can be built from source when no wheel matches.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if the package has a build_target, or an sdist that may be built.
    """
    if pkg.get("build_target"):
        return True
    return bool(pkg.get("sdist_file")) and not sdist_builds_disallowed(pkg)

def is_universal_py3_wheel(filename):
    """Return True if filename is a wheel containing the universal `py3-none-any` tag.

    A `py3-none-any` (or compressed `py2.py3-none-any`, etc.) wheel matches
    every Python 3 target platform unconditionally.

    Args:
        filename: Candidate wheel filename.

    Returns:
        True if the wheel contains the `py3-none-any` tag, False otherwise.
    """
    if not filename.lower().endswith(".whl"):
        return False
    parts = filename[:-4].split("-")
    if len(parts) not in (5, 6):
        return False
    py_tag, abi_tag, plat_tag = parts[-3].lower(), parts[-2].lower(), parts[-1].lower()
    return (
        "py3" in py_tag.split(".") and
        "none" in abi_tag.split(".") and
        "any" in plat_tag.split(".")
    )

def is_wheel_platform_specific(pkg):
    """Whether a resolved package's wheel selection alone can fail on some target platforms.

    True when the package has wheel candidates, no sdist/build_target fallback,
    and no universal py3-none-any candidate.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if wheel selection may fail on some target platform.
    """
    candidates = pkg.get("wheel_candidates", [])
    if not candidates or has_build_fallback(pkg):
        return False
    return not any([is_universal_py3_wheel(c["filename"]) for c in candidates])

def is_platform_specific(pkg):
    """Whether a resolved package may be unavailable in some target environments.

    Args:
        pkg: A resolved package dict.

    Returns:
        True if the package may be unavailable on some target platform.
    """
    if pkg.get("availability_markers"):
        return True
    return is_wheel_platform_specific(pkg)

def variant_item_qname(item):
    """Return the internal name for a variant item.

    Names are package-qualified (e.g. `extra_my-app_cpu`, `package_my-app`) so they're unique
    across a workspace lock. Users don't see these: each generated repo has its own
    `_variants` flags (the item's `flag`, e.g. `extra_cpu`).
    """
    if item["kind"] == "project":
        return "package_{}".format(item["package"])
    return "{}_{}_{}".format(item["kind"], item["package"], item["name"])

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
        if (k.startswith("u:") and v == "*") or (not k.startswith("u:") and not v):
            merged.pop(k, None)
        else:
            merged[k] = v
    if not merged:
        return ""
    return json.encode({k: merged[k] for k in sorted(merged.keys())})

def coerce_transition_values(current, values):
    """Coerce raw repo transition values to the type of a setting's current value.

    Args:
        current: The setting's current value (determines the type).
        values: Raw string values, in order.

    Returns:
        All values for list settings; otherwise the last value as a bool, int or string.
    """
    t = type(current)
    if t == "list":
        return values
    value = values[-1]
    if t == "bool":
        if value in ("True", "true", "1"):
            return True
        if value in ("False", "false", "0"):
            return False
        fail("Invalid boolean flag value: %r" % value)
    if t == "int":
        return int(value)
    return value

def split_setting_value(current, value):
    """Split a repo `settings` value like the command line: on commas for list settings.

    Args:
        current: The setting's current value (determines the type).
        value: The raw string value.

    Returns:
        A list of raw values for coerce_transition_values.
    """
    if type(current) == "list":
        return value.split(",") if value else []
    return [value]

# Attrs that consuming rules must include for merge_py_providers to work.
PY_COMMON_ATTRS = py_common.API_ATTRS

def merge_py_providers(
        ctx,
        deps,
        direct_sources = [],
        direct_imports = [],
        base_runfiles = None,
        direct_venv_symlinks = [],
        has_py2_only_sources = False,
        has_py3_only_sources = False,
        uses_shared_libraries = True):
    """Merges PyInfo and DefaultInfo from deps with optional direct entries.

    Uses rules_python's PyInfoBuilder to ensure all PyInfo fields (including
    pyc files, pyi stubs, and venv symlinks) are properly merged.

    The consuming rule must include PY_COMMON_ATTRS in its attrs dict.

    Args:
        ctx: The rule context (must have PY_COMMON_ATTRS in its rule attrs).
        deps: List of Target objects providing PyInfo and DefaultInfo.
        direct_sources: Files to add as direct entries to transitive_sources.
        direct_imports: Strings to add as direct entries to imports.
        base_runfiles: A Runfiles object (e.g. from ctx.runfiles) to merge with dep runfiles.
        direct_venv_symlinks: VenvSymlinkEntry values to add directly.
        has_py2_only_sources: Whether this target has PY2-only sources.
        has_py3_only_sources: Whether this target has PY3-only sources.
        uses_shared_libraries: Whether to set uses_shared_libraries on PyInfo.

    Returns:
        A struct with fields:
          - py_info: A PyInfo provider.
          - runfiles: The merged Runfiles object.
    """
    api = py_common.get(ctx)
    builder = api.PyInfoBuilder()

    # Merge all dep PyInfos as transitive.
    builder.merge_targets(deps)

    # Add our own direct content.
    builder.transitive_sources.add(direct_sources)
    builder.imports.add(direct_imports)
    if direct_venv_symlinks:
        builder.venv_symlinks.add(direct_venv_symlinks)

    if has_py2_only_sources:
        builder.set_has_py2_only_sources(True)
    if has_py3_only_sources:
        builder.set_has_py3_only_sources(True)
    if uses_shared_libraries:
        builder.set_uses_shared_libraries(True)

    py_info = builder.build()

    # Merge runfiles from all deps in a single merge_all call.
    dep_runfiles = [
        dep[DefaultInfo].default_runfiles
        for dep in deps
        if dep[DefaultInfo].default_runfiles
    ]
    if base_runfiles != None:
        runfiles = base_runfiles.merge_all(dep_runfiles) if dep_runfiles else base_runfiles
    elif not dep_runfiles:
        runfiles = None
    elif len(dep_runfiles) == 1:
        runfiles = dep_runfiles[0]
    else:
        runfiles = dep_runfiles[0].merge_all(dep_runfiles[1:])

    return struct(
        py_info = py_info,
        runfiles = runfiles,
    )

# Mapping of common URL percent-encoded characters.
_URL_HEX_MAP = {
    "20": " ",
    "21": "!",
    "23": "#",
    "24": "$",
    "25": "%",
    "26": "&",
    "27": "'",
    "28": "(",
    "29": ")",
    "2B": "+",
    "2C": ",",
    "2D": "-",
    "2E": ".",
    "2F": "/",
    "3A": ":",
    "3B": ";",
    "3D": "=",
    "3F": "?",
    "40": "@",
    "5B": "[",
    "5D": "]",
    "5F": "_",
    "7E": "~",
}

def url_decode_filename(filename):
    """Decode percent-encoded characters in a URL-derived filename.

    Args:
        filename: A filename string potentially containing %XX sequences.

    Returns:
        The decoded filename string.
    """
    if "%" not in filename:
        return filename
    parts = []
    i = 0
    n = len(filename)
    for _ in range(n):
        if i >= n:
            break
        if filename[i] == "%" and i + 2 < n:
            hex_str = filename[i + 1:i + 3].upper()
            replacement = _URL_HEX_MAP.get(hex_str)
            if replacement:
                parts.append(replacement)
                i += 3
                continue
        parts.append(filename[i])
        i += 1
    return "".join(parts)

def url_filename(url):
    """Extract and percent-decode the filename component from a URL."""
    path_part = url.split("#", 1)[0].split("?", 1)[0]
    return url_decode_filename(path_part.split("/")[-1])
