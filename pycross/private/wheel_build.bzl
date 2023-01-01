"""Implementation of the pycross_wheel_build rule."""

load(
    ":cc_toolchain_util.bzl",
    "absolutize_path_in_str",
    "get_env_vars",
    "get_flags_info",
    "get_headers",
    "get_libraries",
    "get_tools_info",
)
load(":providers.bzl", "PycrossTargetEnvironmentInfo", "PycrossWheelInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load("@rules_python//python:defs.bzl", "PyInfo")

PYTHON_TOOLCHAIN_TYPE = "@bazel_tools//tools/python:toolchain_type"
PYCROSS_TOOLCHAIN_TYPE = "@jvolkman_rules_pycross//pycross:toolchain_type"

def _absolute_tool_value(workspace_name, value):
    if value:
        tool_value_absolute = absolutize_path_in_str(workspace_name, "$$EXT_BUILD_ROOT$$/", value, True)

        # If the tool path contains whitespaces (e.g. C:\Program Files\...),
        # MSYS2 requires that the path is wrapped in double quotes
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

    # If libtool is used as AR, the output file has to be prefixed with
    # "-o".
    if ar == "libtool" or ar.endswith("/libtool"):
        ar_flags = ar_flags + ["-o"]

    vars = {
        "CC": cc,
        "CXX": cxx,
        "CFLAGS": _join_flags_list(workspace_name, flags.cc),
        "CCSHARED": "-fPIC" if flags.needs_pic_for_dynamic_libraries else "",
        "LDSHAREDFLAGS": _join_flags_list(workspace_name, flags.cxx_linker_shared),
        "AR": ar,
        "ARFLAGS": _join_flags_list(workspace_name, ar_flags),
        "CUSTOMIZED_OSX_COMPILER": "True",
        "GNULD": "yes" if "gcc" in cc else "no",  # is there a better way?
    }

    return vars

def _is_sibling_repository_layout_enabled(ctx):
    # It's possible to determine if --experimental_sibling_repository_layout is enabled by looking at
    # Label(@foo).workspace_root. If it's enabled, this value will start with `../`. By default it'll
    # start with `external/`.
    test = Label("@not_" + ctx.workspace_name)  # the not_ prefix means it can't be our local workspace.
    return test.workspace_root.startswith("..")

def _resolve_import_path_fn(ctx):
    # Call the inner function with simple values so the closure it returns doesn't hold onto a large
    # amount of state.
    return _resolve_import_path_fn_inner(
        ctx.workspace_name,
        ctx.bin_dir.path,
        _is_sibling_repository_layout_enabled(ctx),
    )

def _executable(target):
    exe = target[DefaultInfo].files_to_run.executable
    if not exe:
        fail("%s is not executable" % target.label)
    return exe.path

def _resolve_import_path_fn_inner(workspace_name, bin_dir, sibling_layout):
    # The PyInfo import names assume a runfiles-type structure. E.g.:
    #   mytool.runfiles/
    #     main_repo/
    #       my_package/
    #     external_repo_1/
    #       some_package/
    #     external_repo_2/
    #       ...
    #
    # An example PyInfo import name might be "external_repo_1/some_package", which maps nicely to the structure
    # above. However, our wheel builder isn't consuming these dependencies as runfiles, but as inputs. And so
    # for whatever reason the structure is different:
    #
    #   sandbox/main_repo/
    #     bazel-out/
    #       k8-fastbuild/
    #         bin/
    #           my_package/
    #           external/
    #             external_repo_1/
    #               some_package/
    #             external_repo_2/
    #               ...
    #
    # And to complicate the matter even further, the --experimental_sibling_repository_layout flag changes this
    # structure to be:
    #
    #   sandbox/main_repo/
    #     bazel-out/
    #       k8-fastbuild/
    #         bin/
    #           my_package/
    #       external_repo_1/
    #         k8-fastbuild/
    #           bin/
    #             some_package/
    #       external_repo_2/
    #         ...
    #

    # ctx.bin_dir returns something like bazel-out/k8-fastbuild/bin in legacy mode, or
    # bazel-out/my_external_repo/k8-fastbuild/bin in sibling layout when the target is within an external repo.
    # We really just want the first part and the last two parts. The repo name that's added with sibling mode isn't
    # useful for our case.
    bin_dir_parts = bin_dir.split("/")
    output_dir = bin_dir_parts[0]
    bin_dir = paths.join(*bin_dir_parts[-2:])

    def fn(import_name):
        # Split the import name into its repo and path.
        import_repo, import_path = import_name.split("/", 1)

        # Packages within the workspace are always the same regardless of sibling layout.
        if import_repo == workspace_name:
            return paths.join(output_dir, bin_dir, import_path)

        # Otherwise, if sibling layout is enabled...
        if sibling_layout:
            return paths.join(output_dir, import_repo, bin_dir, import_path)

        # And lastly, just use the traditional layout.
        return paths.join(output_dir, bin_dir, "external", import_repo, import_path)

    return fn

def _expand_locations_and_vars(attribute_name, ctx, val):
    rule_dir = paths.join(
        ctx.bin_dir.path,
        ctx.label.workspace_root,
        ctx.label.package,
    )

    additional_substitutions = {
        "RULEDIR": rule_dir,
        "BUILD_FILE_PATH": ctx.build_file_path,
        "VERSION_FILE": ctx.version_file.path,
        "INFO_FILE": ctx.info_file.path,
        "TARGET": "{}//{}:{}".format(
            "@" + ctx.label.workspace_name if ctx.label.workspace_name else "",
            ctx.label.package,
            ctx.label.name,
        ),
        "WORKSPACE": ctx.workspace_name,
    }

    # We import $(abspath :foo) by replacing it with $(execpath :foo) prefixed by 
    # $$EXT_BUILD_ROOT$$/, which is replaced in our build action. Note that "$$$$"
    # turns into "$$" after passing through ctx.expand_location.
    val = val.replace("$(abspath ", "$$$$EXT_BUILD_ROOT$$$$/$(execpath ")
    val = ctx.expand_location(val, ctx.attr.deps + ctx.attr.native_deps + ctx.attr.data)
    val = ctx.expand_make_variables(attribute_name, val, additional_substitutions)
    return val

def _handle_toolchains(ctx, args, tools):
    py_toolchain = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE].py3_runtime
    cpp_toolchain = find_cpp_toolchain(ctx)

    if cpp_toolchain.all_files:
        tools.append(cpp_toolchain.all_files)
    if py_toolchain.files:
        tools.append(py_toolchain.files)

    # If a pycross toolchain is configured, we use that to get the exec and target Python.
    if PYCROSS_TOOLCHAIN_TYPE in ctx.toolchains and ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE]:
        pycross_info = ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE].pycross_info
        args.add("--exec-python-executable", pycross_info.exec_python_executable)
        args.add("--target-python-executable", pycross_info.target_python_executable)
        if pycross_info.target_sys_path:
            args.add_all(pycross_info.target_sys_path, before_each="--target-sys-path")
        if pycross_info.exec_python_files:
            tools.append(pycross_info.exec_python_files)
        if pycross_info.target_python_files:
            tools.append(pycross_info.target_python_files)

    # Otherwise we use the configured Python toolchain.
    else:
        executable = py_toolchain.interpreter_path
        if not executable:
            executable = py_toolchain.interpreter.path
        args.add("--exec-python-executable", executable)
        args.add("--target-python-executable", executable)

