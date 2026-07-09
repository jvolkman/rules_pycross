"""Implementation of the pycross_wheel_zipimport_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

def _pycross_wheel_zipimport_library_impl(ctx):
    wheel_files = ctx.files.wheel
    if len(wheel_files) != 1:
        fail("Expected exactly one file or directory for 'wheel' attribute")

    wheel_file = wheel_files[0]
    stable_wheel = ctx.actions.declare_file(ctx.attr.name + ".whl")

    args = ctx.actions.args()
    args.add(wheel_file.path)
    args.add(stable_wheel.path)

    ctx.actions.run(
        inputs = [wheel_file],
        outputs = [stable_wheel],
        executable = ctx.executable._link_wheel,
        arguments = [args],
        mnemonic = "PycrossLinkWheel",
        progress_message = "Linking/Copying wheel for %s" % ctx.attr.name,
    )

    extra_files = []

    # TODO: Is there a more correct way to get this runfiles-relative import path?
    imp = paths.join(
        ctx.label.workspace_name or ctx.workspace_name,  # Default to the local workspace.
        ctx.label.package,
        ctx.attr.name + ".whl",
    )

    merged = merge_py_providers(
        ctx,
        ctx.attr.deps,
        direct_sources = [stable_wheel] + extra_files,
        direct_imports = [imp],
        base_runfiles = ctx.runfiles(files = [stable_wheel] + extra_files),
        has_py3_only_sources = True,
    )

    return [
        DefaultInfo(
            files = depset(direct = [stable_wheel]),
            runfiles = merged.runfiles,
        ),
        merged.py_info,
    ]

pycross_wheel_zipimport_library = rule(
    implementation = _pycross_wheel_zipimport_library_impl,
    provides = [PyInfo],
    attrs = dict({
        "deps": attr.label_list(
            doc = "A list of this wheel's Python library dependencies.",
            providers = [DefaultInfo, PyInfo],
        ),
        "wheel": attr.label(
            doc = "The wheel file or directory.",
            allow_files = True,
            mandatory = True,
        ),
        "_link_wheel": attr.label(
            default = Label("//pycross/private/tools:link_wheel"),
            cfg = "exec",
            executable = True,
        ),
    }, **PY_COMMON_ATTRS),
)
