"""Macro for building wheels from sdists with native dependency support."""

load(":cc_mixin.bzl", "pycross_cc_mixin")
load(":pep517_build.bzl", "pycross_pep517_build")
load(":repaired_wheel.bzl", "pycross_repaired_wheel")

def pycross_wheel_build(name, native_deps = [], copts = [], linkopts = [], repair_wheel = True, **kwargs):
    """Builds a Python wheel from a source distribution.

    This macro wraps pycross_pep517_build with automatic CC toolchain
    setup and wheel repair. When native_deps are present, the built
    wheel is automatically repaired to bundle shared libraries.

    Args:
        name: The target name.
        native_deps: List of native dependencies (CcInfo).
        copts: Additional C compiler options.
        linkopts: Additional C linker options.
        repair_wheel: If True (default), pass the built wheel through repairwheel to bundle native deps and apply manylinux tags.
        **kwargs: Additional arguments to pass to pycross_pep517_build.
    """
    all_mixins = list(kwargs.pop("mixins", []))

    cc_env_name = name + "_cc_env"
    pycross_cc_mixin(
        name = cc_env_name,
        deps = native_deps,
        copts = copts,
        linkopts = linkopts,
        visibility = ["//visibility:private"],
    )
    all_mixins.append(":" + cc_env_name)

    if repair_wheel:
        build_name = name + "_raw"
    else:
        build_name = name

    pycross_pep517_build(
        name = build_name,
        mixins = all_mixins,
        builder = "@rules_pycross//pycross/private/build/tools:setuptools_builder",
        **kwargs
    )

    if repair_wheel:
        pycross_repaired_wheel(
            name = name,
            wheel = ":" + build_name,
            native_deps = native_deps,
        )
