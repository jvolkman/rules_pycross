"""Rules for using C/C++ headers and libraries that ship inside an installed wheel."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossWheelSharedLibraryInfo")
load("//pycross/private/build:cc_toolchain_util.bzl", "absolutize_path_in_str", "configure_features")
load("//pycross/private/build:wheel_shared_libraries.bzl", "collect_wheel_shared_libraries", "wheel_shared_libraries")
load("//pycross/private/build/rules:common_attrs.bzl", "CC_FRAGMENTS", "CC_TOOLCHAINS")

def _wheel_path(attr_name, value):
    """Checks a site-packages-relative path from an attribute and normalizes it."""
    normalized = paths.normalize(value)
    if paths.is_absolute(value) or normalized == ".." or normalized.startswith("../"):
        fail("{} must be a path inside the wheel's site-packages, got '{}'".format(attr_name, value))
    return normalized

def _copy_from_wheel(ctx, site_packages, attr_name, rel_path):
    """Copies one file out of the installed wheel tree so it can be linked."""

    # One directory per attribute, so libraries with the same file name don't collide
    # (e.g. Windows static and import libraries), and each gets its own --lib-dir.
    out = ctx.actions.declare_file("_{}/{}/{}".format(ctx.label.name, attr_name, paths.basename(rel_path)))

    args = ctx.actions.args()
    args.add_all([site_packages], expand_directories = False)
    args.add(rel_path)
    args.add(attr_name)
    args.add(out)

    ctx.actions.run(
        executable = ctx.executable._extract_wheel_lib,
        arguments = [args],
        inputs = [site_packages],
        outputs = [out],
        mnemonic = "PycrossExtractWheelLib",
        execution_requirements = {"supports-path-mapping": "1"},
        progress_message = "Extracting %s from %s" % (rel_path, ctx.attr.wheel_library.label),
    )
    return out

def _pycross_wheel_cc_import_impl(ctx):
    site_packages = getattr(ctx.attr.wheel_library[PycrossExtractedWheelInfo], "site_packages", None)
    if not site_packages:
        fail("The target provided to `wheel_library` does not provide an extracted site-packages directory. Make sure to use a `pycross_wheel_library` target.")
    root = site_packages.path + "/site-packages"

    includes = [paths.join(root, _wheel_path("includes", inc)) for inc in ctx.attr.includes]
    compilation_context = cc_common.create_compilation_context(
        headers = depset([site_packages]),
        includes = depset(includes),
    )

    libraries = {}
    for attr_name in ("static_library", "shared_library", "interface_library"):
        rel_path = getattr(ctx.attr, attr_name)
        if rel_path:
            libraries[attr_name] = _copy_from_wheel(ctx, site_packages, attr_name, _wheel_path(attr_name, rel_path))

    linking_context = None
    if libraries or ctx.attr.linkopts:
        library_to_link = None
        if libraries:
            cc_toolchain = find_cpp_toolchain(ctx)
            library_to_link = cc_common.create_library_to_link(
                actions = ctx.actions,
                feature_configuration = configure_features(ctx, cc_toolchain),
                cc_toolchain = cc_toolchain,
                static_library = libraries.get("static_library"),
                dynamic_library = libraries.get("shared_library"),
                interface_library = libraries.get("interface_library"),
                alwayslink = ctx.attr.alwayslink,
            )
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset([cc_common.create_linker_input(
                owner = ctx.label,
                libraries = depset([library_to_link] if library_to_link else []),
                user_link_flags = ctx.attr.linkopts,
            )]),
        )

    own_cc_info = CcInfo(compilation_context = compilation_context, linking_context = linking_context)
    cc_info = cc_common.merge_cc_infos(
        direct_cc_infos = [own_cc_info],
        cc_infos = [dep[CcInfo] for dep in ctx.attr.deps],
    )

    shared_libraries = depset(
        [libraries["shared_library"]] if "shared_library" in libraries else [],
        transitive = [wheel_shared_libraries(ctx.attr.deps)],
    )

    providers = [
        DefaultInfo(files = depset([site_packages] + libraries.values())),
        cc_info,
        PycrossWheelSharedLibraryInfo(shared_libraries = shared_libraries),
    ]

    if ctx.attr.make_variable:
        if len(includes) != 1:
            fail("make_variable requires exactly one entry in includes")

        # Double-escape $$ so the value survives ctx.expand_make_variables()
        # in cc_layer.bzl (which collapses $$ → $). After expansion the value
        # will contain $$EXT_BUILD_ROOT$$ for replace_placeholder().
        value = absolutize_path_in_str(
            ctx.workspace_name,
            "$$$$EXT_BUILD_ROOT$$$$/",
            includes[0],
        )
        providers.append(platform_common.TemplateVariableInfo({ctx.attr.make_variable: value}))

    return providers

pycross_wheel_cc_import = rule(
    implementation = _pycross_wheel_cc_import_impl,
    provides = [CcInfo, PycrossWheelSharedLibraryInfo],
    doc = """Exposes C/C++ headers and a prebuilt library from an installed wheel, like `cc_import`.

