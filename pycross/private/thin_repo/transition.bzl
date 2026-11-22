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

def render_transition_bzl(repo_name, flags, settings, fixed_settings):
    """Render `_transition.bzl` defining custom transitioning proxy rules for this thin repo.

    Bazel's `platform(flags=[...])` only applies during top-level platform mapping,
    not when `--platforms` is set via a Starlark transition. We therefore generate
    a repo-local transition setting the individual flag/setting values and reuse
    `make_library_proxy_rule` / `make_file_proxy_rule` from `proxy.bzl`.

    Args:
        repo_name: User-facing repo name for docstrings.
        flags: Normalized `--<label>[=<value>]` flag strings.
        settings: Canonical build setting label -> value dict.
        fixed_settings: Fixed `_lock` variant setting label -> value dict.

    Returns:
        Generated `_transition.bzl` file content.
    """
    flag_settings = flag_values(flags)

    outputs_lines = []
    return_lines = []
    for label, values in sorted(flag_settings.items()):
        outputs_lines.append("        {},".format(json.encode(label)))
        return_lines.append("    {}: {},".format(json.encode(label), repr(values)))
    settings_lines = []
    for label, value in sorted(settings.items()):
        outputs_lines.append("        {},".format(json.encode(label)))
        settings_lines.append("    {}: {},".format(json.encode(label), repr(value)))
    fixed_lines = []
    fixed_outputs_lines = []
    for label, value in sorted(fixed_settings.items()):
        fixed_outputs_lines.append("        {},".format(json.encode(label)))
        fixed_lines.append("    {}: {},".format(json.encode(label), repr(value)))

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

    return """\
\"\"\"Generated transition rules for {repo} with pinned flag values.\"\"\"

load("@rules_pycross//pycross/private:proxy.bzl", "make_file_proxy_rule", "make_library_proxy_rule")
load("@rules_pycross//pycross/private:util.bzl", "coerce_transition_values", "split_setting_value")

_FLAG_VALUES = {{
{return_dict}
}}

_SETTING_VALUES = {{
{settings_dict}
}}

# Variant pins and defaults for the workspace repo's resolvers.
_FIXED_VALUES = {{
{fixed_dict}
}}
{duplicate_check}
def _transition_impl(settings, attr):
    result = {{
        label: coerce_transition_values(settings[label], values)
        for label, values in _FLAG_VALUES.items()
    }}
    for label, value in _SETTING_VALUES.items():
        result[label] = coerce_transition_values(settings[label], split_setting_value(settings[label], value))
    result.update(_FIXED_VALUES)
    if attr.platform:
        result["//command_line_option:platforms"] = [str(attr.platform)]
    else:
        result["//command_line_option:platforms"] = settings["//command_line_option:platforms"]
    return result

_repo_transition = transition(
    implementation = _transition_impl,
    inputs = [
        "//command_line_option:platforms",
{outputs}
    ],
    outputs = [
        "//command_line_option:platforms",
{outputs}
{fixed_outputs}
    ],
)

pycross_transitioning_library_proxy = make_library_proxy_rule(cfg = _repo_transition)

pycross_transitioning_file_proxy = make_file_proxy_rule(cfg = _repo_transition)
""".format(
        repo = repo_name,
        return_dict = "\n".join(return_lines),
        settings_dict = "\n".join(settings_lines),
        fixed_dict = "\n".join(fixed_lines),
        duplicate_check = duplicate_check,
        outputs = "\n".join(outputs_lines),
        fixed_outputs = "\n".join(fixed_outputs_lines),
    )
