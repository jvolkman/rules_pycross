"""UV conflict sets, variant pins/defaults, and conflict-aware pin resolution.

Handles UV's `[[conflicts]]` declarations: rewriting uv's encoded `extra == ...`
conflict tokens to internal `__variant_<qname>` tokens, computing per-repo
`_variants` flags / `repo_pin` / `repo_default`, folding edge markers during
local-member expansion, and resolving surviving edges into conditional pins.
"""

load(
    ":translator_util.bzl",
    "canonicalize_name",
    "record_edge_testonly",
    "record_root_marker",
)
load(
    ":util.bzl",
    "parse_package_key",
    "resolution_marker_constraint_name",
    "sanitize_name",
)
load(
    ":variant_util.bzl",
    "excluded_variant_items",
    "fold_variant_marker",
    "marker_mentions_variant",
    "variant_active_tokens",
    "variant_conflict_pairs",
    "variant_item_qname",
)

def _uv_conflict_token(item):
    """Return the uv-encoded conflict marker token for a conflict item."""
    kind = item["kind"]
    pkg = canonicalize_name(item["package"])
    name = item.get("name", "")
    if kind == "extra":
        return "extra-{}-{}-{}".format(len(pkg), pkg, canonicalize_name(name))
    if kind == "group":
        return "group-{}-{}-{}".format(len(pkg), pkg, canonicalize_name(name))
    if kind == "project":
        return "project-{}-{}".format(len(pkg), pkg)
    fail("Unknown conflict item kind: {}".format(kind))

def canonicalize_group_key(key):
    """Normalize the name in a requested group key (`optional:<name>`, `group:<name>`).

    Args:
        key: Group key string such as `"default"`, `"optional:My_Extra"`, or `"group:Dev"`.

    Returns:
        Group key string with the suffix canonicalized per PEP 503.
    """
    kind, sep, name = key.partition(":")
    if not sep:
        return key
    return "{}:{}".format(kind, canonicalize_name(name))

def _is_item_requested(item, requested_keys):
    """Whether a repo requests a conflict item of one of its projects."""
    kind = item["kind"]
    if kind == "project":
        # A project variant gates all of the project's edges.
        return bool(requested_keys)
    if kind == "extra":
        return "optional:" + item["name"] in requested_keys
    return "group:" + item["name"] in requested_keys

def rewrite_conflict_markers(marker, token_replacements):
    """Rewrite uv conflict marker tokens in `marker` into `__variant_<qname>`.

    Args:
        marker: PEP 508 marker string (may be `""`).
        token_replacements: Sequence of `(old_quoted, new_quoted)` string pairs.

    Returns:
        Marker string with all matching conflict tokens rewritten.
    """
    if not marker or not token_replacements or "extra" not in marker:
        return marker
    for old_quoted, new_quoted in token_replacements:
        if old_quoted in marker:
            marker = marker.replace(old_quoted, new_quoted)
    return marker

