"""Implementation of the pycross_wheel_library rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(":providers.bzl", "PycrossWheelInfo")

def _pycross_wheel_library_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.name)
    install_outputs = [out]

    enable_cc = ctx.attr.cc_hdrs_globs or ctx.attr.cc_deps or ctx.attr.cc_includes

    wheel_target = ctx.attr.wheel
    if PycrossWheelInfo in wheel_target:
        wheel_file = wheel_target[PycrossWheelInfo].wheel_file
        name_file = wheel_target[PycrossWheelInfo].name_file
    else:
        wheel_file = ctx.file.wheel
        name_file = None

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--wheel", wheel_file)
    args.add("--directory", out.path)

    inputs = [wheel_file]
    if name_file:
        inputs.append(name_file)
        args.add("--wheel-name-file", name_file)

    if ctx.attr.enable_implicit_namespace_pkgs:
        args.add("--enable-implicit-namespace-pkgs")

    for install_exclude_glob in ctx.attr.install_exclude_globs:
        args.add("--install-exclude-glob", install_exclude_glob)

    cc_hdrs = None
    if enable_cc:
        # This needs to end in .h so the C/C++ rules know it has header files.
        # Those rules normally split out header files by extension, but that
        # logic doesn't have access to the filenames inside a tree artifact, so
        # we need to do the filtering ourselves and then put the correct
        # extension on the folder name.
        cc_hdrs = ctx.actions.declare_directory(ctx.attr.name + "__hdrs.h")
        install_outputs.append(cc_hdrs)
        args.add("--cc-hdrs-directory", cc_hdrs.path)

        for cc_hdrs_glob in ctx.attr.cc_hdrs_globs:
            args.add("--cc-hdrs-glob", cc_hdrs_glob)
            args.add("--install-exclude-glob", cc_hdrs_glob)

    ctx.actions.run(
        inputs = inputs,
        outputs = install_outputs,
        executable = ctx.executable._tool,
        arguments = [args],
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
    ]

    if enable_cc:
        cc_toolchain = find_cpp_toolchain(ctx)
        feature_configuration = cc_common.configure_features(
            ctx = ctx,
            cc_toolchain = cc_toolchain,
            requested_features = [],
            unsupported_features = [],
        )
        (compilation_context, compilation_outputs) = cc_common.compile(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            public_hdrs = [cc_hdrs],
            includes = [paths.join(
                cc_hdrs.path,
                include,
            ) for include in ctx.attr.cc_includes],
            compilation_contexts = [dep[CcInfo].compilation_context for dep in ctx.attr.cc_deps],
            name = ctx.attr.name + "__cc_compile",
        )
        (linking_context, _) = cc_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            name = ctx.attr.name + "__cc",
            compilation_outputs = compilation_outputs,
            linking_contexts = [dep[CcInfo].linking_context for dep in ctx.attr.cc_deps],
        )
        providers.append(CcInfo(
            compilation_context = compilation_context,
            linking_context = linking_context,
        ))

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
            allow_single_file = [".whl"],
            mandatory = True,
        ),
        "install_exclude_globs": attr.string_list(
            doc = "A list of globs for files to exclude during installation.",
        ),
        "cc_hdrs_globs": attr.string_list(
            doc = "A list of globs for files to use as C/C++ header files.",
            default = [],
        ),
        "cc_deps": attr.label_list(
            doc = "Dependencies for the C/C++ files.",
            providers = [CcInfo],
            default = [],
        ),
        "cc_includes": attr.string_list(
            doc = "C/C++ include directories.",
            default = [],
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
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_installer"),
            cfg = "exec",
            executable = True,
        ),
    },
    fragments = ["cpp"],
    toolchains = use_cpp_toolchain(),
)
