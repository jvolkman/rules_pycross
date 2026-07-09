"""Implementation of the pycross_wheel_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")

# buildifier: disable=bzl-visibility
load(
    "@rules_python//python/private:flags.bzl",
    "VenvsSitePackages",
)

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
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

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

    if ctx.attr.package_name:
        args.add("--expected-name", ctx.attr.package_name)
    if ctx.attr.package_version:
        args.add("--expected-version", ctx.attr.package_version)

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

    # TODO: Is there a more correct way to get this runfiles-relative import path?
    imp = paths.join(
        ctx.label.workspace_name or ctx.workspace_name,  # Default to the local workspace.
        ctx.label.package,
        ctx.label.name,
        "site-packages",  # we put lib files in this subdirectory.
    )

    # Build venv symlink entries for rules_python's venvs_site_packages support.
    # Each top-level package gets a symlink from the venv's site-packages/<tlp>
    # to the runfiles location <repo>/<pkg>/<name>/site-packages/<tlp>.
    venv_symlinks = []
    package_name = ctx.attr.package_name or ctx.label.name
    package_version = ctx.attr.package_version or ""

    site_paths = ctx.attr.site_paths
    bin_paths = ctx.attr.bin_paths + ctx.attr.console_scripts
    data_paths = ctx.attr.data_paths
    include_paths = ctx.attr.include_paths
    if not site_paths and PycrossPackageInfo in ctx.attr.wheel:
        site_paths = ctx.attr.wheel[PycrossPackageInfo].site_paths
    if not bin_paths and PycrossPackageInfo in ctx.attr.wheel:
        bin_paths = ctx.attr.wheel[PycrossPackageInfo].bin_paths
    if not data_paths and PycrossPackageInfo in ctx.attr.wheel:
        data_paths = ctx.attr.wheel[PycrossPackageInfo].data_paths
    if not include_paths and PycrossPackageInfo in ctx.attr.wheel:
        include_paths = ctx.attr.wheel[PycrossPackageInfo].include_paths

    venvs_site_packages_enabled = VenvsSitePackages.is_enabled(ctx)

    if venvs_site_packages_enabled and site_paths:
        for tlp in site_paths:
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
            for p in bin_paths:
                venv_symlinks.append(VenvSymlinkEntry(
                    kind = getattr(VenvSymlinkKind, "BIN"),
                    link_to_path = paths.join(base_dir, "bin", p),
                    package = package_name,
                    version = package_version,
                    venv_path = p,
                    files = depset([out]),
                ))

        if hasattr(VenvSymlinkKind, "DATA"):
            for p in data_paths:
                venv_symlinks.append(VenvSymlinkEntry(
                    kind = getattr(VenvSymlinkKind, "DATA"),
                    link_to_path = paths.join(base_dir, "data", p),
                    package = package_name,
                    version = package_version,
                    venv_path = p,
                    files = depset([out]),
                ))

            # VenvSymlinkKind.INCLUDE existed in earlier versions of rules_python but was missing from venv_dir_map.
            # It was properly added in the same commit that introduced VenvSymlinkKind.DATA.
            if hasattr(VenvSymlinkKind, "INCLUDE"):
                for p in include_paths:
                    venv_symlinks.append(VenvSymlinkEntry(
                        kind = getattr(VenvSymlinkKind, "INCLUDE"),
                        link_to_path = paths.join(base_dir, "include", p),
                        package = package_name,
                        version = package_version,
                        venv_path = p,
                        files = depset([out]),
                    ))

    merged = merge_py_providers(
        ctx,
        ctx.attr.deps,
        direct_sources = [out],
        direct_imports = [imp],
        base_runfiles = ctx.runfiles(files = [out]),
        direct_venv_symlinks = venv_symlinks,
        has_py2_only_sources = ctx.attr.python_version == "PY2",
        has_py3_only_sources = ctx.attr.python_version == "PY3",
    )

    providers = [
        DefaultInfo(
            files = depset(direct = [out]),
            runfiles = merged.runfiles,
        ),
        merged.py_info,
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
                site_paths = site_paths,
                bin_paths = bin_paths,
                data_paths = data_paths,
                include_paths = include_paths,
            ),
        )

    return providers

pycross_wheel_library = rule(
    implementation = _pycross_wheel_library_impl,
    provides = [PyInfo, PycrossExtractedWheelInfo],
    attrs = dict({
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
        "site_paths": attr.string_list(doc = "The list of site-packages paths provided by this wheel."),
        "bin_paths": attr.string_list(doc = "The list of bin paths provided by this wheel."),
        "console_scripts": attr.string_list(doc = "Deprecated: Use bin_paths instead."),
        "data_paths": attr.string_list(doc = "The list of data paths provided by this wheel."),
        "include_paths": attr.string_list(doc = "The list of include paths provided by this wheel."),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_installer"),
            cfg = "exec",
            executable = True,
        ),
        "experimental_venvs_site_packages": attr.label(
            default = Label("@rules_python//python/config_settings:venvs_site_packages"),
        ),
    }, **PY_COMMON_ATTRS),
)

def _pycross_wheel_metadata_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.wheel)),
        PycrossPackageInfo(
            package_name = ctx.attr.package_name,
            package_version = ctx.attr.package_version,
            site_paths = ctx.attr.site_paths,
            bin_paths = ctx.attr.bin_paths + ctx.attr.console_scripts,
            data_paths = ctx.attr.data_paths,
            include_paths = ctx.attr.include_paths,
        ),
    ]

pycross_wheel_metadata = rule(
    implementation = _pycross_wheel_metadata_impl,
    provides = [PycrossPackageInfo],
    attrs = {
        "wheel": attr.label(allow_files = True, mandatory = True),
        "package_name": attr.string(),
        "package_version": attr.string(),
        "site_paths": attr.string_list(doc = "The list of site-packages paths provided by this wheel."),
        "bin_paths": attr.string_list(doc = "The list of bin paths provided by this wheel."),
        "console_scripts": attr.string_list(doc = "Deprecated: Use bin_paths instead."),
        "data_paths": attr.string_list(doc = "The list of data paths provided by this wheel."),
        "include_paths": attr.string_list(doc = "The list of include paths provided by this wheel."),
    },
)
