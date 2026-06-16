"""Implementation of the pycross_wheel_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_python//python/private:flags.bzl", "VenvsSitePackages")

# buildifier: disable=bzl-visibility
load(
    "@rules_python//python/private:py_info.bzl",
    "VenvSymlinkEntry",
    "VenvSymlinkKind",
)
load(
    ":providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
)

def _pycross_wheel_library_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.name)
    entry_points = ctx.actions.declare_file(ctx.attr.name + ".dist_info/entry_points.txt")

    wheel_input = ctx.files.wheel[0]

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    if type(wheel_input) == "File" and wheel_input.is_directory:
        args.add("--wheel-dir", wheel_input.path)
    else:
        # Plain file (e.g., local override wheel) — pass directly as --wheel
        args.add("--wheel", wheel_input.path)
    args.add("--directory", out.path)
    args.add_all(ctx.files.post_install_patches, format_each = "--patch=%s")

    inputs = [wheel_input] + ctx.files.post_install_patches

    for install_exclude_glob in ctx.attr.install_exclude_globs:
        args.add("--install-exclude-glob", install_exclude_glob)

    args.add("--entry-points-output", entry_points)

    ctx.actions.run(
        inputs = inputs,
        outputs = [out, entry_points],
        executable = ctx.executable._tool,
        mnemonic = "PycrossWheelInstall",
        execution_requirements = {"supports-path-mapping": "1"},
        arguments = [args],
        # Set environment variables to make generated .pyc files reproducible.
        env = {
            "SOURCE_DATE_EPOCH": "315532800",
            "PYTHONHASHSEED": "0",
        },
        progress_message = "Installing %s" % wheel_input.basename,
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
        transitive = [dep[PyInfo].transitive_sources for dep in ctx.attr.deps if PyInfo in dep],
    )
    runfiles = ctx.runfiles(files = [out])
    for d in ctx.attr.deps:
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)

    # Build venv symlink entries for rules_python's venvs_site_packages support.
    # Each top-level package gets a symlink from the venv's site-packages/<tlp>
    # to the runfiles location <repo>/<pkg>/<name>/site-packages/<tlp>.
    venv_symlinks = []
    package_name = ctx.attr.package_name or ctx.label.name
    package_version = ctx.attr.package_version or ""

    top_level_paths = ctx.attr.top_level_paths
    if not top_level_paths and PycrossPackageInfo in ctx.attr.wheel:
        top_level_paths = ctx.attr.wheel[PycrossPackageInfo].top_level_paths

    venvs_site_packages_enabled = VenvsSitePackages.is_enabled(ctx)

    if venvs_site_packages_enabled and top_level_paths:
        for tlp in top_level_paths:
            venv_symlinks.append(VenvSymlinkEntry(
                kind = VenvSymlinkKind.LIB,
                link_to_path = paths.join(imp, tlp),
                package = package_name,
                version = package_version,
                venv_path = tlp,
                files = depset([out]),
            ))

        # Also add .dist-info directory symlink so metadata is accessible.
        dist_info_candidates = [
            "{}-{}.dist-info".format(package_name.replace("-", "_"), package_version),
            "{}-{}.dist-info".format(package_name, package_version),
        ]
        for dist_info_dir in dist_info_candidates:
            venv_symlinks.append(VenvSymlinkEntry(
                kind = VenvSymlinkKind.LIB,
                link_to_path = paths.join(imp, dist_info_dir),
                package = package_name,
                version = package_version,
                venv_path = dist_info_dir,
                files = depset([out]),
            ))
            break  # Only need one

        # Add other directory symlinks if supported by the rules_python version.
        base_dir = paths.dirname(imp)
        
        if hasattr(VenvSymlinkKind, "BIN"):
            venv_symlinks.append(VenvSymlinkEntry(
                kind = getattr(VenvSymlinkKind, "BIN"),
                link_to_path = paths.join(base_dir, "bin"),
                package = package_name,
                version = package_version,
                venv_path = "",
                files = depset([out]),
            ))
            
        if hasattr(VenvSymlinkKind, "DATA"):
            venv_symlinks.append(VenvSymlinkEntry(
                kind = getattr(VenvSymlinkKind, "DATA"),
                link_to_path = paths.join(base_dir, "data"),
                package = package_name,
                version = package_version,
                venv_path = "",
                files = depset([out]),
            ))

    py_info_kwargs = dict(
        has_py2_only_sources = has_py2_only_sources,
        has_py3_only_sources = has_py3_only_sources,
        imports = imports,
        transitive_sources = transitive_sources,
        uses_shared_libraries = True,  # Docs say this is unused
    )
    if venvs_site_packages_enabled:
        transitive_venv_symlinks = []
        for d in ctx.attr.deps:
            if hasattr(d[PyInfo], "venv_symlinks"):
                transitive_venv_symlinks.append(d[PyInfo].venv_symlinks)

        py_info_kwargs["venv_symlinks"] = depset(
            direct = venv_symlinks,
            transitive = transitive_venv_symlinks,
        )

    providers = [
        DefaultInfo(
            files = depset(direct = [out]),
            runfiles = runfiles,
        ),
        PyInfo(**py_info_kwargs),
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
                top_level_paths = top_level_paths,
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
        "top_level_paths": attr.string_list(
            doc = "The list of top-level importable paths (packages, .pth files, standalone modules) provided by this wheel.",
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_installer"),
            cfg = "exec",
            executable = True,
        ),
        "experimental_venvs_site_packages": attr.label(
            default = Label("@rules_python//python/config_settings:venvs_site_packages"),
        ),
    },
)

def _pycross_wheel_metadata_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.wheel)),
        PycrossPackageInfo(
            package_name = ctx.attr.package_name,
            package_version = ctx.attr.package_version,
            top_level_paths = ctx.attr.top_level_paths,
        ),
    ]

pycross_wheel_metadata = rule(
    implementation = _pycross_wheel_metadata_impl,
    attrs = {
        "wheel": attr.label(allow_files = True, mandatory = True),
        "package_name": attr.string(),
        "package_version": attr.string(),
        "top_level_paths": attr.string_list(),
    },
)
