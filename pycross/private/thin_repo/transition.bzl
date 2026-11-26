"""Generation of repo-local `_transition.bzl` for thin package repos."""

load("//pycross/private:util.bzl", "parse_flag_arg")

def flag_values(flags):
    """Parse `--label[=value]` flags (validated by the extension) into label -> values.

    Values keep declaration order; a flag without a value means "True".

    Args:
        flags: Normalized `--<label>[=<value>]` flag strings.

    Returns:
        Dict mapping flag label to list of string values.
    """
    values = {}
    for f in flags:
        parsed = parse_flag_arg(f)
        values.setdefault(parsed.label, []).append(parsed.value)
    return values

def render_transition_bzl(repo_name, flags, settings, variant_state_label = "", variant_state_overrides = None):
    """Render `_transition.bzl` defining custom transitioning proxy rules for this thin repo.

    Bazel's `platform(flags=[...])` only applies during top-level platform mapping,
    not when `--platforms` is set via a Starlark transition. We therefore generate
    a repo-local transition setting the individual flag/setting values and reuse
    `make_library_proxy_rule` / `make_file_proxy_rule` from `proxy.bzl`.

    Args:
        repo_name: User-facing repo name for docstrings.
        flags: Normalized `--<label>[=<value>]` flag strings.
        settings: Canonical build setting label -> value dict.
        variant_state_label: Label of the workspace's `//_lock:_state` setting,
            when `variant_state_overrides` is non-empty.
        variant_state_overrides: `{key: value}` overrides to merge over incoming
            `//_lock:_state` (pins, defaults, and usable narrowing).

    Returns:
        Generated `_transition.bzl` file content.
    """
    flag_settings = flag_values(flags)
    variant_state_overrides = variant_state_overrides or {}

    has_flags = bool(flag_settings)
    has_settings = bool(settings)
    has_variant_state = bool(variant_state_overrides)

    io_entries = ['        "//command_line_option:platforms",']
    return_lines = []
    for label, values in sorted(flag_settings.items()):
        io_entries.append("        {},".format(json.encode(label)))
        return_lines.append("    {}: {},".format(json.encode(label), repr(values)))
    settings_lines = []
    for label, value in sorted(settings.items()):
        io_entries.append("        {},".format(json.encode(label)))
        settings_lines.append("    {}: {},".format(json.encode(label), repr(value)))
    if has_variant_state:
        io_entries.append("        {},".format(json.encode(variant_state_label)))

    lines = [
        '"""Generated transition rules for {} with pinned flag values."""'.format(repo_name),
        "",
        'load("@rules_pycross//pycross/private:proxy.bzl", "make_file_proxy_rule", "make_library_proxy_rule")',
    ]
    if has_flags or has_settings:
        util_imports = ["coerce_transition_values"]
        if has_settings:
            util_imports.append("split_setting_value")
        lines.append('load("@rules_pycross//pycross/private:util.bzl", {})'.format(
            ", ".join([json.encode(sym) for sym in sorted(util_imports)]),
        ))
    if has_variant_state:
        lines.append('load("@rules_pycross//pycross/private:variant_util.bzl", "merge_variant_state")')
    lines.append("")

    if has_flags:
        lines.append("_FLAG_VALUES = {")
        lines.extend(return_lines)
        lines.extend(["}", ""])

    if has_settings:
        lines.append("_SETTING_VALUES = {")
        lines.extend(settings_lines)
        lines.extend(["}", ""])

    if has_variant_state:
        lines.extend([
            "# Variant pins, defaults, and usable narrowing merged over incoming _state.",
            "_VARIANT_STATE_LABEL = {}".format(json.encode(variant_state_label)),
            "",
            "_VARIANT_STATE_OVERRIDES = {",
        ])
        for k, v in sorted(variant_state_overrides.items()):
            lines.append("    {}: {},".format(json.encode(k), json.encode(v)))
        lines.extend(["}", ""])

    if has_flags and has_settings:
        lines.extend([
            "_CANONICAL_FLAG_LABELS = {",
            "    Label(label): True",
            "    for label in _FLAG_VALUES",
            '    if not label.startswith("//command_line_option:")',
            "}",
            "for _setting_label in _SETTING_VALUES:",
            "    if Label(_setting_label) in _CANONICAL_FLAG_LABELS:",
            '        fail("Build setting {} is set in both flags and settings".format(_setting_label))',
            "",
        ])

    lines.append("def _transition_impl(settings, attr):")
    if has_flags:
        lines.extend([
            "    result = {",
            "        label: coerce_transition_values(settings[label], values)",
            "        for label, values in _FLAG_VALUES.items()",
            "    }",
        ])
    else:
        lines.append("    result = {}")
    if has_settings:
        lines.extend([
            "    for label, value in _SETTING_VALUES.items():",
            "        result[label] = coerce_transition_values(settings[label], split_setting_value(settings[label], value))",
        ])
    if has_variant_state:
        lines.append("    result[_VARIANT_STATE_LABEL] = merge_variant_state(settings[_VARIANT_STATE_LABEL], _VARIANT_STATE_OVERRIDES)")
    lines.extend([
        "    if attr.platform:",
        '        result["//command_line_option:platforms"] = [str(attr.platform)]',
        "    else:",
        '        result["//command_line_option:platforms"] = settings["//command_line_option:platforms"]',
        "    return result",
        "",
        "_repo_transition = transition(",
        "    implementation = _transition_impl,",
        "    inputs = [",
    ])
    lines.extend(io_entries)
    lines.extend([
        "    ],",
        "    outputs = [",
    ])
    lines.extend(io_entries)
    lines.extend([
        "    ],",
        ")",
        "",
        "pycross_transitioning_library_proxy = make_library_proxy_rule(cfg = _repo_transition, supports_deps = False)",
        "",
        "pycross_transitioning_file_proxy = make_file_proxy_rule(cfg = _repo_transition)",
        "",
    ])
    return "\n".join(lines)
