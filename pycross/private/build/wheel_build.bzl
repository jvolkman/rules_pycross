"""Backward-compatible macro wrapping setuptools_build.

This provides the v1 pycross_wheel_build API as a thin wrapper around
the v2 setuptools_build rule. Users migrating from v1 can continue
using pycross_wheel_build with the same arguments.
"""

load("//pycross/private/build/rules:setuptools_build.bzl", "setuptools_build")

def pycross_wheel_build(
        name,
        sdist,
        deps = [],
        native_deps = [],
        data = [],
        copts = [],
        linkopts = [],
        config_settings = {},
        path_tools = [],
        target_environment = None,
        build_env = None,
        pre_build_hooks = None,
        post_build_hooks = None,
        whldir_name = None,
        **kwargs):
    """Builds a Python wheel from a source distribution.

    This is a backward-compatible wrapper around setuptools_build.
    It accepts the v1 pycross_wheel_build arguments and delegates
    to the v2 backend.

    Args:
        name: The target name.
        sdist: The sdist file label.
        deps: Python build dependencies.
        native_deps: Native dependencies (CcInfo).
        data: Additional data files. Note: in v2 these should be added
            via backend-specific override attrs instead.
        copts: Additional C compiler options.
        linkopts: Additional C linker options.
        config_settings: PEP 517 config settings.
        path_tools: Tools to place on PATH during build.
        target_environment: The target environment JSON label.
        build_env: Environment variables for the build. Note: in v2 use
            config_settings or site_hooks instead.
        pre_build_hooks: Pre-build hook executables. Note: in v2 use
            pre_build_patches or site_hooks instead.
        post_build_hooks: Post-build hook executables. Note: not directly
            supported in v2; use pycross_wheel_transform as a post step.
        whldir_name: Name for the output .whldir TreeArtifact.
        **kwargs: Additional arguments passed to setuptools_build.
    """

    if build_env:
        # buildifier: disable=print
        print("WARNING: pycross_wheel_build build_env is deprecated in v2. " +
              "Use config_settings or site_hooks instead.")

    if pre_build_hooks:
        # buildifier: disable=print
        print("WARNING: pycross_wheel_build pre_build_hooks is deprecated in v2. " +
              "Use pre_build_patches or site_hooks instead.")

    if post_build_hooks:
        # buildifier: disable=print
        print("WARNING: pycross_wheel_build post_build_hooks is deprecated in v2. " +
              "Use pycross_wheel_transform instead.")

    if data:
        # buildifier: disable=print
        print("WARNING: pycross_wheel_build data is deprecated in v2.")

    build_kwargs = dict(
        name = name,
        sdist = sdist,
        deps = deps,
        native_deps = native_deps,
        copts = copts,
        linkopts = linkopts,
        config_settings = config_settings,
        path_tools = path_tools,
    )

    if target_environment:
        build_kwargs["target_environment"] = target_environment

    if whldir_name:
        build_kwargs["whldir_name"] = whldir_name

    build_kwargs.update(kwargs)

    setuptools_build(**build_kwargs)
