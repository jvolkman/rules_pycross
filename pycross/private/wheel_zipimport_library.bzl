"""Implementation of the pycross_wheel_zipimport_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:defs.bzl", "PyInfo")

def _pycross_wheel_zipimport_library_impl(ctx):
    wheel_label = ctx.file.wheel.owner or ctx.attr.wheel.label
    wheel_file = ctx.file.wheel

    has_py2_only_sources = False
    has_py3_only_sources = True
    if not has_py2_only_sources:
        for d in ctx.attr.deps:
            if d[PyInfo].has_py2_only_sources:
                has_py2_only_sources = True
                break
    if not has_py3_only_sources:
        for d in ctx.attr.deps:
            if d[PyInfo].has_py3_only_sources:
                has_py3_only_sources = True
                break

    # TODO: Is there a more correct way to get this runfiles-relative import path?
    imp = paths.join(
        wheel_label.workspace_name or ctx.workspace_name,  # Default to the local workspace.
        wheel_label.package,
        wheel_label.name,
    )

    imports = depset(
        direct = [imp],
        transitive = [d[PyInfo].imports for d in ctx.attr.deps],
    )
    transitive_sources = depset(
        direct = [wheel_file],
        transitive = [dep[PyInfo].transitive_sources for dep in ctx.attr.deps if PyInfo in dep],
    )
    runfiles = ctx.runfiles(files = [wheel_file])
    for d in ctx.attr.deps:
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            files = depset(direct = [wheel_file]),
            runfiles = runfiles,
        ),
        PyInfo(
            has_py2_only_sources = has_py2_only_sources,
            has_py3_only_sources = has_py3_only_sources,
            imports = imports,
            transitive_sources = transitive_sources,
            uses_shared_libraries = True,  # Docs say this is unused
        ),
    ]

pycross_wheel_zipimport_library = rule(
    implementation = _pycross_wheel_zipimport_library_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of this wheel's Python library dependencies.",
            providers = [DefaultInfo, PyInfo],
        ),
        "wheel": attr.label(
            doc = "The wheel file.",
            allow_single_file = [".whl"],
            mandatory = True,
        ),
    },
)
