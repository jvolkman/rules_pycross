"""Implementation of the pycross_pep517_build rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("//pycross/private:providers.bzl", "PycrossBuildMixinInfo", "PycrossWheelInfo")
load(":transitions.bzl", "pycross_exec_platform_transition")

PYTHON_TOOLCHAIN_TYPE = Label("@rules_python//python:toolchain_type")
PYCROSS_TOOLCHAIN_TYPE = Label("//pycross:toolchain_type")

def _is_sibling_repository_layout_enabled():
    test = Label("@rules_pycross_internal//:BUILD.bazel")
    return test.workspace_root.startswith("..")

def _resolve_import_path_fn_inner(workspace_name, bin_dir, sibling_layout):
    bin_dir_parts = bin_dir.split("/")
    output_dir = bin_dir_parts[0]
    bin_dir = paths.join(*bin_dir_parts[-2:])

    def fn(import_name):
        import_repo, import_path = import_name.split("/", 1)
        if import_repo == workspace_name:
            return paths.join(output_dir, bin_dir, import_path)
        if sibling_layout:
            return paths.join(output_dir, import_repo, bin_dir, import_path)
        return paths.join(output_dir, bin_dir, "external", import_repo, import_path)

    return fn

def _pep517_build_impl(ctx):
    inputs = [ctx.file.sdist]
    transitive_inputs = []
    tools = []

    # 1. Resolve Exec & Target Python interpreters
    exec_python = None
    target_python = None
    target_sys_path = []

    py_toolchain = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE].py3_runtime
    if py_toolchain.files:
        transitive_inputs.append(py_toolchain.files)

    if PYCROSS_TOOLCHAIN_TYPE in ctx.toolchains and ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE]:
        pycross_info = ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE].pycross_info
        exec_python = pycross_info.exec_python_executable
        target_python = pycross_info.target_python_executable
        target_sys_path = pycross_info.target_sys_path or []
        if pycross_info.exec_python_files:
            transitive_inputs.append(pycross_info.exec_python_files)
        if pycross_info.target_python_files:
            transitive_inputs.append(pycross_info.target_python_files)
    else:
        interpreter = py_toolchain.interpreter_path
        if not interpreter:
            interpreter = py_toolchain.interpreter.path
        exec_python = interpreter
        target_python = interpreter

    # 2. Resolve site-packages python paths for build dependencies
    dummy_target = ctx.attr._dummy_bin_file[0] if type(ctx.attr._dummy_bin_file) == "list" else ctx.attr._dummy_bin_file
    deps_bin_dir = dummy_target[DefaultInfo].files.to_list()[0].root.path

    imports = depset(transitive = [d[PyInfo].imports for d in ctx.attr.deps])
    map_fn = _resolve_import_path_fn_inner(
        ctx.workspace_name,
        deps_bin_dir,
        _is_sibling_repository_layout_enabled(),
    )
    python_paths = [map_fn(imp) for imp in imports.to_list()]
    transitive_inputs.extend([dep[PyInfo].transitive_sources for dep in ctx.attr.deps])

    # 3. Resolve and merge pluggable Mixins (e.g., CC compiler JSONs)
    mixin_jsons = []
    for mixin_target in ctx.attr.mixins:
        mixin_info = mixin_target[PycrossBuildMixinInfo]
        mixin_jsons.append(mixin_info.config_json.path)
        transitive_inputs.append(mixin_info.files)

    # 4. Resolve user-provided config settings (expand location variables and write to json)
    config_settings_file = None
    if ctx.attr.config_settings:
        config_settings_file = ctx.actions.declare_file(paths.join(ctx.attr.name, "config_settings.json"))
        inputs.append(config_settings_file)

        expanded_settings = {}
        for key, value in ctx.attr.config_settings.items():
            expanded_settings[key] = [ctx.expand_location(vi, ctx.attr.deps) for vi in value]

        ctx.actions.write(config_settings_file, json.encode(expanded_settings))

    # 4.1. Resolve pkg_config_files
    pkg_config_paths = []
    for f in ctx.files.pkg_config_files:
        pkg_config_paths.append(f.path)
        inputs.append(f)

    # 4.2. Resolve path_tools (list of executable labels)
    path_tools_list = []
    for target in ctx.attr.path_tools:
        exe = target[DefaultInfo].files_to_run.executable
        if not exe:
            fail("%s is not executable" % target.label)
        path_tools_list.append({
            "name": exe.basename,
            "path": exe.path,
        })
        inputs.append(exe)
        tools.append(target[DefaultInfo].files_to_run)

    # 5. Declare output files
    sdist_name = ctx.file.sdist.basename
    if sdist_name.lower().endswith(".tar.gz"):
        wheel_name = sdist_name[:-7]
    else:
        wheel_name = sdist_name.rsplit(".", 1)[0]

    out_wheel = ctx.actions.declare_symlink(paths.join(ctx.attr.name, wheel_name + ".whl"))
    out_wheel_name = ctx.actions.declare_file(paths.join(ctx.attr.name, wheel_name + ".whl.name"))
    out_wheel_directory = ctx.actions.declare_directory(paths.join(ctx.attr.name, "wheel"))

    # 6. Write master `bazel_config.json` configuration file
    master_config = {
        "sdist": ctx.file.sdist.path,
        "exec_python": exec_python,
        "target_python": target_python,
        "target_sys_path": target_sys_path,
        "python_paths": python_paths,
        "mixins": mixin_jsons,
        "config_settings_raw": config_settings_file.path if config_settings_file else None,
        "pkg_config_files": pkg_config_paths,
        "path_tools": path_tools_list,
        "sdist_python_paths": ctx.attr.sdist_python_paths,
        "wheel_file": out_wheel.path,
        "wheel_name_file": out_wheel_name.path,
        "wheel_directory": out_wheel_directory.path,
    }

    config_json = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_json, json.encode(master_config))
    inputs.append(config_json)

    # 7. Execute pluggable Python builder tool
    # Inject builder runfiles
    tools.append(ctx.attr.builder[DefaultInfo].files_to_run)

    sdist_root = out_wheel.dirname + "/sdist"

    build_root = ctx.bin_dir.path + "/" + ctx.label.package + "/" + ctx.label.name + "_tmp"
    action_env = dict(ctx.configuration.default_shell_env)
    action_env.update({
        "PYCROSS_BUILD_ROOT": build_root,
        "PYCROSS_SDIST_DIR": sdist_root,
        "PYTHONPATH": ":".join([sdist_root] + python_paths),
    })

    ctx.actions.run(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_wheel, out_wheel_name, out_wheel_directory],
        executable = ctx.executable.builder,
        arguments = [config_json.path],
        env = action_env,
        tools = tools,
        mnemonic = "Pep517Build",
        progress_message = "Building wheel %s" % sdist_name,
    )

    return [
        DefaultInfo(
            files = depset([out_wheel]),
        ),
        PycrossWheelInfo(
            wheel_file = out_wheel,
            name_file = out_wheel_name,
            wheel_directory = out_wheel_directory,
        ),
    ]

pycross_pep517_build = rule(
    implementation = _pep517_build_impl,
    attrs = {
        "sdist": attr.label(mandatory = True, allow_single_file = True),
        "builder": attr.label(mandatory = True, executable = True, cfg = "exec"),
        "mixins": attr.label_list(providers = [PycrossBuildMixinInfo]),
        "config_settings": attr.string_list_dict(),
        "sdist_python_paths": attr.string_list(
            doc = "Sdist-relative paths to add to PYTHONPATH during the build (e.g., vendored build utilities).",
        ),
        "pkg_config_files": attr.label_list(allow_files = True),
        "path_tools": attr.label_list(
            cfg = pycross_exec_platform_transition,
        ),
        "deps": attr.label_list(
            providers = [PyInfo],
            cfg = pycross_exec_platform_transition,
        ),
        "_dummy_bin_file": attr.label(
            default = Label("//pycross/private:dummy_bin_file"),
            allow_single_file = True,
            cfg = pycross_exec_platform_transition,
        ),
    },
    toolchains = [
        PYTHON_TOOLCHAIN_TYPE,
        config_common.toolchain_type(PYCROSS_TOOLCHAIN_TYPE, mandatory = False),
    ],
)
