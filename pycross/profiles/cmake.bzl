"""Build profile for CMake-based Python packages (scikit-build-core).

This profile generates pycross_wheel_build + pycross_wheel_library targets
configured for packages that use scikit-build-core or other CMake-based
build backends.
"""

load("//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library")

def cmake_build(name, **kwargs):
    """Build profile for CMake-based packages.

    Args:
        name: Name of the target.
        **kwargs: Additional arguments passed to pycross_wheel_build.
    """
    build_deps = kwargs.pop("build_deps", [])
    deps = kwargs.pop("deps", [])
    path_tools = dict(kwargs.pop("path_tools", {}))
    visibility = kwargs.pop("visibility", None)
    tags = list(kwargs.pop("tags", []))

    build_name = name + "_build"
    if "manual" not in tags:
        tags.append("manual")

    pycross_wheel_build(
        name = build_name,
        deps = build_deps,
        path_tools = path_tools,
        visibility = ["//visibility:private"],
        tags = tags,
        **kwargs
    )

    pycross_wheel_library(
        name = name,
        wheel = ":" + build_name,
        deps = deps,
        visibility = visibility,
    )