def _handle_sdist(ctx, args, inputs):  # -> PycrossWheelInfo
    inputs.append(ctx.file.sdist)
    args.add("--sdist", ctx.file.sdist)

    sdist_name = ctx.file.sdist.basename
    if sdist_name.lower().endswith(".tar.gz"):
        wheel_name = sdist_name[:-7]
    else:
        wheel_name = sdist_name.rsplit(".", 1)[0]  # Also includes .zip

    out_wheel = ctx.actions.declare_file(paths.join(ctx.attr.name, wheel_name + ".whl"))
    out_wheel_name = ctx.actions.declare_file(paths.join(ctx.attr.name, wheel_name + ".whl.name"))

    args.add("--wheel-file", out_wheel)
    args.add("--wheel-name-file", out_wheel_name)

    return PycrossWheelInfo(
        wheel_file = out_wheel,
        name_file = out_wheel_name,
    )

def _handle_sysconfig_data(ctx, args, inputs):  # -> cc_vars
    cc_sysconfig_data = ctx.actions.declare_file(paths.join(ctx.attr.name, "cc_sysconfig.json"))
    cc_vars = get_env_vars(ctx)
    flags = get_flags_info(ctx)
    tools = get_tools_info(ctx)
    sysconfig_vars = _get_sysconfig_data(ctx.workspace_name, tools, flags)
    ctx.actions.write(cc_sysconfig_data, json.encode(sysconfig_vars))

    inputs.append(cc_sysconfig_data)
    args.add("--sysconfig-vars", cc_sysconfig_data)

    return cc_vars

