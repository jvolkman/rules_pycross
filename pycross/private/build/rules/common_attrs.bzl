"""Shared attribute dictionaries and utilities for pycross build rules."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(
    "//pycross/private:providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
    "PycrossWheelInfo",
)
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")

COMMON_BUILD_ATTRS = {
    "sdist": attr.label(mandatory = True, allow_single_file = True),
    "deps": attr.label_list(
        providers = [PyInfo],
        cfg = pycross_exec_platform_transition,
    ),
    "build_deps": attr.label_list(
        providers = [PyInfo],
        cfg = pycross_exec_platform_transition,
    ),
    "pre_build_patches": attr.label_list(
        doc = "Patch files to apply to the sdist source tree before building.",
        allow_files = [".patch", ".diff"],
    ),
    "_dummy_bin_file": attr.label(
        default = Label("//pycross/private:dummy_bin_file"),
        allow_single_file = True,
        cfg = pycross_exec_platform_transition,
    ),
}

CC_BUILD_ATTRS = {
    "native_deps": attr.label_list(providers = [CcInfo]),
    "copts": attr.string_list(),
    "linkopts": attr.string_list(),
    "config_settings": attr.string_list_dict(),
    "site_hooks": attr.string_list(),
    "pkg_config_files": attr.label_list(allow_files = True),
    "path_tools": attr.label_list(cfg = pycross_exec_platform_transition),
}

CC_TOOLCHAIN_ATTRS = {
    "_cc_toolchain": attr.label(default = "@bazel_tools//tools/cpp:current_cc_toolchain"),
    "_os_linux": attr.label(default = "@platforms//os:linux"),
    "_os_macos": attr.label(default = "@platforms//os:macos"),
    "_os_windows": attr.label(default = "@platforms//os:windows"),
    "_cpu_x86_64": attr.label(default = "@platforms//cpu:x86_64"),
    "_cpu_aarch64": attr.label(default = "@platforms//cpu:aarch64"),
    "_cpu_arm": attr.label(default = "@platforms//cpu:arm"),
    "_cpu_x86_32": attr.label(default = "@platforms//cpu:x86_32"),
}

CC_TOOLCHAINS = ["@bazel_tools//tools/cpp:toolchain_type"]
CC_FRAGMENTS = ["cpp"]

def group_tool_deps(tool_deps_list):
    """Groups tool_deps by PycrossPackageInfo.package_name.

    Args:
        tool_deps_list: list[Target], targets that may carry PycrossPackageInfo.

    Returns:
        dict[str, list[Target]]: targets keyed by normalized package name.
    """
    result = {}
    for dep in tool_deps_list:
        if PycrossPackageInfo in dep:
            name = dep[PycrossPackageInfo].package_name
            if name not in result:
                result[name] = []
            result[name].append(dep)
    return result

def get_wheel_file(target):
    """Extracts the .whl File from a target.

    Args:
        target: Target, a wheel target (with or without PycrossWheelInfo).

    Returns:
        File: the wheel file.
    """
    if PycrossWheelInfo in target:
        return target[PycrossWheelInfo].wheel_file
    files = target[DefaultInfo].files.to_list()
    for f in files:
        if f.path.endswith(".whl"):
            return f
    return files[0]

def get_unzipped_wheel(target):
    """Extracts the site_packages TreeArtifact from a target.

    Args:
        target: Target, must provide PycrossExtractedWheelInfo.

    Returns:
        File (TreeArtifact): the installed site-packages directory.
    """
    if PycrossExtractedWheelInfo in target:
        return target[PycrossExtractedWheelInfo].site_packages
    fail("Target {} does not provide a site_packages directory. Make sure it is wrapped in a pycross_wheel_library.".format(target.label))