def parse_uv_conflicts_base(uv_conflicts):
    """Parse workspace-invariant UV `conflicts` structures once per lockfile.

    Args:
        uv_conflicts: List of conflict sets from `uv.lock["conflicts"]`.

    Returns:
        Struct with `base_variant_sets`, `base_items_by_key`,
        `extra_variant_values`, `group_variant_values`, `project_variant_values`,
        `token_replacements`, `set_qnames`, and `conflict_pairs`.
    """
    base_items_by_key = {}  # (package, kind, name) -> base variant item dict
    base_variant_sets = []
    for variant_list in uv_conflicts:
        items = []
        for c in variant_list:
            package = canonicalize_name(c["package"])
            if "extra" in c:
                kind, vname = "extra", canonicalize_name(c["extra"])
            elif "group" in c:
                kind, vname = "group", canonicalize_name(c["group"])
            else:
                kind, vname = "project", ""
            key = (package, kind, vname)
            if key not in base_items_by_key:
                item = {"package": package, "kind": kind}
                if vname:
                    item["name"] = vname
                base_items_by_key[key] = item
            items.append(base_items_by_key[key])
        base_variant_sets.append({"items": items})

    # Build constraint lookups keyed by (package, name) so a conflict declared
    # on one project's extra/group doesn't apply to a same-named extra/group of
    # another project.
    extra_variant_values = {}
    group_variant_values = {}
    project_variant_values = {}
    token_replacements = []
    for item in base_items_by_key.values():
        kind = item["kind"]
        vname = item.get("name", "")
        qualified = variant_item_qname(item)
        if kind == "extra":
            extra_variant_values[(item["package"], vname)] = qualified
        elif kind == "group":
            group_variant_values[(item["package"], vname)] = qualified
        elif kind == "project":
            project_variant_values[item["package"]] = qualified

        uv_tok = _uv_conflict_token(item)
        var_tok = "__variant_{}".format(qualified)
        token_replacements.append(("'{}'".format(uv_tok), "'{}'".format(var_tok)))
        token_replacements.append(('"{}"'.format(uv_tok), '"{}"'.format(var_tok)))

    set_qnames = [[variant_item_qname(item) for item in vs["items"]] for vs in base_variant_sets]
    conflict_pairs = variant_conflict_pairs(set_qnames)
    return struct(
        base_variant_sets = base_variant_sets,
        base_items_by_key = base_items_by_key,
        extra_variant_values = extra_variant_values,
        group_variant_values = group_variant_values,
        project_variant_values = project_variant_values,
        token_replacements = token_replacements,
        set_qnames = set_qnames,
        conflict_pairs = conflict_pairs,
    )

def instantiate_uv_conflicts(base_conflicts, target_projects):
    """Create fresh per-repo variant sets and item flags from `base_conflicts`.

    Each repo receives fresh `variant_sets` and `variant_items_by_key` dicts so
    per-repo `flags`, `repo_requested`, `repo_pin`, and `repo_default` writes do
    not leak across workspace members.

    Args:
        base_conflicts: Struct returned by `parse_uv_conflicts_base`.
        target_projects: List of canonicalized target project names for this repo.

    Returns:
        Struct with `variant_sets`, `variant_items_by_key`,
        `extra_variant_values`, `group_variant_values`, `project_variant_values`,
        `token_replacements`, `set_qnames`, and `conflict_pairs`.
    """
    target_projects_set = {p: True for p in target_projects}
    variant_items_by_key = {}
    for key, base_item in base_conflicts.base_items_by_key.items():
        item = dict(base_item)

        # User-facing `_variants` flags for this repo, for items declared by its
        # own projects (other projects' items get none):
        #   - `<kind>_<name>` (e.g. `group_test`) covers that extra/group in
        #     every project of the repo, like `uv --group test`.
        #   - `<kind>_<project>_<name>` covers one project, like
        #     `uv --package app-a --group test`.
        # Names are normalized (`-` only), so the two forms can't collide.
        if item["package"] in target_projects_set:
            kind = item["kind"]
            if kind == "project":
                item["flags"] = ["package_{}".format(item["package"])]
            else:
                vname = item.get("name", "")
                item["flags"] = [
                    "{}_{}".format(kind, vname),
                    "{}_{}_{}".format(kind, item["package"], vname),
                ]
        variant_items_by_key[key] = item

    variant_sets = [
        {
            "items": [
                variant_items_by_key[(item["package"], item["kind"], item.get("name", ""))]
                for item in vs["items"]
            ],
        }
        for vs in base_conflicts.base_variant_sets
    ]
    return struct(
        variant_sets = variant_sets,
        variant_items_by_key = variant_items_by_key,
        extra_variant_values = base_conflicts.extra_variant_values,
        group_variant_values = base_conflicts.group_variant_values,
        project_variant_values = base_conflicts.project_variant_values,
        token_replacements = base_conflicts.token_replacements,
        set_qnames = base_conflicts.set_qnames,
        conflict_pairs = base_conflicts.conflict_pairs,
    )

