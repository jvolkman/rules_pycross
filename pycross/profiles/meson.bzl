"""Build profile for Meson-based Python packages.

This profile generates pycross_wheel_build + pycross_wheel_library targets
configured for packages that use meson-python (mesonpy) as their build backend.
"""

load(
    "//pycross:defs.bzl",
    "pycross_cc_mixin",
    "pycross_pep517_build",
    "pycross_repaired_wheel",
    "pycross_wheel_library",
)

def meson_build(
        name,
        sdist,
        native_deps = [],
        copts = [],
        linkopts = [],
        build_deps = [],
        deps = [],
        path_tools = [],
        config_settings = {},
        pkg_config_files = [],
        sdist_python_paths = [],
        visibility = None,
        tags = []):
    """Build profile for Meson-based Python packages.

    This profile generates a 3-stage compilation/link/repair pipeline
    and registers the final wheel as a library.

    Args:
      name: Name of the final library target.
      sdist: The sdist label to build.
      native_deps: CC dependencies to link against.
      copts: Extra C++ compiler options.
      linkopts: Extra linker options.
      build_deps: Build dependencies required for PEP 517 package.
      deps: Additional Python runtime dependencies.
      path_tools: Executable tools to put on PATH during build.
      config_settings: Meson setup configuration arguments.
      pkg_config_files: Pkg-config files to copy to package directory.
      sdist_python_paths: Sdist-relative paths to add to PYTHONPATH during the build.
      visibility: Target visibility.
      tags: Target tags.
    """
    mixins = []
    cc_mixin_name = name + "_cc_mixin"
    raw_build_name = name + "_raw"

    # Stage 1: Extract CC toolchains and static libs into a Mixin
    if native_deps or copts or linkopts:
        pycross_cc_mixin(
            name = cc_mixin_name,
            deps = native_deps,
            copts = copts,
            linkopts = linkopts,
            visibility = ["//visibility:private"],
        )
        mixins.append(":" + cc_mixin_name)

    # Stage 2: Build raw wheel via PEP 517
    pycross_pep517_build(
        name = raw_build_name,
        sdist = sdist,
        builder = "@rules_pycross//pycross/private/build/tools:meson_builder",
        mixins = mixins,
        deps = build_deps,
        config_settings = config_settings,
        pkg_config_files = pkg_config_files,
        sdist_python_paths = sdist_python_paths,
        path_tools = path_tools,
        visibility = ["//visibility:private"],
        tags = tags,
    )

    # Stage 3: Repair wheel (bundle native shared libraries)
    repaired_wheel_name = name + "_repaired"
    pycross_repaired_wheel(
        name = repaired_wheel_name,
        wheel = ":" + raw_build_name,
        native_deps = native_deps,
        visibility = ["//visibility:private"],
    )

    # Stage 4: Expose final wheel library
    pycross_wheel_library(
        name = name,
        wheel = ":" + repaired_wheel_name,
        deps = deps,
        visibility = visibility,
    )
