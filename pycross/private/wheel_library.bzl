"""Implementation of the pycross_wheel_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
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
load(":deferred_failure.bzl", "register_failure_action", "unsupported_wheel_message")
load(
    ":providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
    "PycrossUnsupportedWheelInfo",
)
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers", "underscore_name")

_PYCROSS_TOOLCHAIN_TYPE = Label("//pycross:toolchain_type")

def _register_wheel_install_action(ctx, out, entry_points, dist_info_dir, expected_site_paths = []):
    if PycrossUnsupportedWheelInfo in ctx.attr.wheel:
        pkg_id = "{}{}".format(
            ctx.attr.package_name or ctx.label.name,
            "@{}".format(ctx.attr.package_version) if ctx.attr.package_version else "",
        )
        register_failure_action(
            ctx,
            outputs = [out, entry_points],
            message = unsupported_wheel_message(pkg_id),
            mnemonic = "PycrossUnsupportedWheel",
            progress_message = "Rejecting unsupported wheel %s" % pkg_id,
        )
        return None

    if not ctx.files.wheel:
        fail("Expected at least one wheel file or directory in 'wheel' attribute of {}".format(ctx.label))
    wheel_input = ctx.files.wheel[0]

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    if type(wheel_input) == "File" and wheel_input.is_directory:
        args.add_all([wheel_input], before_each = "--wheel-dir", expand_directories = False)
    else:
        # Plain file (e.g., local override wheel) — pass directly as --wheel
        args.add("--wheel", wheel_input)
    args.add_all([out], before_each = "--directory", expand_directories = False)
    args.add_all(ctx.files.post_install_patches, format_each = "--patch=%s")

    inputs = [wheel_input] + ctx.files.post_install_patches
    transitive_inputs = []
    tools = []
    supports_path_mapping = True

    for install_exclude_glob in ctx.attr.install_exclude_globs:
        args.add("--install-exclude-glob", install_exclude_glob)

    args.add("--entry-points-output", entry_points)

    if ctx.attr.package_name:
        args.add("--expected-name", ctx.attr.package_name)
    if ctx.attr.package_version:
        args.add("--expected-version", ctx.attr.package_version)
    if dist_info_dir:
        args.add("--dist-info-dir", dist_info_dir)
    for site_path in expected_site_paths:
        args.add("--expected-site-path", site_path)

    flag_precompile = ctx.attr._precompile[BuildSettingInfo].value
    if flag_precompile == "force_enabled":
        effective_precompile = "enabled"
    elif flag_precompile == "force_disabled":
        effective_precompile = "disabled"
    elif ctx.attr.precompile == "auto":
        effective_precompile = "enabled" if flag_precompile == "enabled" else "disabled"
    else:
        effective_precompile = ctx.attr.precompile

    precompile_cache_tag = None
    if (
        effective_precompile == "enabled" and
        _PYCROSS_TOOLCHAIN_TYPE in ctx.toolchains and
        ctx.toolchains[_PYCROSS_TOOLCHAIN_TYPE]
    ):
        pycross_info = ctx.toolchains[_PYCROSS_TOOLCHAIN_TYPE].pycross_info
        precompile_cache_tag = getattr(pycross_info, "bytecode_cache_tag", None)
        if ctx.attr.precompile_invalidation_mode != "auto":
            invalidation_mode = ctx.attr.precompile_invalidation_mode
        else:
            flag_mode = ctx.attr._precompile_invalidation_mode[BuildSettingInfo].value
            if flag_mode != "auto":
                invalidation_mode = flag_mode
            else:
                invalidation_mode = (
                    "unchecked_hash" if ctx.var.get("COMPILATION_MODE") == "opt" else "checked_hash"
                )
        exec_py_file = getattr(pycross_info, "exec_python_executable_file", None)
        if not exec_py_file and pycross_info.exec_python_files_to_run:
            exec_py_file = pycross_info.exec_python_files_to_run.executable
        if exec_py_file:
            args.add("--compile-python", exec_py_file)
        else:
            args.add("--compile-python", pycross_info.exec_python_executable)

            # A custom provider that hands us a raw bazel-out string cannot be
            # rewritten by Bazel's path mapper, so opt out for that case.
            if pycross_info.exec_python_executable.startswith("bazel-out/"):
                supports_path_mapping = False
        args.add("--compile-invalidation-mode", invalidation_mode)
        args.add("--compile-optimize", str(ctx.attr.precompile_optimize_level))
        compile_files = getattr(
            pycross_info,
            "exec_python_compile_files",
            pycross_info.exec_python_files,
        )
        if compile_files:
            transitive_inputs.append(compile_files)
        if pycross_info.exec_python_files_to_run:
            tools.append(pycross_info.exec_python_files_to_run)
        elif exec_py_file:
            tools.append(exec_py_file)

    ctx.actions.run(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out, entry_points],
        executable = ctx.executable._tool,
        tools = tools,
        mnemonic = "PycrossWheelInstall",
        execution_requirements = {"supports-path-mapping": "1"} if supports_path_mapping else {},
        arguments = [args],
        env = {
            "PYTHONHASHSEED": "0",
        },
        progress_message = "Installing %s" % wheel_input.basename,
    )

    return precompile_cache_tag

# A binary that reaches one package through two configurations gets two
# `VenvSymlinkEntry`s for it. With `files = depset([out])` they differ, since
# depsets compare by identity, so rules_python merges them as an overlap. Before
# rules_python #4396 (which added `link_to_subpaths`), that merge skipped
# entries backed by a directory artifact and dropped the package from the venv.
# There, pass an empty depset so the two entries are identical and collapse to
# one. rules_python reads `files` only when merging, and runfiles come from
# `DefaultInfo`. With #4396, keep `depset([out])`: the merge then links the
# first entry, and overlaps it can't merge fail loudly.
_NO_FILES = depset()
_MERGES_DIRECTORY_ENTRIES = hasattr(
    VenvSymlinkEntry(
        kind = VenvSymlinkKind.LIB,
        venv_path = "",
        link_to_path = "",
        package = None,
        version = None,
        files = _NO_FILES,
    ),
    "link_to_subpaths",
)

def _pyc_rel_path(py_rel_path, cache_tag, optimize_level):
    dirname = paths.dirname(py_rel_path)
    stem = paths.basename(py_rel_path)[:-3]  # strip ".py"
    opt_suffix = ".opt-{}".format(optimize_level) if optimize_level else ""
    pyc_name = "{}.{}{}.pyc".format(stem, cache_tag, opt_suffix)
    return paths.join(dirname, "__pycache__", pyc_name) if dirname else paths.join("__pycache__", pyc_name)

def _build_venv_symlinks(
        venvs_site_packages_enabled,
        out,
        imp,
        dist_info_dir,
        package_name,
        package_version,
        site_paths,
        bin_paths,
        data_paths,
        include_paths,
        precompile_cache_tag = None,
        precompile_optimize_level = 0):
    has_venv_paths = bool(site_paths or bin_paths or data_paths or include_paths)
    if not (venvs_site_packages_enabled and has_venv_paths):
        return []

    entry_files = depset([out]) if _MERGES_DIRECTORY_ENTRIES else _NO_FILES
    venv_symlinks = []
    for tlp in site_paths:
        venv_symlinks.append(VenvSymlinkEntry(
            kind = VenvSymlinkKind.LIB,
            link_to_path = paths.join(imp, tlp),
            package = package_name,
            version = package_version,
            venv_path = tlp,
            files = entry_files,
        ))
        if precompile_cache_tag and tlp.endswith(".py") and paths.basename(tlp) != ".py":
            pyc_rel = _pyc_rel_path(tlp, precompile_cache_tag, precompile_optimize_level)
            venv_symlinks.append(VenvSymlinkEntry(
                kind = VenvSymlinkKind.LIB,
                link_to_path = paths.join(imp, pyc_rel),
                package = package_name,
                version = package_version,
                venv_path = pyc_rel,
                files = entry_files,
            ))

    # Also add .dist-info directory symlink when Python modules are linked into
    # the venv's site-packages. When site_paths is empty we keep [imp] on
    # sys.path (which already exposes site-packages/*.dist-info), so linking
    # dist-info into the venv would expose the distribution twice to importlib.metadata.
    if site_paths and dist_info_dir:
        venv_symlinks.append(VenvSymlinkEntry(
            kind = VenvSymlinkKind.LIB,
            link_to_path = paths.join(imp, dist_info_dir),
            package = package_name,
            version = package_version,
            venv_path = dist_info_dir,
            files = entry_files,
        ))

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
                files = entry_files,
            ))

    if hasattr(VenvSymlinkKind, "DATA"):
        for p in data_paths:
            venv_symlinks.append(VenvSymlinkEntry(
                kind = getattr(VenvSymlinkKind, "DATA"),
                link_to_path = paths.join(base_dir, "data", p),
                package = package_name,
                version = package_version,
                venv_path = p,
                files = entry_files,
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
                    files = entry_files,
                ))

    return venv_symlinks

def _pycross_wheel_library_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.name)
    entry_points = ctx.actions.declare_file(ctx.attr.name + ".dist_info/entry_points.txt")
    dist_info_dir = None
    if ctx.attr.package_name and ctx.attr.package_version:
        dist_info_dir = "{}-{}.dist-info".format(
            underscore_name(ctx.attr.package_name),
            ctx.attr.package_version,
        )

    package_name = ctx.attr.package_name or ctx.label.name
    package_version = ctx.attr.package_version or ""

    wheel_pkg_info = ctx.attr.wheel[PycrossPackageInfo] if PycrossPackageInfo in ctx.attr.wheel else None
    site_paths = ctx.attr.site_paths
    site_paths_exact = bool(ctx.attr.site_paths)
    bin_paths = ctx.attr.bin_paths
    data_paths = ctx.attr.data_paths
    include_paths = ctx.attr.include_paths
    if not site_paths and wheel_pkg_info:
        site_paths = wheel_pkg_info.site_paths
        site_paths_exact = getattr(wheel_pkg_info, "site_paths_exact", True)
    if not bin_paths and wheel_pkg_info:
        bin_paths = wheel_pkg_info.bin_paths
    if not data_paths and wheel_pkg_info:
        data_paths = wheel_pkg_info.data_paths
    if not include_paths and wheel_pkg_info:
        include_paths = wheel_pkg_info.include_paths

    venvs_site_packages_enabled = VenvsSitePackages.is_enabled(ctx)

    # Only build venv LIB links (and verify installed top-level paths under
    # venvs_site_packages=yes) from exact wheel metadata or explicit site_paths
    # annotations. Repo-time sdist guesses stay advisory for modules_mapping
    # while keeping [imp] on sys.path.
    venv_site_paths = site_paths if site_paths_exact else []

    precompile_cache_tag = _register_wheel_install_action(
        ctx,
        out,
        entry_points,
        dist_info_dir,
        expected_site_paths = venv_site_paths if venvs_site_packages_enabled else [],
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
    venv_symlinks = _build_venv_symlinks(
        venvs_site_packages_enabled,
        out,
        imp,
        dist_info_dir,
        package_name,
        package_version,
        venv_site_paths,
        bin_paths,
        data_paths,
        include_paths,
        precompile_cache_tag = precompile_cache_tag,
        precompile_optimize_level = ctx.attr.precompile_optimize_level,
    )

    # With venvs_site_packages, wheels with exact/annotated site_paths are linked into the
    # venv's site-packages, so (like rules_python) don't also put their site-packages dir
    # on sys.path. Keep [imp] when venv_site_paths is empty (e.g. unannotated sdist builds).
    merged = merge_py_providers(
        ctx,
        ctx.attr.deps,
        direct_sources = [out],
        direct_imports = [] if (venvs_site_packages_enabled and venv_site_paths) else [imp],
        base_runfiles = ctx.runfiles(files = [out]),
        direct_venv_symlinks = venv_symlinks,
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

    if PycrossUnsupportedWheelInfo in ctx.attr.wheel:
        pkg_id = "{}{}".format(
            ctx.attr.package_name or ctx.label.name,
            "@{}".format(ctx.attr.package_version) if ctx.attr.package_version else "",
        )
        providers.append(PycrossUnsupportedWheelInfo(package = pkg_id))

    if ctx.attr.package_name:
        providers.append(
            PycrossPackageInfo(
                package_name = ctx.attr.package_name,
                package_version = ctx.attr.package_version,
                site_paths = site_paths,
                site_paths_exact = site_paths_exact,
                bin_paths = bin_paths,
                data_paths = data_paths,
                include_paths = include_paths,
            ),
        )

    return providers

_WHEEL_LIBRARY_ATTRS = dict({
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
    "package_name": attr.string(
        doc = "The name of the package. Used for providing PycrossPackageInfo.",
    ),
    "package_version": attr.string(
        doc = "The version of the package. Used for providing PycrossPackageInfo.",
    ),
    "site_paths": attr.string_list(doc = "The list of site-packages paths provided by this wheel."),
    "bin_paths": attr.string_list(doc = "The list of bin paths provided by this wheel."),
    "data_paths": attr.string_list(doc = "The list of data paths provided by this wheel."),
    "include_paths": attr.string_list(doc = "The list of include paths provided by this wheel."),
    "precompile": attr.string(
        default = "auto",
        values = ["auto", "enabled", "disabled"],
        doc = "Whether to compile Python source files to `.pyc` bytecode at wheel install time. `auto` (default) follows the `--@rules_python//python/config_settings:precompile` flag: compile only when it is `enabled` or `force_enabled`. `force_enabled`/`force_disabled` override `enabled`/`disabled` here. Unlike `py_library`, there is no `inherit`: a binary's `pyc_collection` does not apply to installed wheels.",
    ),
    "precompile_invalidation_mode": attr.string(
        default = "auto",
        values = ["auto", "checked_hash", "unchecked_hash"],
        doc = "The PEP 552 hash invalidation mode for generated `.pyc` files. `auto` follows `--@rules_pycross//pycross/settings:precompile_invalidation_mode` (defaulting to `unchecked_hash` when `--compilation_mode=opt` and `checked_hash` otherwise).",
    ),
    "precompile_optimize_level": attr.int(
        default = 0,
        values = [0, 1, 2],
        doc = "The Python bytecode optimization level passed to `py_compile.compile(optimize=...)`.",
    ),
    "_tool": attr.label(
        default = Label("//pycross/private/tools:wheel_installer"),
        cfg = "exec",
        executable = True,
    ),
    "_precompile": attr.label(
        default = Label("@rules_python//python/config_settings:precompile"),
    ),
    "_precompile_invalidation_mode": attr.label(
        default = Label("//pycross/settings:precompile_invalidation_mode"),
    ),
    "experimental_venvs_site_packages": attr.label(
        default = Label("@rules_python//python/config_settings:venvs_site_packages"),
    ),
}, **PY_COMMON_ATTRS)

def make_wheel_library_rule(cfg = None):
    """Create the `pycross_wheel_library` rule, optionally with an incoming transition.

    Args:
        cfg: An incoming-edge transition, or None.

    Returns:
        The rule.
    """
    attrs = dict(_WHEEL_LIBRARY_ATTRS)
    kwargs = {}
    if cfg:
        attrs["_allowlist_function_transition"] = attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        )
        kwargs["cfg"] = cfg
    return rule(
        doc = "Installs a Python wheel into a TreeArtifact directory and exposes it as a `PyInfo` library.",
        implementation = _pycross_wheel_library_impl,
        provides = [PyInfo, PycrossExtractedWheelInfo],
        attrs = attrs,
        toolchains = [
            config_common.toolchain_type("//pycross:toolchain_type", mandatory = False),
        ],
        **kwargs
    )

pycross_wheel_library = make_wheel_library_rule()

def _pycross_wheel_metadata_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.wheel)),
        PycrossPackageInfo(
            package_name = ctx.attr.package_name,
            package_version = ctx.attr.package_version,
            site_paths = ctx.attr.site_paths,
            site_paths_exact = ctx.attr.site_paths_exact,
            bin_paths = ctx.attr.bin_paths,
            data_paths = ctx.attr.data_paths,
            include_paths = ctx.attr.include_paths,
        ),
    ]

pycross_wheel_metadata = rule(
    doc = "Wraps a wheel target to provide `PycrossPackageInfo` metadata without installing the wheel.",
    implementation = _pycross_wheel_metadata_impl,
    provides = [PycrossPackageInfo],
    attrs = {
        "wheel": attr.label(
            doc = "The wheel file or wheel directory target.",
            allow_files = True,
            mandatory = True,
        ),
        "package_name": attr.string(doc = "The normalized package name."),
        "package_version": attr.string(doc = "The package version."),
        "site_paths": attr.string_list(doc = "The list of site-packages paths provided by this wheel."),
        "site_paths_exact": attr.bool(
            default = True,
            doc = "Whether site_paths is exact (True for inspected wheels, False for repo-time sdist guesses).",
        ),
        "bin_paths": attr.string_list(doc = "The list of bin paths provided by this wheel."),
        "data_paths": attr.string_list(doc = "The list of data paths provided by this wheel."),
        "include_paths": attr.string_list(doc = "The list of include paths provided by this wheel."),
    },
)

def _pycross_unsupported_wheel_impl(ctx):
    wheel = ctx.actions.declare_file(ctx.label.name + ".whl")
    register_failure_action(
        ctx,
        outputs = [wheel],
        message = unsupported_wheel_message(None),
        mnemonic = "PycrossUnsupportedWheel",
        progress_message = "Rejecting unsupported wheel",
    )
    return [
        DefaultInfo(
            files = depset([wheel]),
            runfiles = ctx.runfiles(files = [wheel]),
        ),
        PyInfo(transitive_sources = depset()),
        PycrossUnsupportedWheelInfo(package = ""),
    ]

pycross_unsupported_wheel = rule(
    doc = "Sentinel target used when no compatible wheel or branch matches the target environment under `fail_at_execution`.",
    implementation = _pycross_unsupported_wheel_impl,
    provides = [PyInfo, PycrossUnsupportedWheelInfo],
)
