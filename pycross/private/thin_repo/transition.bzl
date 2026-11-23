"""Generation of repo-local `_transition.bzl` for thin package repos."""

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
        label, sep, value = f[2:].partition("=")
        values.setdefault(label, []).append(value if sep else "True")
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

    io_lines = []
    return_lines = []
    for label, values in sorted(flag_settings.items()):
        io_lines.append("        {},".format(json.encode(label)))
        return_lines.append("    {}: {},".format(json.encode(label), repr(values)))
    settings_lines = []
    for label, value in sorted(settings.items()):
        io_lines.append("        {},".format(json.encode(label)))
        settings_lines.append("    {}: {},".format(json.encode(label), repr(value)))

    has_variant_state = bool(variant_state_overrides)
    if has_variant_state:
        io_lines.append("        {},".format(json.encode(variant_state_label)))

    util_imports = ["coerce_transition_values", "split_setting_value"]
    if has_variant_state:
        util_imports.append("merge_variant_state")
    util_load = 'load("@rules_pycross//pycross/private:util.bzl", {})'.format(
        ", ".join([json.encode(sym) for sym in sorted(util_imports)]),
    )

    state_block = ""
    state_merge_line = ""
    if has_variant_state:
        override_lines = [
            "    {}: {},".format(json.encode(k), json.encode(v))
            for k, v in sorted(variant_state_overrides.items())
        ]
        state_block = (
            "\n# Variant pins, defaults, and usable narrowing merged over incoming _state.\n" +
            "_VARIANT_STATE_LABEL = {}\n\n".format(json.encode(variant_state_label)) +
            "_VARIANT_STATE_OVERRIDES = {\n" +
            "\n".join(override_lines) +
            "\n}\n"
        )
        state_merge_line = "    result[_VARIANT_STATE_LABEL] = merge_variant_state(settings[_VARIANT_STATE_LABEL], _VARIANT_STATE_OVERRIDES)\n"

    duplicate_check = ""
    if flag_settings and settings:
        duplicate_check = (
            "\n_CANONICAL_FLAG_LABELS = {\n" +
            "    Label(label): True\n" +
            "    for label in _FLAG_VALUES\n" +
            '    if not label.startswith("//command_line_option:")\n' +
            "}\n" +
            "for _setting_label in _SETTING_VALUES:\n" +
            "    if Label(_setting_label) in _CANONICAL_FLAG_LABELS:\n" +
            '        fail("Build setting {} is set in both flags and settings".format(_setting_label))\n'
        )

    io_block = "\n".join(io_lines)
    return """\
\"\"\"Generated transition rules for {repo} with pinned flag values.\"\"\"

load("@rules_pycross//pycross/private:proxy.bzl", "make_file_proxy_rule", "make_library_proxy_rule")
{util_load}

_FLAG_VALUES = {{
{return_dict}
}}

_SETTING_VALUES = {{
{settings_dict}
}}
{state_block}{duplicate_check}
def _transition_impl(settings, attr):
    result = {{
        label: coerce_transition_values(settings[label], values)
        for label, values in _FLAG_VALUES.items()
    }}
    for label, value in _SETTING_VALUES.items():
        result[label] = coerce_transition_values(settings[label], split_setting_value(settings[label], value))
{state_merge_line}    if attr.platform:
        result["//command_line_option:platforms"] = [str(attr.platform)]
    else:
        result["//command_line_option:platforms"] = settings["//command_line_option:platforms"]
    return result

_repo_transition = transition(
    implementation = _transition_impl,
    inputs = [
        "//command_line_option:platforms",
{io_block}
    ],
    outputs = [
        "//command_line_option:platforms",
{io_block}
    ],
)

pycross_transitioning_library_proxy = make_library_proxy_rule(cfg = _repo_transition)

pycross_transitioning_file_proxy = make_file_proxy_rule(cfg = _repo_transition)
""".format(
        repo = repo_name,
        util_load = util_load,
        return_dict = "\n".join(return_lines),
        settings_dict = "\n".join(settings_lines),
        state_block = state_block,
        duplicate_check = duplicate_check,
        state_merge_line = state_merge_line,
        io_block = io_block,
    )
