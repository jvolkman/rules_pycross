"""Rule-only helpers for merging rules_python PyInfo and DefaultInfo providers."""

load("@rules_python//python/api:api.bzl", "py_common")

# Attrs that consuming rules must include for merge_py_providers to work.
PY_COMMON_ATTRS = py_common.API_ATTRS

def merge_py_providers(
        ctx,
        deps,
        direct_sources = [],
        direct_imports = [],
        base_runfiles = None,
        direct_venv_symlinks = [],
        has_py2_only_sources = False,
        has_py3_only_sources = False,
        uses_shared_libraries = True):
    """Merges PyInfo and DefaultInfo from deps with optional direct entries.

    Uses rules_python's PyInfoBuilder to ensure all PyInfo fields (including
    pyc files, pyi stubs, and venv symlinks) are properly merged.

    The consuming rule must include PY_COMMON_ATTRS in its attrs dict.

    Args:
        ctx: The rule context (must have PY_COMMON_ATTRS in its rule attrs).
        deps: List of Target objects providing PyInfo and DefaultInfo.
        direct_sources: Files to add as direct entries to transitive_sources.
        direct_imports: Strings to add as direct entries to imports.
        base_runfiles: A Runfiles object (e.g. from ctx.runfiles) to merge with dep runfiles.
        direct_venv_symlinks: VenvSymlinkEntry values to add directly.
        has_py2_only_sources: Whether this target has PY2-only sources.
        has_py3_only_sources: Whether this target has PY3-only sources.
        uses_shared_libraries: Whether to set uses_shared_libraries on PyInfo.

    Returns:
        A struct with fields:
          - py_info: A PyInfo provider.
          - runfiles: The merged Runfiles object.
    """
    api = py_common.get(ctx)
    builder = api.PyInfoBuilder()

    # Merge all dep PyInfos as transitive.
    builder.merge_targets(deps)

    # Add our own direct content.
    builder.transitive_sources.add(direct_sources)
    builder.imports.add(direct_imports)
    if direct_venv_symlinks:
        builder.venv_symlinks.add(direct_venv_symlinks)

    if has_py2_only_sources:
        builder.set_has_py2_only_sources(True)
    if has_py3_only_sources:
        builder.set_has_py3_only_sources(True)
    if uses_shared_libraries:
        builder.set_uses_shared_libraries(True)

    py_info = builder.build()

    # Merge runfiles from all deps in a single merge_all call.
    dep_runfiles = [
        dep[DefaultInfo].default_runfiles
        for dep in deps
        if dep[DefaultInfo].default_runfiles
    ]
    if base_runfiles != None:
        runfiles = base_runfiles.merge_all(dep_runfiles) if dep_runfiles else base_runfiles
    elif not dep_runfiles:
        runfiles = None
    elif len(dep_runfiles) == 1:
        runfiles = dep_runfiles[0]
    else:
        runfiles = dep_runfiles[0].merge_all(dep_runfiles[1:])

    return struct(
        py_info = py_info,
        runfiles = runfiles,
    )