def _handle_py_deps(ctx, args, tools):
    imports = depset(transitive = [d[PyInfo].imports for d in ctx.attr.deps])
    args.add_all(imports, before_each="--python-path", map_each=_resolve_import_path_fn(ctx), allow_closure=True)
    tools.extend([dep[PyInfo].transitive_sources for dep in ctx.attr.deps])

def _handle_native_deps(ctx, args, tools):
    for dep in ctx.attr.native_deps:
        if CcInfo not in dep:
            continue
        ccinfo = dep[CcInfo]

        headers_and_includes = get_headers(ccinfo)
        tools.append(ccinfo.compilation_context.headers)
        args.add_all(headers_and_includes.include_dirs, before_each="--native-include-path")
        args.add_all(headers_and_includes.headers, before_each="--native-header", expand_directories=False)

        libraries = get_libraries(ccinfo)
        tools.append(depset(libraries))
        args.add_all(libraries, before_each="--native-library")

def _handle_target_environment(ctx, args, inputs):
    if not ctx.attr.target_environment:
        return
    target_environment_file = ctx.attr.target_environment[PycrossTargetEnvironmentInfo].file
    args.add("--target-environment-file", target_environment_file)
    inputs.append(ctx.attr.target_environment[PycrossTargetEnvironmentInfo].file)

def _handle_build_env(ctx, args, inputs):
    if not ctx.attr.build_env:
        return
    build_env_data = ctx.actions.declare_file(paths.join(ctx.attr.name, "build_env.json"))
    args.add("--build-env", build_env_data)
    inputs.append(build_env_data)
    vals = {}
    for key, value in ctx.attr.build_env.items():
        vals[key] = _expand_locations_and_vars("build_env", ctx, value)
    ctx.actions.write(build_env_data, json.encode(vals))

def _handle_config_settings(ctx, args, inputs):
    if not ctx.attr.config_settings:
        return
    config_settings_data = ctx.actions.declare_file(paths.join(ctx.attr.name, "config_settings.json"))
    args.add("--config-settings", config_settings_data)
    inputs.append(config_settings_data)
    vals = {}
    for key, value in ctx.attr.config_settings.items():
        vals[key] = _expand_locations_and_vars("config_settings", ctx, value)
    ctx.actions.write(config_settings_data, json.encode(vals))

def _handle_tools_and_data(ctx, args, tools, input_manifests):
    tools.extend([data[DefaultInfo].files for data in ctx.attr.data])

    if ctx.attr.pre_build_hooks:
        args.add_all(ctx.attr.pre_build_hooks, before_each="--pre-build-hook", map_each=_executable)
        tool_inputs, tool_manifests = ctx.resolve_tools(tools=ctx.attr.pre_build_hooks)
        tools.extend([tool_inputs])
        input_manifests.extend(tool_manifests)

    if ctx.attr.post_build_hooks:
        args.add_all(ctx.attr.post_build_hooks, before_each="--post-build-hook", map_each=_executable)
        tool_inputs, tool_manifests = ctx.resolve_tools(tools=ctx.attr.post_build_hooks)
        tools.extend([tool_inputs])
        input_manifests.extend(tool_manifests)

    if ctx.attr.path_tools:
        for tool, name in ctx.attr.path_tools.items():
            args.add_all("--path-tool", [name, _executable(tool)])
        tool_inputs, tool_manifests = ctx.resolve_tools(tools=ctx.attr.path_tools.keys())
        tools.extend([tool_inputs])
        input_manifests.extend(tool_manifests)