def parse_uv_conflicts(uv_conflicts, target_projects):
    """Parse uv `conflicts` declarations into variant sets, lookups, and rewrite rules.

    Args:
        uv_conflicts: List of conflict sets from `uv.lock["conflicts"]`.
        target_projects: List of canonicalized target project names for this repo.

    Returns:
        Struct with `variant_sets`, `variant_items_by_key`,
        `extra_variant_values`, `group_variant_values`, `project_variant_values`,
        `token_replacements`, `set_qnames`, and `conflict_pairs`.
    """
    return instantiate_uv_conflicts(parse_uv_conflicts_base(uv_conflicts), target_projects)

def apply_repo_variant_pins_and_defaults(
        conflicts,
        target_projects,
        requested_by_project,
        default_owner,
        uv_default_groups,
        is_build_tools_repo):
    """Annotate `conflicts.variant_sets` with `repo_requested`, `repo_pin`, and `repo_default`.

    In uv, extras and groups are active only when requested. A `{package = ...}`
    project variant gates all of that project's edges, so it is active whenever
    the repo requests anything from the project. When this repo requests exactly
    one item of a set (and none of its rivals in any overlapping set), the repo
    pins it via `repo_pin` (except `<ws>__build`, which serves sdist builds for
    every repo). When several items are requested, `repo_default` comes from the
    selected pyproject's `[tool.uv] default-groups` or a project whose default
    dependencies are requested, provided exactly one candidate qualifies.

    Args:
        conflicts: Struct returned by `parse_uv_conflicts`.
        target_projects: List of canonicalized target project names.
        requested_by_project: Dict mapping project name -> requested groups dict.
        default_owner: Canonicalized project name that owns `default-groups`.
        uv_default_groups: `[tool.uv] default-groups` value (`"all"` or list).
        is_build_tools_repo: Whether this repo is the workspace `__build` repo.

    Returns:
        List of `repo_pin` variant qualified names active across this repo.
    """
    target_projects_set = {p: True for p in target_projects}
    requested_keys = {
        project: {canonicalize_group_key(key): True for key in requested.keys()}
        for project, requested in requested_by_project.items()
    }
    requested_by_set = []
    requested_qname_sets = []
    all_requested_qnames = {}
    for variant_set in conflicts.variant_sets:
        owned_items = [item for item in variant_set["items"] if item["package"] in target_projects_set]
        requested_items = [item for item in owned_items if _is_item_requested(item, requested_keys[item["package"]])]
        requested_by_set.append((owned_items, requested_items))
        if requested_items:
            qnames = [variant_item_qname(item) for item in requested_items]
            variant_set["repo_requested"] = qnames
            requested_qname_sets.append(qnames)
            for q in qnames:
                all_requested_qnames[q] = True
    rival_requested = excluded_variant_items(requested_qname_sets, all_requested_qnames)

    repo_pins = []
    for variant_set, (owned_items, requested_items) in zip(conflicts.variant_sets, requested_by_set):
        # An item can belong to several sets (e.g. `[[cpu, gpu], [cpu, gpu-test]]`).
        # Pin it only if the repo requests none of its rivals in any of them.
        if len(requested_items) <= 1:
            if requested_items and not is_build_tools_repo:
                qname = variant_item_qname(requested_items[0])
                if qname not in rival_requested:
                    variant_set["repo_pin"] = qname
                    repo_pins.append(qname)
            continue

        candidates = []
        for item in owned_items:
            requested = requested_keys[item["package"]]
            if item["kind"] == "project":
                if "default" in requested:
                    candidates.append(item)
                continue
            if item["kind"] != "group" or item["package"] != default_owner:
                continue
            if uv_default_groups != "all" and item["name"] not in [canonicalize_name(g) for g in uv_default_groups]:
                continue
            if "group:" + item["name"] not in requested:
                continue
            candidates.append(item)
        if len(candidates) == 1:
            variant_set["repo_default"] = variant_item_qname(candidates[0])

    return repo_pins

