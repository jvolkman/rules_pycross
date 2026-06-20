"""Backward-compatible macro wrapping setuptools_build.

This provides the v1 pycross_wheel_build API as a thin wrapper around
the v2 setuptools_build rule. Users migrating from v1 can continue
using pycross_wheel_build with the same arguments.
"""

load("//pycross/private/build/rules:path_tool.bzl", "pycross_path_tool")
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
        path_tools = {},
        target_environment = None,
        build_env = {},
        pre_build_hooks = [],
        post_build_hooks = [],
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
        data: Additional data and dependencies used by the build.
        copts: Additional C compiler options.
        linkopts: Additional C linker options.
        config_settings: PEP 517 config settings.
        path_tools: A mapping of binary targets to names placed on PATH
            during the build. Use {"//tools:cmake3": "cmake"} to rename,
            or {"//tools:cmake": ""} to use the executable's basename.
            Can also be passed as a list of targets directly.
        target_environment: The target environment JSON label.
        build_env: Environment variables passed to the sdist build.
            Values are subject to $(location) expansion.
        pre_build_hooks: Executables to run before building the wheel.
        post_build_hooks: Executables to run after the wheel is built.
        whldir_name: Name for the output .whldir TreeArtifact.
        **kwargs: Additional arguments passed to setuptools_build.
    """

    rule_path_tools = []
    if type(path_tools) == "dict":
        for tool, tool_name in path_tools.items():
            if tool_name:
                # Generate a helper target for renaming
                sanitized_tool = (
                    tool
                        .replace(":", "_")
                        .replace("/", "_")
                        .replace("@", "_")
                        .replace(".", "_")
                        .replace("-", "_")
                )
                helper_name = "{}_path_tool_{}".format(name, sanitized_tool)
                pycross_path_tool(
                    name = helper_name,
                    tool = tool,
                    executable_name = tool_name,
                )
                rule_path_tools.append(":" + helper_name)
            else:
                rule_path_tools.append(tool)
    elif type(path_tools) == "list":
        rule_path_tools = path_tools
    else:
        fail("path_tools must be a dict or a list, got: " + type(path_tools))

    build_kwargs = dict(
        name = name,
        sdist = sdist,
        deps = deps,
        native_deps = native_deps,
        data = data,
        copts = copts,
        linkopts = linkopts,
        config_settings = config_settings,
        path_tools = rule_path_tools,
        build_env = build_env,
        pre_build_hooks = pre_build_hooks,
        post_build_hooks = post_build_hooks,
    )

    if target_environment:
        build_kwargs["target_environment"] = target_environment

    if whldir_name:
        build_kwargs["whldir_name"] = whldir_name

    build_kwargs.update(kwargs)

    setuptools_build(**build_kwargs)
