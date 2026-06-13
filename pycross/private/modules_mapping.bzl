"""Rules for Gazelle modules mapping."""

load(":providers.bzl", "PycrossPackageInfo")

def _pycross_modules_mapping_impl(ctx):
    mapping = {}

    for dep in ctx.attr.deps:
        if PycrossPackageInfo in dep:
            pkg_info = dep[PycrossPackageInfo]
            for tlp in pkg_info.top_level_paths:
                # Normalize top level path back to import style (e.g. google/cloud -> google.cloud)
                # Wait, modules_mapping.json usually expects top level modules, maybe not nested?
                # Actually, rules_python Gazelle uses `module_name` exactly as it appears in import.
                # If tlp is "google/cloud/storage", the import is "google.cloud.storage".
                module_name = tlp.replace("/", ".").removesuffix(".py")
                mapping[module_name] = pkg_info.package_name

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
            doc = "A list of pycross_wheel_library targets.",
            providers = [PycrossPackageInfo],
        ),
    },
)
