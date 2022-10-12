"""Implementation of the pycross_wheel_library rule."""

load(":providers.bzl", "PycrossWheelInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:defs.bzl", "PyInfo")

def _pycross_wheel_library_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.name)

    wheel_target = ctx.attr.wheel
    if PycrossWheelInfo in wheel_target:
        wheel_file = wheel_target[PycrossWheelInfo].wheel_file
        name_file = wheel_target[PycrossWheelInfo].name_file
    else:
        wheel_file = ctx.file.wheel
        name_file = None

    args = [
        "--wheel",
        wheel_file.path,
        "--directory",
        out.path,
    ]

    inputs = [wheel_file]
    if name_file:
        inputs.append(name_file)
        args.extend([
            "--wheel-name-file",
            name_file.path,
        ])

    if ctx.attr.enable_implicit_namespace_pkgs:
        args.append("--enable-implicit-namespace-pkgs")

    ctx.actions.run(
        inputs = inputs,
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
        # Set environment variables to make generated .pyc files reproducible.
        env = {
            "SOURCE_DATE_EPOCH": "315532800",
            "PYTHONHASHSEED": "0",
        },
        mnemonic = "WheelInstall",
        progress_message = "Installing %s" % ctx.file.wheel.basename,
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
    imp = paths.join(
        ctx.label.workspace_name or ctx.workspace_name,  # Default to the local workspace.
        ctx.label.package,
        ctx.label.name,
        "site-packages",  # we put lib files in this subdirectory.
    )

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
            uses_shared_libraries = True,  # Docs say this is unused
        ),
    ]

pycross_wheel_library = rule(
    implementation = _pycross_wheel_library_impl,
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
            doc = "The python version required for this wheel ('PY2' or 'PY3')",
            values = ["PY2", "PY3", ""]
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_installer"),
            cfg = "host",
            executable = True,
        ),
    }
)
