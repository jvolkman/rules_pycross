"""Implementation of the pycross_wheel_build rule."""

load(":cc_toolchain_util.bzl", "absolutize_path_in_str", "get_env_vars", "get_flags_info", "get_tools_info")
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

def _get_sysconfig_data(workspace_name, tools, flags):
    cc = _absolute_tool_value(workspace_name, tools.cc)
    cxx = _absolute_tool_value(workspace_name, tools.cxx)
    ar = _absolute_tool_value(workspace_name, tools.cxx_linker_static)
    vars = {
        "CC": cc,
        "CXX": cxx,
        "CFLAGS": " ".join(flags.cc),
        "CCSHARED": "-fPIC" if flags.needs_pic_for_dynamic_libraries else "",
        "LDSHAREDFLAGS": " ".join(flags.cxx_linker_shared),
        "AR": ar,
        "ARFLAGS": " ".join(flags.cxx_linker_static),
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

def _pycross_wheel_build_impl(ctx):
    cc_sysconfig_data = ctx.actions.declare_file(paths.join(ctx.attr.name, "cc_sysconfig.json"))

    sdist_name = ctx.file.sdist.basename
    if sdist_name.lower().endswith(".tar.gz"):
        wheel_name = sdist_name[:-7]
    else:
        wheel_name = sdist_name.rsplit(".", 1)[0]  # Also includes .zip

    out_wheel = ctx.actions.declare_file(paths.join(ctx.attr.name, wheel_name + ".whl"))
    out_name = ctx.actions.declare_file(paths.join(ctx.attr.name, wheel_name + ".whl.name"))

    cc_vars = get_env_vars(ctx)
    flags = get_flags_info(ctx)
    tools = get_tools_info(ctx)
    sysconfig_vars = _get_sysconfig_data(ctx.workspace_name, tools, flags)

    py_toolchain = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE].py3_runtime
    cpp_toolchain = find_cpp_toolchain(ctx)

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add("--sdist", ctx.file.sdist)
    args.add("--sysconfig-vars", cc_sysconfig_data)
    args.add("--wheel-file", out_wheel)
    args.add("--wheel-name-file", out_name)
    if ctx.attr.target_environment:
        target_environment_file = ctx.attr.target_environment[PycrossTargetEnvironmentInfo].file
        args.add("--target-environment-file", target_environment_file)

    toolchain_deps = []
    if cpp_toolchain.all_files:
        toolchain_deps.append(cpp_toolchain.all_files)
    if py_toolchain.files:
        toolchain_deps.append(py_toolchain.files)

    # If a pycross toolchain is configured, we use that to get the exec and target Python.
    if PYCROSS_TOOLCHAIN_TYPE in ctx.toolchains and ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE]:
        pycross_info = ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE].pycross_info
        args.add("--exec-python-executable", pycross_info.exec_python_executable)
        args.add("--target-python-executable", pycross_info.target_python_executable)
        if pycross_info.target_sys_path:
            args.add_all(pycross_info.target_sys_path, before_each="--target-sys-path")
        if pycross_info.exec_python_files:
            toolchain_deps.append(pycross_info.exec_python_files)
        if pycross_info.target_python_files:
            toolchain_deps.append(pycross_info.target_python_files)

    # Otherwise we use the configured Python toolchain.
    else:
        executable = py_toolchain.interpreter_path
        if not executable:
            executable = py_toolchain.interpreter.path
        args.add("--exec-python-executable", executable)
        args.add("--target-python-executable", executable)

    imports = depset(
        transitive = [d[PyInfo].imports for d in ctx.attr.deps],
    )

    args.add_all(imports, before_each="--path", map_each=_resolve_import_path_fn(ctx), allow_closure=True)

    ctx.actions.write(cc_sysconfig_data, json.encode(sysconfig_vars))

    deps = [
        ctx.file.sdist,
        cc_sysconfig_data,
    ]

    transitive_sources = [dep[PyInfo].transitive_sources for dep in ctx.attr.deps if PyInfo in dep]

    if ctx.attr.target_environment:
        deps.append(ctx.attr.target_environment[PycrossTargetEnvironmentInfo].file)

    env = dict(cc_vars)
    env.update(ctx.configuration.default_shell_env)

    ctx.actions.run(
        inputs = deps,
        outputs = [out_wheel, out_name],
        tools = depset(transitive = toolchain_deps + transitive_sources),
        executable = ctx.executable._tool,
        use_default_shell_env = False,
        env = env,
        arguments = [args],
        mnemonic = "WheelBuild",
        progress_message = "Building %s" % ctx.file.sdist.basename,
    )

    return [
        PycrossWheelInfo(
            wheel_file = out_wheel,
            name_file = out_name,
        ),
        DefaultInfo(
            files = depset(direct = [out_wheel]),
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
        "deps": attr.label_list(
            doc = "A list of build dependencies for the wheel.",
            providers = [DefaultInfo, PyInfo],
        ),
        "sdist": attr.label(
            doc = "The sdist file.",
            allow_single_file = [".tar.gz", ".zip"],
            mandatory = True,
        ),
        "target_environment": attr.label(
            doc = "The target environment to build for.",
            providers = [PycrossTargetEnvironmentInfo],
        ),
        "copts": attr.string_list(
            doc = "Additional C compiler options.",
        ),
        "linkopts": attr.string_list(
            doc = "Additional C linker options.",
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_builder"),
            cfg = "host",
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
