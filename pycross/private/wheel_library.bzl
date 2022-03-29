"""Implementation of the pycross_wheel_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:defs.bzl", "PyInfo")

def _pycross_wheel_library_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.name)

    args = [
        "--wheel",
        ctx.file.wheel.path,
        "--directory",
        out.path,
    ]

    if ctx.attr.enable_implicit_namespace_pkgs:
        args.append("--enable-implicit-namespace-pkgs")

    ctx.actions.run(
        inputs = [ctx.file.wheel],
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
    )

    has_py2_only_sources = ctx.attr.python_version == "PY2"
    has_py3_only_sources = ctx.attr.python_version == "PY3"
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
    imp = paths.join(ctx.workspace_name, ctx.label.package, ctx.label.name)

    imports = depset(
        direct = [imp],
        transitive = [d[PyInfo].imports for d in ctx.attr.deps],
    )
    transitive_sources = depset(
        direct = [out],
        transitive = [d[PyInfo].transitive_sources for d in ctx.attr.deps],
    )
    runfiles = ctx.runfiles(files = [out])
    for d in ctx.attr.deps:
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            files = depset(direct = [out]),
            runfiles = runfiles,
        ),
        PyInfo(
            has_py2_only_sources = has_py2_only_sources,
            has_py3_only_sources = has_py3_only_sources,
            imports = imports,
            transitive_sources = transitive_sources,
        ),
    ]

pycross_wheel_library = rule(
    implementation = _pycross_wheel_library_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of this wheel's Python library dependencies.",
        ),
        "wheel": attr.label(
            doc = "The wheel file.",
            allow_single_file = [".whl"],
            mandatory = True,
        ),
        "enable_implicit_namespace_pkgs": attr.bool(
        default = True,
        doc = """
If true, disables conversion of native namespace packages into pkg-util style namespace packages. When set all py_binary
and py_test targets must specify either `legacy_create_init=False` or the global Bazel option
`--incompatible_default_to_explicit_init_py` to prevent `__init__.py` being automatically generated in every directory.
This option is required to support some packages which cannot handle the conversion to pkg-util style.
            """,
        ),
        "python_version": attr.string(
            doc = "The python version required for this wheel.",
            values = ["PY2", "PY3", ""]
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools/extract_wheels:extract"),
            cfg = "host",
            executable = True,
        ),
    }
)
