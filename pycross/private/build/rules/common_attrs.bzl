"""Shared attribute dictionaries and utilities for pycross build rules."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load(
    "//pycross/private:providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
    "PycrossPathToolInfo",
)
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")

def resolve_path_tools(ctx):
    """Resolve path_tools attr into a list of tool executable structs.

    Each entry in ``ctx.attr.path_tools`` is either:
    - A ``pycross_path_tool`` target (carries ``PycrossPathToolInfo``) — uses
      the custom name from the provider.
    - A plain executable target — uses the executable's basename.

    Args:
        ctx: Rule context with a ``path_tools`` label_list attr.

    Returns:
        list[struct]: Each struct has ``name``, ``file``, and ``files_to_run``.
    """
    result = []
    for target in ctx.attr.path_tools:
        if PycrossPathToolInfo in target:
            info = target[PycrossPathToolInfo]
            result.append(struct(
                name = info.name,
                file = info.executable,
                files_to_run = target[DefaultInfo].files_to_run,
            ))
        else:
            exe = target[DefaultInfo].files_to_run.executable
            if not exe:
                files = target[DefaultInfo].files.to_list()
                if files:
                    exe = files[0]
            if not exe:
                fail("Tool target must provide an executable: " + str(target.label))
            result.append(struct(
                name = exe.basename,
                file = exe,
                files_to_run = target[DefaultInfo].files_to_run,
            ))
    return result

COMMON_BUILD_ATTRS = {
    "sdist": attr.label(mandatory = True, allow_single_file = True),
    "source_dir": attr.string(
        doc = "Subdirectory within the sdist source tree to build.",
    ),
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
    "site_hooks": attr.string_list(
        doc = "Python code snippets to execute on interpreter startup during builds.",
    ),
    "whldir_name": attr.string(
        doc = "Name for the output .whldir TreeArtifact directory (e.g., 'numpy-1.24.0.whldir'). " +
              "If empty, defaults to '{name}.whldir'.",
    ),
    "build_env": attr.string_dict(
        doc = "Environment variables passed to the sdist build. " +
              "Values are subject to 'Make variable' and $(location) expansion.",
    ),
    "data": attr.label_list(
        doc = "Additional data and dependencies used by the build. " +
              "These files are made available in the sandbox and can be referenced " +
              "via $(location) in build_env and config_settings values.",
        allow_files = True,
    ),
    "pre_build_hooks": attr.label_list(
        doc = "Executables to run before building the wheel. " +
              "Each hook receives PYCROSS_CONFIG_SETTINGS_FILE and PYCROSS_ENV_VARS_FILE " +
              "environment variables pointing to JSON files it may read and modify.",
        cfg = pycross_exec_platform_transition,
    ),
    "post_build_hooks": attr.label_list(
        doc = "Executables to run after the wheel is built. " +
              "Each hook receives PYCROSS_WHEEL_FILE pointing to the built wheel.",
        cfg = pycross_exec_platform_transition,
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
    "pkg_config_files": attr.label_list(allow_files = True),
    "path_tools": attr.label_list(
        doc = "A list of binary targets placed on PATH during the build. " +
              "Targets can be raw executables or pycross_path_tool targets.",
        cfg = pycross_exec_platform_transition,
    ),
}

REPAIR_BUILD_ATTRS = {
    "target_environment": attr.label(
        doc = "The target environment mapping JSON (resolved dynamically via alias filegroup).",
        default = Label("@pycross_environments//:current"),
        allow_files = True,
    ),
    "_repair_tool": attr.label(
        default = Label("//pycross/private/build/tools:repair_wheel_hook"),
        executable = True,
        cfg = "exec",
    ),
}

TOOL_EXTRACT_ATTRS = {
    "_extract_console_script": attr.label(
        default = Label("//pycross/private/tools:extract_console_script"),
        executable = True,
        cfg = "exec",
    ),
    "_extract_wheel_bin": attr.label(
        default = Label("//pycross/private/tools:extract_wheel_bin"),
        executable = True,
        cfg = "exec",
    ),
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

def get_wheel(target):
    """Extracts the wheel output from a target.

    Args:
        target: Target, a wheel build target.

    Returns:
        File: the wheel file or TreeArtifact directory containing a .whl file.
    """
    files = target[DefaultInfo].files.to_list()
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
