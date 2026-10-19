"""Rules for Gazelle modules mapping."""

load(":providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")

def _pycross_modules_mapping_impl(ctx):
    # Deps with a per-wheel index are mapped from the installed wheel; the same index can arrive
    # through several deps (e.g. a package and its extras), so dedupe by file.
    indexes = {}

    # Deps without one fall back to the analysis-time site_paths in PycrossPackageInfo.
    site_paths = []
    for dep in ctx.attr.deps:
        index = None
        if PycrossExtractedWheelInfo in dep:
            index = getattr(dep[PycrossExtractedWheelInfo], "index", None)
        if index:
            indexes[index] = True
        elif PycrossPackageInfo in dep:
            pkg_info = dep[PycrossPackageInfo]
            for tlp in pkg_info.site_paths:
                site_paths.append("{}={}".format(pkg_info.package_name, tlp))

    out = ctx.actions.declare_file(ctx.attr.name + ".json")
    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--output", out)
    args.add_all(indexes.keys(), before_each = "--index")
    args.add_all(site_paths, before_each = "--site-path")
    ctx.actions.run(
        inputs = indexes.keys(),
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = [args],
        mnemonic = "PycrossModulesMapping",
        progress_message = "Generating Gazelle modules mapping %{output}",
    )
    return DefaultInfo(files = depset([out]))

pycross_modules_mapping = rule(
    implementation = _pycross_modules_mapping_impl,
    doc = """
    Generates a modules_mapping.json file mapping Python import names to package names.
    This is intended to be used with rules_python_gazelle_plugin to resolve third-party imports.

    The mapping is built from the per-wheel index that each installed wheel's install action
    writes, so building it installs every dep (building sdists where needed). Namespace packages
    are never mapped themselves, and names that several packages provide are dropped; the
    modules and packages below them map to the package that provides them.
    """,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of package targets. Targets providing PycrossExtractedWheelInfo with an index are mapped from their installed files; targets providing only PycrossPackageInfo are mapped from its site_paths; others are silently skipped.",
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:modules_mapping"),
            cfg = "exec",
            executable = True,
        ),
    },
)
