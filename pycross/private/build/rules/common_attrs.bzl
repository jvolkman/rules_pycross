"""Shared attribute dictionaries and utilities for pycross build rules."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("//pycross/private:deferred_failure.bzl", "register_failure_action")
load(
    "//pycross/private:providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
    "PycrossPathToolInfo",
)
load("//pycross/private/build:resource_sets.bzl", "RESOURCE_SET_ATTRS", "get_resource_set")
load("//pycross/private/build:transitions.bzl", "pycross_exec_platform_transition")
load("//pycross/private/build:wheel_shared_libraries.bzl", "collect_wheel_shared_libraries")
load("//pycross/private/build/actions:pep517_action.bzl", "register_pep517_action")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")

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
                files_to_run = getattr(info, "files_to_run", None) or target[DefaultInfo].files_to_run,
            ))
            continue

        exe = target[DefaultInfo].files_to_run.executable
        if not exe:
            files = target[DefaultInfo].files.to_list()
            exe = files[0] if files else None
        if not exe:
            fail("Tool target must provide an executable: " + str(target.label))
        result.append(struct(
            name = exe.basename,
            file = exe,
            files_to_run = target[DefaultInfo].files_to_run,
        ))
    return result

COMMON_BUILD_ATTRS = {
    "sdist": attr.label(
        mandatory = True,
        allow_single_file = True,
        doc = "The sdist archive to build.",
    ),
    "source_dir": attr.string(
        doc = "Subdirectory within the sdist source tree to build.",
    ),
    "deps": attr.label_list(
        doc = "Runtime dependencies of the package, available on the build's Python path.",
        providers = [PyInfo],
        cfg = pycross_exec_platform_transition,
    ),
    "build_deps": attr.label_list(
        doc = "Build-time Python packages (e.g. `build-system.requires`), available on the build's Python path.",
        providers = [PyInfo],
        cfg = pycross_exec_platform_transition,
    ),
    "build_requires": attr.string_list(
        doc = "PEP 508 requirement strings from `pyproject.toml`'s `build-system.requires`, " +
              "used to warn when a resolved build dependency version does not satisfy its version specifier.",
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
              "Values are subject to $(location) expansion.",
    ),
    "config_settings": attr.string_list_dict(
        doc = "PEP 517 `config_settings` passed to the build backend. " +
              "Values are subject to $(location) expansion.",
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
              "environment variables pointing to JSON files it may read and modify " +
              "(set an env key to null in PYCROSS_ENV_VARS_FILE to unset it).",
        cfg = pycross_exec_platform_transition,
    ),
    "post_build_hooks": attr.label_list(
        doc = "Executables to run after the wheel is built. " +
              "Each hook receives PYCROSS_WHEEL_FILE pointing to the built wheel.",
        cfg = pycross_exec_platform_transition,
    ),
} | RESOURCE_SET_ATTRS

CC_BUILD_ATTRS = {
    "native_deps": attr.label_list(
        doc = "C/C++ libraries whose headers and libraries are made available to the build.",
        providers = [CcInfo],
        aspects = [collect_wheel_shared_libraries],
    ),
    "copts": attr.string_list(
        doc = "Extra C/C++ compiler flags, appended after the toolchain flags.",
    ),
    "linkopts": attr.string_list(
        doc = "Extra linker flags, appended after the toolchain flags.",
    ),
    "pkg_config_files": attr.label_list(
        doc = "pkg-config `.pc` files made available to the build (e.g. from `pycross_cc_pkg_config`).",
        allow_files = True,
    ),
    "path_tools": attr.label_list(
        doc = "A list of binary targets placed on PATH during the build. " +
              "Targets can be raw executables or pycross_path_tool targets.",
        cfg = pycross_exec_platform_transition,
    ),
}

REPAIR_BUILD_ATTRS = {
    "repair_exclude_globs": attr.string_list(
        doc = "Shared library globs to exclude from wheel repair; assumed provided at runtime.",
    ),
    "target_environment": attr.label(
        doc = "The target environment mapping JSON (resolved dynamically via alias filegroup).",
        default = Label("@rules_pycross//pycross/private:default_target_platform"),
        allow_files = True,
    ),
    "_repair_tool": attr.label(
        default = Label("//pycross/private/build/tools:repair_wheel_hook"),
        executable = True,
        cfg = "exec",
    ),
}

TOOL_EXTRACT_ATTRS = {
    "_extract_wheel_bin": attr.label(
        default = Label("//pycross/private/tools:wheel_file_op"),
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

COMMON_TOOLCHAINS = [
    Label("@rules_python//python:toolchain_type"),
    config_common.toolchain_type(Label("//pycross:toolchain_type"), mandatory = False),
]
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
        if PycrossPackageInfo not in dep:
            continue
        result.setdefault(dep[PycrossPackageInfo].package_name, []).append(dep)
    return result

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

def defer_build_error(ctx, errors):
    """Reports sdist build configuration errors at execution time.

    Build rules call this instead of `fail()` when they detect, during analysis,
    that a build cannot succeed (e.g. missing build-system packages or tools).
    Returning providers backed by a failing action, rather than failing
    analysis, keeps analysis-only consumers (aspects, `cquery`) working for
    packages that are never actually built, while any real build of the package
    still fails with the same message. This mirrors Bazel's validation-action
    pattern.

    Args:
        ctx: The build rule context (must include `COMMON_BUILD_ATTRS`).
        errors: list[str], the error messages. Must be non-empty.

    Returns:
        list of providers for the build rule to return.
    """
    whldir_name = ctx.attr.whldir_name or (ctx.attr.name + ".whldir")
    out = ctx.actions.declare_directory(whldir_name)
    register_failure_action(
        ctx,
        outputs = [out],
        message = "Cannot build {} from source:\n{}".format(
            ctx.file.sdist.basename,
            "\n".join(errors),
        ),
        mnemonic = "PycrossSdistBuildConfigError",
        progress_message = "Rejecting sdist build %{label}",
    )
    return [
        DefaultInfo(files = depset([out])),
        OutputGroupInfo(raw_wheel = depset([out])),
    ]

def run_wheel_build(
        ctx,
        builder,
        additional_build_deps = [],
        layers = [],
        tool_executables = [],
        extra_files = {},
        extra_inputs = [],
        env = {},
        parallelism_env_vars = (),
        native_deps = None,
        repair_deps = []):
    """Runs the standard PEP 517 build and wheel repair tail for a backend rule.

    Computes the action resource set, populates `MAKEFLAGS` and any backend-specific
    `parallelism_env_vars` when parallelism is configured, registers the PEP 517 build
    and wheel repair actions, and returns `[DefaultInfo, OutputGroupInfo(raw_wheel=...)]`.

    Args:
        ctx: The rule context (must declare `COMMON_BUILD_ATTRS` and `REPAIR_BUILD_ATTRS`).
        builder: Target, the PEP 517 builder executable.
        additional_build_deps: list[Target], extra build-time Python deps merged with `ctx.attr.build_deps`.
        layers: list[struct], layer configs (e.g. from `extract_cc_layer()`).
        tool_executables: list[struct(name, file)], executables to place on PATH.
        extra_files: dict[str, File], files to inject into the sdist directory before building.
        extra_inputs: list[File], extra inputs to the build action.
        env: dict[str, str], extra programmatic environment variables for the build action.
        parallelism_env_vars: sequence[str], additional env var names (besides `MAKEFLAGS`)
            to populate with `str(resources.parallelism)` when parallelism > 0.
        native_deps: optional list[Target], CcInfo deps for repair; defaults to `ctx.attr.native_deps` if present.
        repair_deps: list[Target], optional PyInfo targets (e.g. `repairwheel` override) for repair.

    Returns:
        list of providers: `[DefaultInfo, OutputGroupInfo(raw_wheel = ...)]`.
    """
    resources = get_resource_set(ctx.attr)
    build_env = dict(env)
    if resources.parallelism > 0:
        jobs = str(resources.parallelism)
        build_env.setdefault("MAKEFLAGS", "-j{}".format(jobs))
        for var_name in parallelism_env_vars:
            build_env.setdefault(var_name, jobs)

    build_result = register_pep517_action(
        ctx,
        builder = builder,
        additional_build_deps = additional_build_deps,
        layers = layers,
        tool_executables = tool_executables,
        extra_files = extra_files,
        extra_inputs = extra_inputs,
        env = build_env,
        resource_set = resources.resource_set,
    )

    effective_native_deps = native_deps if native_deps != None else getattr(ctx.attr, "native_deps", [])
    target_environment = ctx.files.target_environment[0] if ctx.files.target_environment else None
    repair_result = register_repair_action(
        ctx,
        input_wheel_dir = build_result.wheel_dir,
        native_deps = effective_native_deps,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
        repair_exclude_globs = ctx.attr.repair_exclude_globs,
        repair_deps = repair_deps,
    )

    return [
        DefaultInfo(files = depset([repair_result.wheel_dir])),
        OutputGroupInfo(
            raw_wheel = depset([build_result.wheel_dir]),
        ),
    ]
