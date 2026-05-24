"""Exposes numpy headers for C++ compilation."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _numpy_cc_library_impl(ctx):
    # Get the numpy pycross_wheel_library target
    numpy_dep = ctx.attr.numpy_wheel_dep
    files = numpy_dep[DefaultInfo].files.to_list()
    if not files:
        fail("numpy_wheel_dep has no files")

    # The output site-packages directory (TreeArtifact)
    numpy_dir = files[0]

    # Supporting both NumPy 1.x and 2.x include directory layouts
    include_dirs = [
        numpy_dir.path + "/site-packages/numpy/_core/include",
        numpy_dir.path + "/site-packages/numpy/core/include",
    ]

    compilation_context = cc_common.create_compilation_context(
        headers = depset([numpy_dir]),
        includes = depset(include_dirs),
    )

    return [
        CcInfo(
            compilation_context = compilation_context,
        ),
        DefaultInfo(
            files = depset([numpy_dir]),
        ),
    ]

numpy_cc_library = rule(
    implementation = _numpy_cc_library_impl,
    attrs = {
        "numpy_wheel_dep": attr.label(mandatory = True),
    },
)
