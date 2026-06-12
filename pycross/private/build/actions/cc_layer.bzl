"""Action logic for CC environment extraction."""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(
    "//pycross/private:cc_toolchain_util.bzl",
    "CC_DISABLED_FEATURES",
    "absolutize_path_in_str",
    "get_flags_info",
    "get_headers",
    "get_libraries",
    "get_tools_info",
)

def _absolute_tool_value(workspace_name, value):
    if value:
        tool_value_absolute = absolutize_path_in_str(workspace_name, "$$EXT_BUILD_ROOT$$/", value, True)
        if " " in tool_value_absolute:
            tool_value_absolute = "\\\"" + tool_value_absolute + "\\\""
        return tool_value_absolute
    return value

def _join_flags_list(workspace_name, flags):
    return " ".join([absolutize_path_in_str(workspace_name, "$$EXT_BUILD_ROOT$$/", flag) for flag in flags])

def _get_sysconfig_data(workspace_name, tools, flags):
    cc = _absolute_tool_value(workspace_name, tools.cc)
    cxx = _absolute_tool_value(workspace_name, tools.cxx)
    ar = _absolute_tool_value(workspace_name, tools.cxx_linker_static)
    ar_flags = flags.cxx_linker_static

    if ar == "libtool" or ar.endswith("/libtool"):
        ar_flags = ar_flags + ["-o"]

    vars = {
        "CC": cc,
        "CXX": cxx,
        "CFLAGS": _join_flags_list(workspace_name, flags.cc),
        "CXXFLAGS": _join_flags_list(workspace_name, flags.cxx),
        "CCSHARED": "-fPIC" if flags.needs_pic_for_dynamic_libraries else "",
        "LDFLAGS": _join_flags_list(workspace_name, flags.cxx_linker_executable),
        "LDSHAREDFLAGS": _join_flags_list(workspace_name, flags.cxx_linker_shared),
        "AR": ar,
        "ARFLAGS": _join_flags_list(workspace_name, ar_flags),
    }
    return vars

def _expand_locations_and_vars(attribute_name, ctx, val, deps):
    rule_dir = ctx.bin_dir.path + "/" + ctx.label.workspace_root + "/" + ctx.label.package
    additional_substitutions = {
        "RULEDIR": rule_dir,
        "WORKSPACE": ctx.workspace_name,
    }
    val = val.replace("$(abspath ", "$$$$EXT_BUILD_ROOT$$$$/$(execpath ")
    val = ctx.expand_location(val, deps)
    val = ctx.expand_make_variables(attribute_name, val, additional_substitutions)
    return val

def _get_target_os_and_cpu(ctx):
    target_os = None
    target_cpu = None

    if ctx.target_platform_has_constraint(ctx.attr._os_linux[platform_common.ConstraintValueInfo]):
        target_os = "linux"
    elif ctx.target_platform_has_constraint(ctx.attr._os_macos[platform_common.ConstraintValueInfo]):
        target_os = "darwin"
    elif ctx.target_platform_has_constraint(ctx.attr._os_windows[platform_common.ConstraintValueInfo]):
        target_os = "windows"

    if ctx.target_platform_has_constraint(ctx.attr._cpu_x86_64[platform_common.ConstraintValueInfo]):
        target_cpu = "x86_64"
    elif ctx.target_platform_has_constraint(ctx.attr._cpu_aarch64[platform_common.ConstraintValueInfo]):
        target_cpu = "aarch64"
    elif ctx.target_platform_has_constraint(ctx.attr._cpu_arm[platform_common.ConstraintValueInfo]):
        target_cpu = "arm"
    elif ctx.target_platform_has_constraint(ctx.attr._cpu_x86_32[platform_common.ConstraintValueInfo]):
        target_cpu = "x86"

    if not target_os:
        fail("Cannot determine target OS. Ensure your target platform has a recognized @platforms//os constraint (linux, macos, windows).")
    if not target_cpu:
        fail("Cannot determine target CPU. Ensure your target platform has a recognized @platforms//cpu constraint (x86_64, aarch64, arm, x86_32).")

    return target_os, target_cpu

def _is_shared_library(path):
    filename = path.split("/")[-1]
    if filename.endswith(".dylib"):
        return True
    if filename.endswith(".so"):
        return True
    if ".so." in filename:
        return True
    return False

