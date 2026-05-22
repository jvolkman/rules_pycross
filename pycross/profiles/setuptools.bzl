"""Build profile for setuptools-based Python packages."""

load("//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library")

def setuptools_build(name, **kwargs):
    """Build profile for setuptools-based packages.

    Args:
        name: Name of the target.
        **kwargs: Additional arguments passed to pycross_wheel_build.
    """
    build_deps = kwargs.pop("build_deps", [])
    deps = kwargs.pop("deps", [])
    visibility = kwargs.pop("visibility", None)
    tags = list(kwargs.pop("tags", []))

    build_name = name + "_build"
    if "manual" not in tags:
        tags.append("manual")

    pycross_wheel_build(
        name = build_name,
        deps = build_deps,
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