def _fold_with_cache(marker, constraint_key, conflicts, repo_pins, parse_cache, tokens_cache, fold_cache):
    """Fold `marker` under `[constraint_key] + repo_pins`, reusing cached tokens and results."""
    cache_key = (constraint_key, marker)
    if fold_cache != None:
        cached = fold_cache.get(cache_key)
        if cached != None:
            return cached
    tokens = tokens_cache.get(constraint_key) if tokens_cache != None else None
    if tokens == None:
        active = ([constraint_key] if constraint_key else []) + repo_pins
        tokens = variant_active_tokens(active, conflicts.set_qnames)
        if tokens_cache != None:
            tokens_cache[constraint_key] = tokens
    ev = fold_variant_marker(
        marker,
        conflict_pairs = conflicts.conflict_pairs,
        parse_cache = parse_cache,
        active_tokens = tokens,
    )
    if fold_cache != None:
        fold_cache[cache_key] = ev
    return ev

def make_pin_marker_folder(conflicts, repo_pins, parse_cache = None, tokens_cache = None, fold_cache = None):
    """Build a `fold_pin_marker(constraint, marker)` closure for `expand_root_edges`.

    Jointly evaluates `__variant_` tokens against both the edge's enclosing
    variant `constraint` and all `repo_pins` active in this repo:
      - `"F"` (unsatisfiable) returns `None` so the edge is pruned immediately.
      - `"T"` with a non-empty `constraint` simplifies to `""`.
      - Plain (`constraint == ""`) edges keep their marker even when `"T"` under
        `repo_pins` so plain edge-split pruning can still detect overlap with
        conflicted branches on the same pin.

    Args:
        conflicts: Struct returned by `parse_uv_conflicts`.
        repo_pins: List of `repo_pin` qnames active in this repo.
        parse_cache: Optional dict memoizing `{marker: parsed_ast}` across folds.
        tokens_cache: Optional dict memoizing `{constraint: active_tokens}` for
            this `(conflicts, repo_pins)`.
        fold_cache: Optional dict memoizing `{(constraint, marker): fold_result}`
            for this `(conflicts, repo_pins)`.

    Returns:
        Callable `fold(constraint, marker) -> str | None`.
    """
    if tokens_cache == None:
        tokens_cache = {}
    if fold_cache == None:
        fold_cache = {}

    def _fold(constraint, marker):
        if not marker or "__variant_" not in marker:
            return marker
        ev = _fold_with_cache(
            marker,
            constraint,
            conflicts,
            repo_pins,
            parse_cache,
            tokens_cache,
            fold_cache,
        )
        if ev == "F":
            return None
        if ev == "T" and constraint:
            return ""
        return marker

    return _fold

def _edge_constraint_name(base_dep_name, version, marker, tag = ""):
    """Build a content-hashed `__edge_<hash>` constraint name for `(base_dep_name, version, tag, marker)`."""
    prefix = resolution_marker_constraint_name(base_dep_name, version, tag) if version else "res_{}".format(sanitize_name(base_dep_name))
    return "%s__edge_%x" % (prefix, hash(marker) & 0xffffffff)

