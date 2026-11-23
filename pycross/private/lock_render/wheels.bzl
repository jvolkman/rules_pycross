"""Wheel candidate resolution and `pycross_wheel_chooser` rendering for `_lock/lock.bzl`."""

load("//pycross/private:build_text.bzl", "alias", "config_setting_group", "flag_setting", "select_expr")
load("//pycross/private:util.bzl", "is_universal_py3_wheel", "sanitize_name")
load(":common.bzl", "ind", "wheel_target")

def wheel_cs_name(pkg_key, filename):
    """Return the `config_setting` target name for a single wheel candidate.

    Args:
        pkg_key: Package key in the lock.
        filename: Wheel filename.

    Returns:
        Target name string `_wheel_cs_<pkg_key>_<sanitized_filename>`.
    """
    return "_wheel_cs_{}_{}".format(pkg_key, sanitize_name(filename))

def resolved_wheel_candidates(pkg, repo_map):
    """Return the subset of `pkg['wheel_candidates']` whose file references resolve in `repo_map`.

    Args:
        pkg: Package dict from the lock.
        repo_map: Map of file key -> repository label.

    Returns:
        List of resolved wheel candidate dicts.
    """
    return [
        c
        for c in pkg.get("wheel_candidates", [])
        if wheel_target(c.get("file_reference", {}), repo_map)
    ]

def wheel_match_condition(lines, pkg_key, resolved_filenames, all_resolved, target_name, require_target = False, loads = None):
    """Emit a config_setting (or group) matching when any wheel in `resolved_filenames` matched.

    Shared by wheel-only availability (`_wheel_available_<pkg>`) and variant-reset
    wheel gating (`_reset_wheel_<pkg>`). Those two callers are mutually exclusive
    (wheel-only requires no sdist fallback; reset gating requires an sdist build
    fallback); uniqueness of `_wheel_matched_<pkg>` is enforced via `loads`.

    Args:
        lines: Output lines list.
        pkg_key: Package key in the lock.
        resolved_filenames: Non-empty list of resolved wheel filenames.
        all_resolved: Whether every candidate in `pkg['wheel_candidates']` resolved.
        target_name: Target name to emit when a new target is created.
        require_target: If True, emit a `native.alias` named `target_name` even for
            a single candidate (needed when external callers reference `target_name`
            by fixed label).
        loads: Optional dict tracking emitted helper loads (`"selects"`,
            `"wheel_matched"`) and emitted `_wheel_matched_*` target names.

    Returns:
        Relative config_setting label (`":<name>"`) matching when any wheel matched.
    """
    cs_labels = [":" + wheel_cs_name(pkg_key, fn) for fn in resolved_filenames]
    if len(cs_labels) == 1:
        if require_target:
            lines.extend(alias(target_name, cs_labels[0], indent = 1, use_native = True))
            return ":" + target_name
        return cs_labels[0]

    if len(cs_labels) >= 3 and all_resolved:
        matched_name = "_wheel_matched_{}".format(pkg_key)
        if loads != None:
            emitted = loads.setdefault("emitted_wheel_matched", {})
            if matched_name in emitted:
                fail("internal: duplicate {} target emitted for {}".format(matched_name, pkg_key))
            emitted[matched_name] = True
            loads["wheel_matched"] = True
        lines.extend([
            ind("pycross_wheel_matched("),
            ind("name = {},".format(json.encode(matched_name)), 2),
            ind("chooser = {},".format(json.encode(":_wheel_chooser_{}".format(pkg_key))), 2),
            ind(")"),
            "",
        ])
        lines.extend(flag_setting(target_name, ":" + matched_name, "true", indent = 1, use_native = True))
        return ":" + target_name

    lines.extend(config_setting_group(target_name, "match_any", cs_labels, indent = 1))
    if loads != None:
        loads["selects"] = True
    return ":" + target_name

def render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_target = None, loads = None):
    """Render a wheel chooser target and per-wheel config_settings + alias.

    Args:
        lines: Output lines list.
        pkg_key: Package key in the lock.
        pkg: Package dict from the lock.
        repo_map: Map of file key -> repository label.
        sdist_target: Optional sdist/build fallback target label.
        loads: Optional dict tracking emitted helper loads (`"selects"`, `"wheel_matched"`).

    Returns:
        True when a wheel-only availability target was emitted under the name
        `_wheel_available_<pkg>` for thin repos to compose with per-member
        availability markers.
    """
    candidates = pkg.get("wheel_candidates", [])
    if not candidates:
        return False

    # Resolve candidate targets first so a sole universal py3-none-any wheel can
    # bypass pycross_wheel_chooser, config_setting, and select() completely.
    resolved_candidates = []
    for candidate in candidates:
        target = wheel_target(candidate.get("file_reference", {}), repo_map)
        if target:
            resolved_candidates.append((candidate, target))

    if (
        len(candidates) == 1 and
        len(resolved_candidates) == 1 and
        is_universal_py3_wheel(resolved_candidates[0][0]["filename"])
    ):
        lines.extend(alias("_wheel_{}".format(pkg_key), resolved_candidates[0][1], indent = 1, use_native = True))
        return False

    filenames = [c["filename"] for c in candidates]
    chooser_name = "_wheel_chooser_{}".format(pkg_key)

    lines.extend([
        ind("pycross_wheel_chooser("),
        ind("name = {},".format(json.encode(chooser_name)), 2),
        ind("candidates = [{}],".format(", ".join([json.encode(f) for f in filenames])), 2),
        ind(")"),
        "",
    ])

    for candidate, _target in resolved_candidates:
        filename = candidate["filename"]
        lines.extend(flag_setting(
            wheel_cs_name(pkg_key, filename),
            ":" + chooser_name,
            filename,
            indent = 1,
            use_native = True,
        ))

    # Wheel alias selecting over the config_settings
    branches = [
        (":" + wheel_cs_name(pkg_key, candidate["filename"]), target)
        for candidate, target in resolved_candidates
    ]
    no_match_target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
    lines.extend(alias(
        "_wheel_{}".format(pkg_key),
        select_expr(branches, default = no_match_target, indent = 2),
        indent = 1,
        use_native = True,
        actual_is_expr = True,
    ))

    # Wheel-only availability config_setting: matches when any wheel matches.
    # Always emitted under _wheel_available_<pkg> so thin repos can compose it
    # with their own per-member availability_markers.
    all_resolved = len(resolved_candidates) == len(candidates)
    has_universal = (
        all_resolved and
        any([is_universal_py3_wheel(c["filename"]) for c, _ in resolved_candidates])
    )
    if sdist_target or not resolved_candidates or has_universal:
        return False

    wheel_match_condition(
        lines,
        pkg_key,
        [c["filename"] for c, _ in resolved_candidates],
        all_resolved,
        "_wheel_available_{}".format(pkg_key),
        require_target = True,
        loads = loads,
    )
    return True
