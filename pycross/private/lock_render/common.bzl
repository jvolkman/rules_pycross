"""Shared indentation, cycle, wheel-target, and attribute helpers for lock rendering."""

def ind(text, tabs = 1):
    """Indent `text` by `tabs` 4-space levels, leaving empty lines blank.

    Args:
        text: Line content.
        tabs: Indentation depth (4 spaces per level).

    Returns:
        Indented string, or `""` when `text` is empty.
    """
    if not text:
        return ""
    return ("    " * tabs) + text

def is_in_same_cycle(dep_key, pkg, packages):
    """Return whether `dep_key` belongs to the same cycle group as `pkg`.

    Args:
        dep_key: Dependency package key.
        pkg: Package dict for the dependent package.
        packages: All packages in the lock.

    Returns:
        True if both packages belong to the same cycle group.
    """
    cycle_group = pkg.get("cycle_group")
    if not cycle_group:
        return False
    dep_pkg = packages.get(dep_key)
    if not dep_pkg:
        return False
    return dep_pkg.get("cycle_group") == cycle_group

def wheel_target(file_ref, repo_map):
    """Resolve a wheel or sdist `file_reference` to its repository label, or None.

    Args:
        file_ref: Dict with `label` or `key`.
        repo_map: Map of file key -> repository label.

    Returns:
        Label string or None if unresolved.
    """
    return file_ref.get("label") or repo_map.get(file_ref.get("key"))

def render_str_list_attr(lines, attr_name, values):
    """Append a multi-line string-list attribute assignment to `lines` when `values` is non-empty.

    Args:
        lines: Output list of generated `.bzl` lines.
        attr_name: Target attribute name.
        values: Optional iterable of string values.
    """
    if values:
        lines.append(ind("{} = [".format(attr_name), 2))
        for val in values:
            lines.append(ind('"{}",'.format(val), 3))
        lines.append(ind("],", 2))
