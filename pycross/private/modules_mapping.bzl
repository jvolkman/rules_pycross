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
    if not s:
        return False
    is_first = True
    for c in s.elems():
        if is_first:
            if not (c.isalpha() or c == "_"):
                return False
            is_first = False
        elif not (c.isalnum() or c == "_"):
            return False
    return True

def _strip_extensions(module_name):
    for ext in [".pth", ".so", ".py", ".pyd"]:
        if module_name.endswith(ext):
            module_name = module_name[:-len(ext)]
            if ".cpython-" in module_name:
                module_name = module_name.split(".cpython-")[0]
            elif ".abi3-" in module_name:
                module_name = module_name.split(".abi3-")[0]
            elif module_name.endswith(".abi3"):
                module_name = module_name[:-5]
            break
    return module_name

def _is_valid_module_name(module_name):
    for c in module_name.split("."):
        if not _is_valid_identifier(c):
            return False
    return True

def _get_module_name(tlp):
    """Converts a top-level path (from site_paths) to a Python import name."""
    module_name = _strip_extensions(tlp).replace("/", ".")
    if not _is_valid_module_name(module_name):
        return None
    return module_name

def _pycross_modules_mapping_impl(ctx):
    mapping = {}
    extras_mapping = ctx.attr.extras_mapping

    for dep in ctx.attr.deps:
        if PycrossPackageInfo in dep:
            pkg_info = dep[PycrossPackageInfo]
            for tlp in pkg_info.site_paths:
                module_name = _get_module_name(tlp)
                if not module_name:
                    continue

                base_name = pkg_info.package_name.replace("-", "_")

                # If this package has an extras override (e.g. foo -> foo[grpc]),
                # use the extra-qualified name so Gazelle emits the right dep.
                mapping[module_name] = extras_mapping.get(base_name, base_name)

    out = ctx.actions.declare_file(ctx.attr.name + ".json")
    ctx.actions.write(out, json.encode(mapping))
    return DefaultInfo(files = depset([out]))

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
        "extras_mapping": attr.string_dict(
            doc = "A mapping from base package name to extra-qualified name (e.g. {'foo': 'foo[grpc]'}). When set, Gazelle will resolve imports from these packages to the extra-qualified target.",
            default = {},
        ),
    },
)
