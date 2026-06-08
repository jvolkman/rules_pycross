"""Implementation of the pycross_wheel_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(
    ":providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
)

def _pycross_wheel_library_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.name)
    entry_points = ctx.actions.declare_file(ctx.attr.name + ".dist_info/entry_points.txt")

    wheelhouse = ctx.files.wheel[0]

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    if type(wheelhouse) == "File" and wheelhouse.is_directory:
        args.add("--wheelhouse", wheelhouse.path)
    else:
        # Plain file (e.g., local override wheel) — pass directly as --wheel
        args.add("--wheel", wheelhouse.path)
    args.add("--directory", out.path)
    args.add_all(ctx.files.post_install_patches, format_each = "--patch=%s")

    inputs = [wheelhouse] + ctx.files.post_install_patches

    if ctx.attr.enable_implicit_namespace_pkgs:
        args.add("--enable-implicit-namespace-pkgs")

    for install_exclude_glob in ctx.attr.install_exclude_globs:
        args.add("--install-exclude-glob", install_exclude_glob)

    args.add("--entry-points-output", entry_points)

    for patch in ctx.files.post_install_patches:
        args.add("--patch", patch)

    ctx.actions.run(
        inputs = inputs,
        outputs = [out, entry_points],
        executable = ctx.executable._tool,
        arguments = [args],
        # Set environment variables to make generated .pyc files reproducible.
        env = {
            "SOURCE_DATE_EPOCH": "315532800",
            "PYTHONHASHSEED": "0",
        },
        mnemonic = "WheelInstall",
        progress_message = "Installing %s" % wheelhouse.basename,
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

    direct_imports = [imp]
    if ctx.attr.top_level_packages:
        for tlp in ctx.attr.top_level_packages:
            direct_imports.append(paths.join(imp, tlp))

    imports = depset(
        direct = direct_imports,
        transitive = [d[PyInfo].imports for d in ctx.attr.deps],
    )
    transitive_sources = depset(
        direct = [out],
        transitive = [dep[PyInfo].transitive_sources for dep in ctx.attr.deps if PyInfo in dep],
    )
    runfiles = ctx.runfiles(files = [out])
    for d in ctx.attr.deps:
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)

    providers = [
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
        PycrossExtractedWheelInfo(
            site_packages = out,
        ),
        OutputGroupInfo(
            dist_info = depset([entry_points]),
        ),
    ]

    if ctx.attr.package_name:
        providers.append(
            PycrossPackageInfo(
                package_name = ctx.attr.package_name,
                package_version = ctx.attr.package_version,
            ),
        )

    return providers

pycross_wheel_library = rule(
    implementation = _pycross_wheel_library_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of this wheel's Python library dependencies.",
            providers = [DefaultInfo, PyInfo],
        ),
        "wheel": attr.label(
            doc = "The wheel file.",
            allow_files = True,
            mandatory = True,
        ),
        "install_exclude_globs": attr.string_list(
            doc = "A list of globs for files to exclude during installation.",
        ),
        "post_install_patches": attr.label_list(
            doc = "A list of patches to apply after installation.",
            allow_files = True,
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
            values = ["PY2", "PY3", ""],
        ),
        "package_name": attr.string(
            doc = "The name of the package. Used for providing PycrossPackageInfo.",
        ),
        "package_version": attr.string(
            doc = "The version of the package. Used for providing PycrossPackageInfo.",
        ),
        "top_level_packages": attr.string_list(
            doc = "The list of top-level Python packages provided by this wheel.",
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_installer"),
            cfg = "exec",
            executable = True,
        ),
    },
)
