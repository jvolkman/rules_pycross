"""Rules for Gazelle modules mapping."""

load(":providers.bzl", "PycrossPackageInfo")

def _pycross_modules_mapping_impl(ctx):
    mapping = {}

    for dep in ctx.attr.deps:
        if PycrossPackageInfo in dep:
            pkg_info = dep[PycrossPackageInfo]
            for tlp in pkg_info.top_level_paths:
                # Convert filesystem paths to Python import names:
                #   "google/cloud/storage" -> "google.cloud.storage"
                #   "requests" -> "requests"
                #   "six.py" -> "six"
                module_name = tlp
                for ext in [".pth", ".so", ".py"]:
                    if module_name.endswith(ext):
                        module_name = module_name[:-len(ext)]
                        break
                module_name = module_name.replace("/", ".")
                mapping[module_name] = pkg_info.package_name.replace("-", "_")

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
    },
)
