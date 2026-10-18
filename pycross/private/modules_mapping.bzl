"""Rules for Gazelle modules mapping."""

load(":providers.bzl", "PycrossPackageInfo")

def _is_valid_identifier(s):
    """Checks if a given string is a valid Python identifier.

    A valid identifier must start with a letter or an underscore, followed by
    zero or more letters, underscores, and digits.

    Args:
        s: The string to check.

    Returns:
        True if the string is a valid identifier, False otherwise.
    """
    if not s or not (s[0].isalpha() or s[0] == "_"):
        return False
    for c in s[1:].elems():
        if not (c.isalnum() or c == "_"):
            return False
    return True

def _strip_extensions(module_name):
    for ext in [".pth", ".so", ".py", ".pyd"]:
        if not module_name.endswith(ext):
            continue
        module_name = module_name[:-len(ext)]
        if ".cpython-" in module_name:
            module_name = module_name.split(".cpython-")[0]
        elif ".abi3-" in module_name:
            module_name = module_name.split(".abi3-")[0]
        elif module_name.endswith(".abi3"):
            module_name = module_name[:-5]
        break
    return module_name

def _get_module_name(tlp):
    """Converts a top-level path (from site_paths) to a Python import name."""
    if not tlp:
        return None
    parts = tlp.split("/")
    parts[-1] = _strip_extensions(parts[-1])
    if parts[-1] == "__init__":
        parts = parts[:-1]
    if not parts:
        return None
    for part in parts:
        if not _is_valid_identifier(part):
            return None
    return ".".join(parts)

def _build_modules_mapping(pkg_infos):
    mapping = {}
    for pkg_info in pkg_infos:
        pkg_name = pkg_info.package_name.replace("-", "_")
        for tlp in pkg_info.site_paths:
            module_name = _get_module_name(tlp)
            if not module_name:
                continue
            mapping[module_name] = pkg_name

    simplified = {}
    for module_name, pkg_name in mapping.items():
        parts = module_name.split(".")
        has_same_pkg_ancestor = False
        for i in range(1, len(parts)):
            if mapping.get(".".join(parts[:i])) == pkg_name:
                has_same_pkg_ancestor = True
                break
        if not has_same_pkg_ancestor:
            simplified[module_name] = pkg_name

    return simplified

def _pycross_modules_mapping_impl(ctx):
    pkg_infos = [
        dep[PycrossPackageInfo]
        for dep in ctx.attr.deps
        if PycrossPackageInfo in dep
    ]
    mapping = _build_modules_mapping(pkg_infos)

    out = ctx.actions.declare_file(ctx.attr.name + ".json")
    ctx.actions.write(out, json.encode(mapping))
    return DefaultInfo(files = depset([out]))

# Visible for testing
get_module_name_for_testing = _get_module_name
build_modules_mapping_for_testing = _build_modules_mapping

pycross_modules_mapping = rule(
    implementation = _pycross_modules_mapping_impl,
    doc = """
    Generates a modules_mapping.json file mapping top-level Python import paths to package names.
    This is intended to be used with rules_python_gazelle_plugin to resolve third-party imports.
    """,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of package targets. Targets providing PycrossPackageInfo will be included in the mapping; others are silently skipped.",
        ),
    },
)
