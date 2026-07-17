"""Exposes numpy headers for C/C++ compilation."""

load("@rules_pycross//pycross:defs.bzl", "pycross_wheel_headers")

def numpy_cc_library(name, numpy_wheel_dep, **kwargs):
    """Convenience macro for numpy headers."""
    pycross_wheel_headers(
        name = name,
        wheel_library = numpy_wheel_dep,
        include_dir = "numpy/_core/include",
        make_variable = "NUMPY_INCLUDE_DIR",
        **kwargs
    )
