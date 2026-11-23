"""Wheel candidate resolution and `pycross_wheel_chooser` rendering for `_lock/lock.bzl`."""

load("//pycross/private:util.bzl", "is_universal_py3_wheel", "sanitize_name")
load(":common.bzl", "ind", "wheel_target")

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

def render_marker_wheel_chooser(lines, pkg_key, pkg, repo_map, sdist_target = None):
    """Render a wheel chooser target and per-wheel config_settings + alias.

    Args:
        lines: Output lines list.
        pkg_key: Package key in the lock.
        pkg: Package dict from the lock.
        repo_map: Map of file key -> repository label.
        sdist_target: Optional sdist/build fallback target label.

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
        lines.extend([
            ind("native.alias("),
            ind('name = "_wheel_{}",'.format(pkg_key), 2),
            ind('actual = "{}",'.format(resolved_candidates[0][1]), 2),
            ind(")"),
            "",
        ])
        return False

    filenames = [c["filename"] for c in candidates]
    chooser_name = "_wheel_chooser_{}".format(pkg_key)

    lines.extend([
        ind("pycross_wheel_chooser("),
        ind('name = "{}",'.format(chooser_name), 2),
        ind("candidates = {},".format(filenames), 2),
        ind(")"),
        "",
    ])

    for candidate, _target in resolved_candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, sanitize_name(filename))
        lines.extend([
            ind("native.config_setting("),
            ind('name = "{}",'.format(cs_name), 2),
            ind("flag_values = {", 2),
            ind('":{chooser}": "{filename}",'.format(
                chooser = chooser_name,
                filename = filename,
            ), 3),
            ind("},", 2),
            ind(")"),
            "",
        ])

    # Wheel alias selecting over the config_settings
    lines.extend([
        ind("native.alias("),
        ind('name = "_wheel_{}",'.format(pkg_key), 2),
        ind("actual = select({", 2),
    ])
    for candidate, target in resolved_candidates:
        filename = candidate["filename"]
        cs_name = "_wheel_cs_{}_{}".format(pkg_key, sanitize_name(filename))
        lines.append(ind('":{}": "{}",'.format(cs_name, target), 3))
    no_match_target = sdist_target if sdist_target else "@rules_pycross//pycross/private:no_match_error"
    lines.append(ind('"//conditions:default": "{}",'.format(no_match_target), 3))
    lines.extend([
        ind("}),", 2),
        ind(")"),
        "",
    ])

    # Wheel-only availability config_setting: matches when any wheel matches.
    # Always emitted under _wheel_available_<pkg> so thin repos can compose it
    # with their own per-member availability_markers.
    has_universal = (
        len(resolved_candidates) == len(candidates) and
        any([is_universal_py3_wheel(c["filename"]) for c, _ in resolved_candidates])
    )
    if sdist_target or not resolved_candidates or has_universal:
        return False

    group_name = "_wheel_available_{}".format(pkg_key)
    cs_names = [
        ":_wheel_cs_{}_{}".format(pkg_key, sanitize_name(candidate["filename"]))
        for candidate, _target in resolved_candidates
    ]
    if len(cs_names) == 1:
        lines.extend([
            ind("native.alias("),
            ind('name = "{}",'.format(group_name), 2),
            ind('actual = "{}",'.format(cs_names[0]), 2),
            ind(")"),
            "",
        ])
    elif len(cs_names) >= 3 and len(resolved_candidates) == len(candidates):
        matched_name = "_wheel_matched_{}".format(pkg_key)
        lines.extend([
            ind("pycross_wheel_matched("),
            ind('name = "{}",'.format(matched_name), 2),
            ind('chooser = ":{}",'.format(chooser_name), 2),
            ind(")"),
            "",
            ind("native.config_setting("),
            ind('name = "{}",'.format(group_name), 2),
            ind("flag_values = {", 2),
            ind('":{}": "true",'.format(matched_name), 3),
            ind("},", 2),
            ind(")"),
            "",
        ])
    else:
        lines.extend([
            ind("selects.config_setting_group("),
            ind('name = "{}",'.format(group_name), 2),
            ind("match_any = [", 2),
        ])
        for cs in cs_names:
            lines.append(ind('"{}",'.format(cs), 3))
        lines.extend([
            ind("],", 2),
            ind(")"),
            "",
        ])
    return True