def _prune_plain_branches(branches, conflicts, repo_pins, parse_cache = None, tokens_cache = None, fold_cache = None):
    """Drop or narrow plain (`raw_constraint == ""`) conflict-gated branches on one pin.

    A plain branch carrying `__variant_` tokens (e.g. from an unconflicted
    project or expanded local member) can sit next to conflicted branches for
    the same conflict set. With no variant selected it would match alongside
    `_unselected_<set>`, and with a variant selected it would collide with that
    variant's own entry and make `select()` ambiguous.
      - A variant item `q` covers `pkg_key` when `q` has a bare branch on this
        pin or already has a branch for `pkg_key`.
      - Drop the plain branch if no uncovered item of the set can satisfy it;
        otherwise narrow its effective marker to the uncovered items that can.
    """
    bare_variants = {}
    variant_specs = {}  # variant_qname -> {pkg_key: True}
    for branch in branches:
        rc = branch["raw_constraint"]
        if not rc:
            continue
        if not branch["needs_marker"]:
            bare_variants[rc] = True
        variant_specs.setdefault(rc, {})[branch["pkg_key"]] = True

    if not variant_specs:
        return branches

    if tokens_cache == None:
        tokens_cache = {}
    if fold_cache == None:
        fold_cache = {}

    set_pin_by_idx = [vs.get("repo_pin", "") for vs in conflicts.variant_sets]
    kept = []
    for branch in branches:
        expr = branch["effective_marker"]
        if branch["raw_constraint"] or not expr or "__variant_" not in expr:
            kept.append(branch)
            continue

        guards = []
        drop = False
        for idx, qnames in enumerate(conflicts.set_qnames):
            if not [q for q in qnames if marker_mentions_variant(expr, q)]:
                continue
            if not [q for q in qnames if q in variant_specs]:
                continue
            repo_pin = set_pin_by_idx[idx]
            candidates = [repo_pin] if repo_pin else qnames
            uncovered = [
                q
                for q in candidates
                if q not in bare_variants and branch["pkg_key"] not in variant_specs.get(q, {})
            ]
            sat_uncovered = [
                q
                for q in uncovered
                if _fold_with_cache(
                    expr,
                    q,
                    conflicts,
                    repo_pins,
                    parse_cache,
                    tokens_cache,
                    fold_cache,
                ) != "F"
            ]
            if not sat_uncovered:
                drop = True
                break
            guards.append("(" + " or ".join(["extra == '__variant_{}'".format(q) for q in sat_uncovered]) + ")")

        if drop:
            continue
        if guards:
            branch["effective_marker"] = " and ".join(guards + ["({})".format(expr)])
            branch["needs_marker"] = True
        kept.append(branch)

    return kept