def extract_cc_layer(ctx, native_deps, copts, linkopts, meson_properties = {}):
    """Extracts CC toolchain info, headers, and libraries from native deps.

    Requires the calling rule to declare:
        - fragments = ["cpp"]
        - toolchains = ["@bazel_tools//tools/cpp:toolchain_type"]
        - _cc_toolchain attr
        - _os_* and _cpu_* constraint attrs

    Args:
        ctx: The rule context.
        native_deps: list[Target], targets providing CcInfo.
        copts: list[str], extra compiler flags.
        linkopts: list[str], extra linker flags.
        meson_properties: dict, meson cross-file properties.

    Returns:
        struct(
            config_json = File,      # the serialized CC config
            transitive_files = depset, # all files needed at build time
            make_vars = dict,        # template variables from deps
        )
    """
    copts = [_expand_locations_and_vars("copts", ctx, copt, native_deps) for copt in copts]
    linkopts = [_expand_locations_and_vars("linkopts", ctx, linkopt, native_deps) for linkopt in linkopts]
    flags = get_flags_info(ctx, copts, linkopts)
    tools = get_tools_info(ctx)
    sysconfig_vars = _get_sysconfig_data(ctx.workspace_name, tools, flags)

    include_dirs = []
    static_libs = []
    shared_libs = []
    transitive_files = []

    cpp_toolchain = find_cpp_toolchain(ctx)
    target_os, target_cpu = _get_target_os_and_cpu(ctx)
    if cpp_toolchain.all_files:
        transitive_files.append(cpp_toolchain.all_files)

    for dep in native_deps:
        if CcInfo not in dep:
            continue
        ccinfo = dep[CcInfo]

        headers_and_includes = get_headers(ccinfo)
        transitive_files.append(ccinfo.compilation_context.headers)
        for inc in headers_and_includes.include_dirs:
            include_dirs.append(absolutize_path_in_str(ctx.workspace_name, "$$EXT_BUILD_ROOT$$/", inc))

        libraries = get_libraries(ccinfo)
        transitive_files.append(depset(libraries))
        for lib in libraries:
            lib_path = absolutize_path_in_str(ctx.workspace_name, "$$EXT_BUILD_ROOT$$/", lib.path)
            if lib.path.endswith(".a"):
                static_libs.append(lib_path)
            elif _is_shared_library(lib.path):
                shared_libs.append(lib_path)

    make_vars = {}
    for dep in native_deps:
        if platform_common.TemplateVariableInfo in dep:
            make_vars.update(dep[platform_common.TemplateVariableInfo].variables)

    expanded_meson_properties = {}
    for key, value in meson_properties.items():
        expanded_meson_properties[key] = ctx.expand_make_variables("meson_properties", value, make_vars)

    runtime_libs = []
    disabled_features = ctx.disabled_features + CC_DISABLED_FEATURES
    if not ctx.coverage_instrumented():
        disabled_features.append("coverage")
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cpp_toolchain,
        requested_features = ctx.features,
        unsupported_features = disabled_features,
    )
    runtime_depset = cpp_toolchain.static_runtime_lib(
        feature_configuration = feature_configuration,
    )
    if runtime_depset:
        for f in runtime_depset.to_list():
            runtime_libs.append(
                absolutize_path_in_str(ctx.workspace_name, "$$EXT_BUILD_ROOT$$/", f.path),
            )
        transitive_files.append(runtime_depset)

    cc_config = {
        "CC": sysconfig_vars["CC"],
        "CXX": sysconfig_vars["CXX"],
        "CFLAGS": sysconfig_vars["CFLAGS"],
        "CXXFLAGS": sysconfig_vars["CXXFLAGS"],
        "CCSHARED": sysconfig_vars["CCSHARED"],
        "LDFLAGS": sysconfig_vars["LDFLAGS"],
        "LDSHAREDFLAGS": sysconfig_vars["LDSHAREDFLAGS"],
        "AR": sysconfig_vars["AR"],
        "ARFLAGS": sysconfig_vars["ARFLAGS"],
        "include_dirs": include_dirs,
        "static_libs": static_libs,
        "shared_libs": shared_libs,
        "runtime_libs": runtime_libs,
        "target_os": target_os,
        "target_cpu": target_cpu,
        "meson_properties": expanded_meson_properties,
    }

    config_json = ctx.actions.declare_file(ctx.label.name + "_cc_config.json")
    ctx.actions.write(config_json, json.encode(cc_config))

    return struct(
        config_json = config_json,
        transitive_files = depset(transitive = transitive_files),
        make_vars = make_vars,
    )