Use this when an sdist builds native code against a wheel it depends on, such
as torch, pyarrow, numpy or an `nvidia-*` wheel. Put the target in the build's
`native_deps`.

Paths are relative to the wheel's site-packages directory. The library is
copied out of the installed wheel so that it can be linked.

A shared library from this rule belongs to the other wheel, so wheel repair
doesn't bundle a copy of it. Repair finds it in this target's output directory
and excludes it by file name, even when the target is wrapped in a
`cc_library`. That works when the file name is the library's SONAME (or its
`@rpath` install name on macOS), which is the usual case for wheels. Versioned
files such as `libcudart.so.12` are fine: sdist builds can still link them with
`-lcudart`.

The built extension still has to find the library at runtime, for example
through an `$ORIGIN`-relative RPATH or because the other package loads it
first.

Use one target per library, as with `cc_import`, and connect them with
`deps`.
""",
    attrs = {
        "wheel_library": attr.label(
            doc = "A pycross_wheel_library target for the wheel that contains the headers and library.",
            mandatory = True,
            providers = [PycrossExtractedWheelInfo],
        ),
        "includes": attr.string_list(
            doc = "Include directories, relative to the wheel's site-packages (e.g. 'torch/include').",
        ),
        "shared_library": attr.string(
            doc = "A shared library (`.so` or `.dylib`) to link against, relative to site-packages " +
                  "(e.g. 'torch/lib/libtorch.so').",
        ),
        "static_library": attr.string(
            doc = "A static library (`.a`) to link against, relative to site-packages " +
                  "(e.g. 'numpy/_core/lib/libnpymath.a').",
        ),
        "interface_library": attr.string(
            doc = "An interface library for `shared_library` (e.g. a `.tbd` or `.lib` file), relative to site-packages.",
        ),
        "alwayslink": attr.bool(
            doc = "Link every object file in `static_library`, as in `cc_import`. This applies to " +
                  "Bazel `cc_*` link actions; sdist builds link what the build system asks for.",
        ),
        "linkopts": attr.string_list(
            doc = "Extra flags for Bazel `cc_*` targets that link against this library. sdist builds " +
                  "don't read them; use the build rule's `linkopts` instead.",
        ),
        "deps": attr.label_list(
            doc = "Other C/C++ targets this library depends on, such as other `pycross_wheel_cc_import` targets.",
            providers = [CcInfo],
            aspects = [collect_wheel_shared_libraries],
        ),
        "make_variable": attr.string(
            doc = "If set, export a TemplateVariableInfo with this name mapped to the absolutized include " +
                  "path, for use in build configuration such as Meson cross files. Requires exactly one " +
                  "entry in `includes`.",
        ),
        "_cc_toolchain": attr.label(default = "@bazel_tools//tools/cpp:current_cc_toolchain"),
        "_extract_wheel_lib": attr.label(
            default = Label("//pycross/private/tools:extract_wheel_lib"),
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = CC_TOOLCHAINS,
    fragments = CC_FRAGMENTS,
)

def pycross_wheel_headers(name, wheel_library, include_dir, make_variable = None, **kwargs):
    """Exposes C/C++ headers from an installed wheel as CcInfo.

    A shorthand for `pycross_wheel_cc_import` with a single include directory
    and no library.

    Args:
        name: The target name.
        wheel_library: A pycross_wheel_library target containing the headers.
        include_dir: Relative path within the wheel's site-packages to the include
            directory (e.g. 'numpy/_core/include').
        make_variable: If set, export a TemplateVariableInfo with this name mapped to
            the absolutized include path, for use in build configuration such as
            Meson cross files.
        **kwargs: Common attributes such as `visibility` and `tags`.
    """
    pycross_wheel_cc_import(
        name = name,
        wheel_library = wheel_library,
        includes = [include_dir],
        make_variable = make_variable,
        **kwargs
    )