def resolve_uv_pins(
        expanded_edges,
        conflicts,
        repo_pins,
        fork_constraints,
        resolution_marker_exprs,
        parse_cache = None,
        tokens_cache = None,
        fold_cache = None):
    """Aggregate expanded UV root edges into pins, markers, and testonly sets.

    Aggregates edges by `(pin_name, raw_constraint, pkg_key)`, prunes plain
    conflict-gated branches that overlap variant entries before registering any
    `resolution_marker_exprs` keys, and emits `pinned_keys`,
    `root_dependency_markers`, and testonly sets in a single final pass.

    Args:
        expanded_edges: Non-local edge structs returned by `expand_root_edges`.
        conflicts: Struct returned by `parse_uv_conflicts`.
        repo_pins: List of `repo_pin` qnames active in this repo.
        fork_constraints: Dict `{base_name: {(version, tag): fork_constraint_name}}`.
        resolution_marker_exprs: Dict of constraint name -> marker expr or
            compound dict, mutated in place with newly needed edge constraints.
        parse_cache: Optional dict memoizing `{marker: parsed_ast}` across folds.
        tokens_cache: Optional dict memoizing `{constraint: active_tokens}` for
            this `(conflicts, repo_pins)`.
        fold_cache: Optional dict memoizing `{(constraint, marker): fold_result}`
            for this `(conflicts, repo_pins)`.

    Returns:
        Struct with `pinned_keys`, `root_dependency_markers`, `testonly_pins`,
        `expanded_testonly_pins`, and `non_testonly_pins`.
    """
    by_pin = {}  # pin_name -> {(raw_constraint, pkg_key): [edge, ...]}
    specs_per_group = {}  # (pin_name, raw_constraint) -> {pkg_key: True}
    for edge in expanded_edges:
        by_pin.setdefault(edge.pin_name, {}).setdefault((edge.constraint, edge.pkg_key), []).append(edge)
        specs_per_group.setdefault((edge.pin_name, edge.constraint), {})[edge.pkg_key] = True

    pinned_keys = {}
    root_dependency_markers = {}
    direct_testonly = {}
    expanded_testonly = {}
    non_testonly = {}
    if tokens_cache == None:
        tokens_cache = {}
    if fold_cache == None:
        fold_cache = {}

    for pin_name, grouped in by_pin.items():
        base_name = pin_name.split("[")[0]
        branches = []
        for (raw_constraint, pkg_key), entries in grouped.items():
            markers = [e.pin_marker for e in entries]
            if "" in markers:
                agg_marker = ""
            else:
                unique = sorted({m: True for m in markers}.keys())
                agg_marker = unique[0] if len(unique) == 1 else " or ".join(["({})".format(m) for m in unique])

            parts = parse_package_key(pkg_key)
            pkg_version = parts.version
            pkg_tag = parts.tag
            fork_constraint = fork_constraints.get(base_name, {}).get((pkg_version, pkg_tag))
            effective_marker = agg_marker or resolution_marker_exprs.get(fork_constraint, "")
            multi_spec = len(specs_per_group[(pin_name, raw_constraint)]) > 1

            needs_marker = bool(effective_marker) and (
                multi_spec or
                fork_constraint != None or
                (
                    "__variant_" in effective_marker and
                    _fold_with_cache(
                        effective_marker,
                        raw_constraint,
                        conflicts,
                        repo_pins,
                        parse_cache,
                        tokens_cache,
                        fold_cache,
                    ) == "V"
                )
            )
            branches.append({
                "raw_constraint": raw_constraint,
                "pkg_key": pkg_key,
                "pkg_version": pkg_version,
                "pkg_tag": pkg_tag,
                "fork_constraint": fork_constraint,
                "effective_marker": effective_marker,
                "needs_marker": needs_marker,
                "entries": entries,
            })

        surviving = _prune_plain_branches(
            branches,
            conflicts,
            repo_pins,
            parse_cache = parse_cache,
            tokens_cache = tokens_cache,
            fold_cache = fold_cache,
        )
        for branch in surviving:
            raw_constraint = branch["raw_constraint"]
            if branch["needs_marker"]:
                fork_constraint = branch["fork_constraint"]
                marker = branch["effective_marker"]
                if fork_constraint and marker == resolution_marker_exprs.get(fork_constraint):
                    marker_key = fork_constraint
                else:
                    marker_key = _edge_constraint_name(base_name, branch["pkg_version"], marker, tag = branch["pkg_tag"])
                    resolution_marker_exprs[marker_key] = marker

                if raw_constraint:
                    constraint_key = "{}_{}".format(raw_constraint, marker_key)
                    resolution_marker_exprs[constraint_key] = {
                        "variant": raw_constraint,
                        "marker": marker_key,
                    }
                else:
                    constraint_key = marker_key
            else:
                constraint_key = raw_constraint

            pinned_keys.setdefault(pin_name, {})[constraint_key] = branch["pkg_key"]
            for edge in branch["entries"]:
                record_root_marker(root_dependency_markers, pin_name, edge.avail_marker)
                if pin_name != base_name:
                    record_root_marker(root_dependency_markers, base_name, edge.avail_marker)
                record_edge_testonly(edge, direct_testonly, expanded_testonly, non_testonly)

    testonly_pins = [name for name in direct_testonly if name not in non_testonly]
    expanded_testonly_pins = [
        name
        for name in expanded_testonly
        if name not in non_testonly and name not in direct_testonly
    ]
    return struct(
        pinned_keys = pinned_keys,
        root_dependency_markers = root_dependency_markers,
        testonly_pins = testonly_pins,
        expanded_testonly_pins = expanded_testonly_pins,
        non_testonly_pins = non_testonly.keys(),
    )
