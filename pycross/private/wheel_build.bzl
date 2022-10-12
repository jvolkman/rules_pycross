"""Implementation of the pycross_wheel_build rule."""

load(":cc_toolchain_util.bzl", "absolutize_path_in_str", "get_env_vars", "get_flags_info", "get_tools_info")
load(":providers.bzl", "PycrossTargetEnvironmentInfo", "PycrossWheelInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load("@rules_python//python:defs.bzl", "PyInfo")

PYTHON_TOOLCHAIN_TYPE = "@bazel_tools//tools/python:toolchain_type"

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

    # Currently we just use the configured Python toolchain's interpreter. But Down the road
    # we may want our own toolchain type to give more control over the interpreter used for
    # building packages.
    executable = py_toolchain.interpreter_path
    if not executable:
        executable = py_toolchain.interpreter.path

    args = [
        "--sdist",
        ctx.file.sdist.path,
        "--sysconfig-vars",
        cc_sysconfig_data.path,
        "--wheel-file",
        out_wheel.path,
        "--wheel-name-file",
        out_name.path,
        "--exec-python-executable",
        executable,
    ]

    if ctx.attr.target_environment:
        args.extend([
            "--target-environment-file",
            ctx.attr.target_environment[PycrossTargetEnvironmentInfo].file.path,
        ])

    imports = depset(
        transitive = [d[PyInfo].imports for d in ctx.attr.deps],
    )

    for import_name in imports.to_list():
        # The PyInfo import names assume a runfiles-type structure. E.g.:
        #   mytool.runfiles/
        #     main_repo/
        #       my_package/
        #     external_repo_1/
        #       some_package/
        #     external_repo_2/
        #       ...
        #
        # So the import name starts with the workspace name, and the rest of the import is the path within
        # that workspace. Our wheel builder isn't consuming these dependencies from runfiles though; they're
        # inputs, and so for whatever reason the structure is different:
        #
        #   sandbox/main_repo/
        #     bazel-out/
        #       k8-fastbuild/
        #         bin/
        #           my_package/
        #     external/
        #       external_repo_1/
        #         some_package/
        #       external_repo_2/
        #         ...
        #
        # So this logic translates the import paths into the proper structure: imports from the main repo
        # are found under `ctx.bin_dir.path`, and external import are found under `external/`.
        import_name_parts = import_name.split("/", 1)
        if import_name_parts[0] == ctx.workspace_name:
            # Local package; will be in ctx.bin_dir
            args.extend([
                "--path",
                paths.join(ctx.bin_dir.path, import_name_parts[1]),
            ])
        else:
            # External package; will be in "external".
            args.extend([
                "--path",
                paths.join("external", import_name),
            ])

    ctx.actions.write(cc_sysconfig_data, json.encode(sysconfig_vars))

    deps = [
        ctx.file.sdist,
        cc_sysconfig_data,
    ] + ctx.files.deps

    transitive_sources = [dep[PyInfo].transitive_sources for dep in ctx.attr.deps if PyInfo in dep]

    if ctx.attr.target_environment:
        deps.append(ctx.attr.target_environment[PycrossTargetEnvironmentInfo].file)

    toolchain_deps = []
    if cpp_toolchain.all_files:
        toolchain_deps.append(cpp_toolchain.all_files)
    if py_toolchain.files:
        toolchain_deps.append(py_toolchain.files)

    env = dict(cc_vars)
    env.update(ctx.configuration.default_shell_env)

    ctx.actions.run(
        inputs = depset(deps, transitive = toolchain_deps + transitive_sources),
        outputs = [out_wheel, out_name],
        executable = ctx.executable._tool,
        use_default_shell_env = False,
        env = env,
        arguments = args,
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
    toolchains = [PYTHON_TOOLCHAIN_TYPE] + use_cpp_toolchain(),
    fragments = ["cpp"],
    host_fragments = ["cpp"],
)
