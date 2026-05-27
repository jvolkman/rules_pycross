"""Rule for compiling C++ toolchain & dependency info into a PycrossBuildMixinInfo."""

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
load("//pycross/private:providers.bzl", "PycrossBuildMixinInfo")

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

def _expand_locations_and_vars(attribute_name, ctx, val):
    rule_dir = ctx.bin_dir.path + "/" + ctx.label.workspace_root + "/" + ctx.label.package
    additional_substitutions = {
        "RULEDIR": rule_dir,
        "WORKSPACE": ctx.workspace_name,
    }
    val = val.replace("$(abspath ", "$$$$EXT_BUILD_ROOT$$$$/$(execpath ")
    val = ctx.expand_location(val, ctx.attr.deps)
    val = ctx.expand_make_variables(attribute_name, val, additional_substitutions)
    return val

def _get_target_os_and_cpu(cpp_toolchain):
    """Extracts and normalizes target OS and CPU from cpp_toolchain.cpu.

    Uses cpp_toolchain.cpu as the single source of truth for determinism.
    Fails explicitly if OS or CPU cannot be determined.
    """
    target_os = None
    target_cpu = None

    cpu = getattr(cpp_toolchain, "cpu", None)
    if cpu:
        cpu_lower = cpu.lower()
        if "darwin" in cpu_lower:
            target_os = "darwin"
        elif "linux" in cpu_lower or cpu_lower == "k8" or cpu_lower == "piii" or cpu_lower == "aarch64":
            target_os = "linux"
        elif "windows" in cpu_lower or "win" in cpu_lower:
            target_os = "windows"

        if "k8" in cpu_lower or "x86_64" in cpu_lower or "amd64" in cpu_lower:
            target_cpu = "x86_64"
        elif "aarch64" in cpu_lower or "arm64" in cpu_lower:
            target_cpu = "aarch64"
        elif "arm" in cpu_lower:
            target_cpu = "arm"
        elif "x86" in cpu_lower or "i386" in cpu_lower or "i686" in cpu_lower or cpu_lower == "piii":
            target_cpu = "x86"

    if not target_os:
        fail("Cannot determine target OS from cpp_toolchain.cpu='{}'. ".format(cpu) +
             "Ensure your C++ toolchain sets a recognized cpu value " +
             "(e.g., k8, darwin, darwin_arm64, aarch64).")
    if not target_cpu:
        fail("Cannot determine target CPU from cpp_toolchain.cpu='{}'. ".format(cpu) +
             "Ensure your C++ toolchain sets a recognized cpu value " +
             "(e.g., k8, darwin_arm64, aarch64).")

    return target_os, target_cpu

def _cc_mixin_impl(ctx):
    copts = [_expand_locations_and_vars("copts", ctx, copt) for copt in ctx.attr.copts]
    linkopts = [_expand_locations_and_vars("linkopts", ctx, linkopt) for linkopt in ctx.attr.linkopts]
    flags = get_flags_info(ctx, copts, linkopts)
    tools = get_tools_info(ctx)
    sysconfig_vars = _get_sysconfig_data(ctx.workspace_name, tools, flags)

    # Extract include dirs and libraries from CcInfo
    include_dirs = []
    static_libs = []
    shared_libs = []
    transitive_files = []

    cpp_toolchain = find_cpp_toolchain(ctx)
    target_os, target_cpu = _get_target_os_and_cpu(cpp_toolchain)
    if cpp_toolchain.all_files:
        transitive_files.append(cpp_toolchain.all_files)

    for dep in ctx.attr.deps:
        if CcInfo not in dep:
            continue
        ccinfo = dep[CcInfo]

        # Extract compilation context (headers & include paths)
        headers_and_includes = get_headers(ccinfo)
        transitive_files.append(ccinfo.compilation_context.headers)
        for inc in headers_and_includes.include_dirs:
            include_dirs.append(absolutize_path_in_str(ctx.workspace_name, "$$EXT_BUILD_ROOT$$/", inc))

        # Extract linking context (static & shared libs)
        libraries = get_libraries(ccinfo)
        transitive_files.append(depset(libraries))
        for lib in libraries:
            lib_path = absolutize_path_in_str(ctx.workspace_name, "$$EXT_BUILD_ROOT$$/", lib.path)
            if lib.path.endswith(".a"):
                static_libs.append(lib_path)
            elif lib.path.endswith(".so") or lib.path.endswith(".dylib"):
                shared_libs.append(lib_path)

    # Extract C++ static runtime libraries from the CC toolchain.
    # When the static_link_cpp_runtimes feature is enabled (Linux/Windows),
    # the toolchain provides the C++ runtime .a files (libc++, libc++abi,
    # libunwind). We extract them so Meson can link against them directly
    # by full path, replicating what Bazel does for cc_binary targets.
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

    # Combine everything into the unified config dictionary
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
    }

    config_json = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_json, json.encode(cc_config))

    return [
        PycrossBuildMixinInfo(
            config_json = config_json,
            files = depset([config_json], transitive = transitive_files),
        ),
    ]

pycross_cc_mixin = rule(
    implementation = _cc_mixin_impl,
    attrs = {
        "deps": attr.label_list(providers = [CcInfo]),
        "copts": attr.string_list(),
        "linkopts": attr.string_list(),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)