def _pycross_wheel_build_impl(ctx):

    print("HAS TARGET", ctx.target_platform_has_constraint("@platforms//os:linux"))

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    inputs = []
    tools = []
    input_manifests = []

    pycross_wheel_info = _handle_sdist(ctx, args, inputs)
    cc_vars = _handle_sysconfig_data(ctx, args, inputs)
    _handle_toolchains(ctx, args, tools)
    _handle_py_deps(ctx, args, tools)
    _handle_native_deps(ctx, args, tools)
    _handle_target_environment(ctx, args, inputs)

    _handle_build_env(ctx, args, inputs)
    _handle_config_settings(ctx, args, inputs)

    _handle_tools_and_data(ctx, args, tools, input_manifests)

    env = dict(cc_vars)
    env.update(ctx.configuration.default_shell_env)

    ctx.actions.run(
        inputs = inputs,
        outputs = [pycross_wheel_info.wheel_file, pycross_wheel_info.name_file],
        tools = depset(transitive = tools),
        input_manifests = input_manifests,
        executable = ctx.executable._tool,
        use_default_shell_env = False,
        env = env,
        arguments = [args],
        mnemonic = "WheelBuild",
        progress_message = "Building %s" % ctx.file.sdist.basename,
    )

    return [
        pycross_wheel_info,
        DefaultInfo(
            files = depset(
                direct = [pycross_wheel_info.wheel_file],
            ),
        ),
    ]

def _pycross_toolchains():
    if hasattr(config_common, "toolchain_type"):
        # Optional toolchains are supported
        return [
            config_common.toolchain_type(PYTHON_TOOLCHAIN_TYPE, mandatory = True),
            config_common.toolchain_type(PYCROSS_TOOLCHAIN_TYPE, mandatory = False),
        ] + use_cpp_toolchain()
    else:
        return [PYTHON_TOOLCHAIN_TYPE] + use_cpp_toolchain()

pycross_wheel_build = rule(
    implementation = _pycross_wheel_build_impl,
    attrs = {
        "sdist": attr.label(
            doc = "The sdist file.",
            allow_single_file = [".tar.gz", ".zip"],
            mandatory = True,
        ),
        "deps": attr.label_list(
            doc = "A list of Python build dependencies for the wheel.",
            providers = [PyInfo],
        ),
        "native_deps": attr.label_list(
            doc = "A list of native build dependencies (CcInfo) for the wheel.",
            providers = [CcInfo],
        ),
        "data": attr.label_list(
            doc = "Additional data and dependencies used by the build.",
            providers = [DefaultInfo],
            allow_files = True,
        ),
        "target_environment": attr.label(
            doc = "The target environment to build for.",
            providers = [PycrossTargetEnvironmentInfo],
        ),
        "build_env": attr.string_dict(
            doc = (
                "Environment variables passed to the sdist build. " +
                "Values are subject to 'Make variable', location, and build_cwd_token expansion."
            )
        ),
        "config_settings": attr.string_dict(
            doc = (
                "PEP 517 config settings passed to the sdist build. " +
                "Values are subject to 'Make variable', location, and build_cwd_token expansion."
            ),
        ),
        "pre_build_hooks": attr.label_list(
            doc = (
                "A list of binaries that are executed prior to building the sdist."
            ),
            cfg = "exec",
        ),
        "post_build_hooks": attr.label_list(
            doc = (
                "A list of binaries that are executed after the wheel is built."
            ),
            cfg = "exec",
        ),
        "path_tools": attr.label_keyed_string_dict(
            doc = (
                "A mapping of binaries to names that are placed in PATH when building the sdist."
            ),
            cfg = "exec",
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_builder"),
            cfg = "exec",
            executable = True,
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    toolchains = _pycross_toolchains(),
    fragments = ["cpp"],
    host_fragments = ["cpp"],
)
