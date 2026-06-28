"""Implementation of the pycross_wheel_zipimport_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

def _pycross_wheel_zipimport_library_impl(ctx):
    wheel_label = ctx.file.wheel.owner or ctx.attr.wheel.label
    wheel_file = ctx.file.wheel
    extra_files = []

    # TODO: Is there a more correct way to get this runfiles-relative import path?
    imp = paths.join(
        wheel_label.workspace_name or ctx.workspace_name,  # Default to the local workspace.
        wheel_label.package,
        wheel_label.name,
    )

    merged = merge_py_providers(
        ctx,
        ctx.attr.deps,
        direct_sources = [wheel_file] + extra_files,
        direct_imports = [imp],
        base_runfiles = ctx.runfiles(files = [wheel_file] + extra_files),
        has_py3_only_sources = True,
    )

    return [
        DefaultInfo(
            files = depset(direct = [wheel_file]),
            runfiles = merged.runfiles,
        ),
        merged.py_info,
    ]

pycross_wheel_zipimport_library = rule(
    implementation = _pycross_wheel_zipimport_library_impl,
    attrs = dict({
        "deps": attr.label_list(
            doc = "A list of this wheel's Python library dependencies.",
            providers = [DefaultInfo, PyInfo],
        ),
        "wheel": attr.label(
            doc = "The wheel file.",
            allow_single_file = [".whl"],
            mandatory = True,
        ),
    }, **PY_COMMON_ATTRS),
)
