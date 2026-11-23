"""Shared line-returning helpers for generating Bazel BUILD and Starlark target text."""

def _ind(text, tabs):
    if not text:
        return ""
    return ("    " * tabs) + text

def config_setting_group(name, kind, labels, indent = 0):
    """Render a `selects.config_setting_group` target as a list of lines (with trailing blank line).

    Args:
        name: Target name.
        kind: Attribute name (`"match_any"` or `"match_all"`).
        labels: Iterable of config_setting label strings.
        indent: Outer indentation level (4 spaces per level).

    Returns:
        List of generated lines ending with an empty string.
    """
    lines = [
        _ind("selects.config_setting_group(", indent),
        _ind("name = {},".format(json.encode(name)), indent + 1),
        _ind("{} = [".format(kind), indent + 1),
    ]
    for label in labels:
        lines.append(_ind("{},".format(json.encode(label)), indent + 2))
    lines.extend([
        _ind("],", indent + 1),
        _ind(")", indent),
        "",
    ])
    return lines

def flag_setting(name, flag, value, indent = 0, use_native = False, inline = False):
    """Render a single-entry `config_setting(flag_values = ...)` target.

    Args:
        name: Target name.
        flag: Build setting / feature flag label.
        value: Expected string value.
        indent: Outer indentation level (4 spaces per level).
        use_native: Whether to emit `native.config_setting` instead of `config_setting`.
        inline: Whether to keep `flag_values = {flag: value}` on a single line.

    Returns:
        List of generated lines ending with an empty string.
    """
    rule = "native.config_setting" if use_native else "config_setting"
    lines = [
        _ind("{}(".format(rule), indent),
        _ind("name = {},".format(json.encode(name)), indent + 1),
    ]
    if inline:
        lines.append(_ind("flag_values = {{{}: {}}},".format(json.encode(flag), json.encode(value)), indent + 1))
    else:
        lines.extend([
            _ind("flag_values = {", indent + 1),
            _ind("{}: {},".format(json.encode(flag), json.encode(value)), indent + 2),
            _ind("},", indent + 1),
        ])
    lines.extend([
        _ind(")", indent),
        "",
    ])
    return lines

def select_expr(branches, default = None, indent = 1):
    """Render a `select({...})` expression string.

    The first line (`select({`) has no leading indent so it can follow `actual = `.
    Branch entries are indented to `indent + 1`, and the closing `})` is at `indent`.

    Args:
        branches: Sequence of `(condition_label, target_label)` pairs in emission order.
        default: Optional target label for `"//conditions:default"`.
        indent: Indentation level of the enclosing attribute line (`actual = ...`).

    Returns:
        Multi-line `select({...})` expression string.
    """
    lines = ["select({"]
    for cond, target in branches:
        lines.append(_ind("{}: {},".format(json.encode(cond), json.encode(target)), indent + 1))
    if default != None:
        lines.append(_ind('"//conditions:default": {},'.format(json.encode(default)), indent + 1))
    lines.append(_ind("})", indent))
    return "\n".join(lines)

def alias(name, actual, indent = 0, use_native = False, actual_is_expr = False, trailing_blank = True):
    """Render an `alias(...)` or `native.alias(...)` target.

    Args:
        name: Target name.
        actual: Target label string, or a raw Starlark expression when `actual_is_expr` is True.
        indent: Outer indentation level (4 spaces per level).
        use_native: Whether to emit `native.alias` instead of `alias`.
        actual_is_expr: If True, emit `actual` verbatim without JSON-encoding it.
        trailing_blank: Whether to append a trailing empty line.

    Returns:
        List of generated lines.
    """
    rule = "native.alias" if use_native else "alias"
    actual_str = actual if actual_is_expr else json.encode(actual)
    lines = [
        _ind("{}(".format(rule), indent),
        _ind("name = {},".format(json.encode(name)), indent + 1),
        _ind("actual = {},".format(actual_str), indent + 1),
        _ind(")", indent),
    ]
    if trailing_blank:
        lines.append("")
    return lines

def deps_plus_selects(lhs, unconditional, conditional_by_cond, indent = 1, inline_values = False, trailing_comma = False):
    """Render `<lhs> = [...] + select({...}) + ...` lines.

    Args:
        lhs: Left-hand side identifier (e.g. `"deps"` or `"_foo_deps"`).
        unconditional: Sorted iterable of unconditional dependency label strings.
        conditional_by_cond: Dict mapping condition label -> iterable of dependency labels.
        indent: Outer indentation level (4 spaces per level).
        inline_values: If True, format each select branch's value list on a single line.
        trailing_comma: Whether to append a trailing comma to the final line.

    Returns:
        List of generated lines (without a trailing blank line).
    """
    lines = [_ind("{} = [".format(lhs), indent)]
    for dep_label in unconditional:
        lines.append(_ind("{},".format(json.encode(dep_label)), indent + 1))
    lines.append(_ind("]", indent))
    for cond in sorted(conditional_by_cond.keys()):
        deps = sorted(conditional_by_cond[cond])
        lines[-1] = lines[-1] + " + select({"
        if inline_values:
            dep_list = ", ".join([json.encode(d) for d in deps])
            lines.append(_ind("{}: [{}],".format(json.encode(cond), dep_list), indent + 1))
        else:
            lines.append(_ind("{}: [".format(json.encode(cond)), indent + 1))
            for dep_label in deps:
                lines.append(_ind("{},".format(json.encode(dep_label)), indent + 2))
            lines.append(_ind("],", indent + 1))
        lines.append(_ind('"//conditions:default": [],', indent + 1))
        lines.append(_ind("})", indent))
    if trailing_comma:
        lines[-1] = lines[-1] + ","
    return lines
