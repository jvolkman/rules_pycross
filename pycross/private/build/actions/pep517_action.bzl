"""Action logic for PEP 517 wheel building."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:py_info.bzl", "PyInfo")

PYTHON_TOOLCHAIN_TYPE = Label("@rules_python//python:toolchain_type")
PYCROSS_TOOLCHAIN_TYPE = Label("//pycross:toolchain_type")

def _is_sibling_repository_layout_enabled():
    # This checks if sibling repository layout is enabled.
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

def register_pep517_action(
        ctx,
        sdist,
        builder,
        deps,
        build_deps,
        config_settings = {},
        site_hooks = [],
        tool_executables = [],
        layers = [],
        pkg_config_files = [],
        extra_files = {},
        extra_inputs = [],
        pre_build_patches = [],
        cargo_vendored_sources = None):
    """Registers the PEP 517 wheel build action.

    Args:
        ctx: The rule context.
        sdist: File, the source distribution archive.
        builder: Target, the builder executable.
        deps: list[Target], runtime Python deps (PyInfo).
        build_deps: list[Target], build-time Python deps (PyInfo).
        config_settings: dict, PEP 517 config settings.
        site_hooks: list[str], Python snippets for interpreter startup.
        tool_executables: list[struct(name, file)], executables to place on PATH.
        layers: list[struct], CC/Rust environment from extract_*_layer().
        pkg_config_files: list[File], pkg-config .pc files.
        extra_files: dict[str, File], files to inject into the sdist directory
            before building, keyed by their target filename (e.g. "Cargo.lock").
        extra_inputs: list[File], extra inputs to the action.
        pre_build_patches: list[File], patch files to apply to the sdist before building.
        cargo_vendored_sources: str, path to the vendored cargo sources relative to the execution root.

    Returns:
        struct(
            wheelhouse = File,  # TreeArtifact containing one .whl file
        )
    """
    inputs = [sdist] + extra_inputs
    transitive_inputs = []
    tools = []

    # Resolve interpreters
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

    # Resolve site-packages python paths for dependencies
    dummy_target = ctx.attr._dummy_bin_file[0] if type(ctx.attr._dummy_bin_file) == "list" else ctx.attr._dummy_bin_file
    deps_bin_dir = dummy_target[DefaultInfo].files.to_list()[0].root.path

    all_deps = deps + build_deps
    imports = depset(transitive = [d[PyInfo].imports for d in all_deps])
    map_fn = _resolve_import_path_fn_inner(
        ctx.workspace_name,
        deps_bin_dir,
        _is_sibling_repository_layout_enabled(),
    )
    python_paths = [map_fn(imp) for imp in imports.to_list()]
    transitive_inputs.extend([dep[PyInfo].transitive_sources for dep in all_deps])

    # Resolve user-provided config settings
    config_settings_file = None
    if config_settings != None and type(config_settings) == "dict" and len(config_settings) > 0:
        config_settings_file = ctx.actions.declare_file(paths.join(ctx.attr.name, "config_settings.json"))
        inputs.append(config_settings_file)

        unique_deps = []
        seen_labels = {}
        for dep in deps + build_deps:
            if dep.label not in seen_labels:
                seen_labels[dep.label] = True
                unique_deps.append(dep)

        expanded_settings = {}
        for key, value in config_settings.items():
            expanded_settings[key] = [ctx.expand_location(vi, unique_deps) for vi in value]

        ctx.actions.write(config_settings_file, json.encode(expanded_settings))

    # Resolve pkg-config and hooks
    expanded_site_hooks = []
    make_vars = {}
    for layer in layers:
        if layer and hasattr(layer, "make_vars"):
            make_vars.update(layer.make_vars)
    for hook in site_hooks:
        expanded_site_hooks.append(ctx.expand_make_variables("site_hooks", hook, make_vars))

    pkg_config_paths = []
    for f in pkg_config_files:
        pkg_config_paths.append(f.path)
        inputs.append(f)

    # Resolve path tools
    path_tools_list = []
    for tool in tool_executables:
        path_tools_list.append({
            "name": tool.name,
            "path": tool.file.path,
        })
        inputs.append(tool.file)
        if hasattr(tool, "files_to_run"):
            tools.append(tool.files_to_run)

    # Include environments
    layer_jsons = []
    for layer in layers:
        if layer:
            layer_jsons.append(layer.config_json.path)
            inputs.append(layer.config_json)
            transitive_inputs.append(layer.transitive_files)

    # Declare output files
    out_wheelhouse = ctx.actions.declare_directory(paths.join(ctx.attr.name, "wheelhouse"))

    # Write main config file
    main_config = {
        "sdist": sdist.path,
        "exec_python": exec_python,
        "target_python": target_python,
        "target_sys_path": target_sys_path,
        "python_paths": python_paths,
        "layers": layer_jsons,
        "config_settings_raw": config_settings_file.path if config_settings_file else None,
        "site_hooks": expanded_site_hooks,
        "pkg_config_files": pkg_config_paths,
        "path_tools": path_tools_list,
        "wheelhouse": out_wheelhouse.path,
    }
    if cargo_vendored_sources:
        main_config["cargo_vendored_sources"] = cargo_vendored_sources

    # Extra files to inject into the sdist before building.
    if extra_files:
        extra_files_config = {}
        for name, f in extra_files.items():
            extra_files_config[name] = f.path
            inputs.append(f)
        main_config["extra_files"] = extra_files_config

    if pre_build_patches:
        patch_paths = []
        for f in pre_build_patches:
            patch_paths.append(f.path)
            inputs.append(f)
        main_config["pre_build_patches"] = patch_paths

    config_json = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_json, json.encode(main_config))
    inputs.append(config_json)

    # Execute action
    tools.append(builder[DefaultInfo].files_to_run)
    if builder[DefaultInfo].default_runfiles:
        transitive_inputs.append(builder[DefaultInfo].default_runfiles.files)

    sdist_root = out_wheelhouse.dirname + "/sdist"
    build_root = ctx.bin_dir.path + "/" + ctx.label.package + "/" + ctx.label.name + "_tmp"

    action_env = dict(ctx.configuration.default_shell_env)
    action_env.update({
        "PYCROSS_BUILD_ROOT": build_root,
        "PYCROSS_SDIST_DIR": sdist_root,
        "PYTHONPATH": ":".join([sdist_root] + python_paths),
    })

    ctx.actions.run(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_wheelhouse],
        executable = builder[DefaultInfo].files_to_run.executable,
        arguments = [config_json.path],
        env = action_env,
        tools = tools,
        mnemonic = "Pep517Build",
        progress_message = "Building wheel %s" % sdist.basename,
    )

    return struct(
        wheelhouse = out_wheelhouse,
    )
