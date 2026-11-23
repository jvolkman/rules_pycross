"""Action logic for PEP 517 wheel building."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@pypackaging.bzl", "pypackaging")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("//pycross/private:providers.bzl", "PycrossPackageInfo")

PYTHON_TOOLCHAIN_TYPE = Label("@rules_python//python:toolchain_type")
PYCROSS_TOOLCHAIN_TYPE = Label("//pycross:toolchain_type")

def is_sibling_repository_layout_enabled():
    # This checks if sibling repository layout is enabled.
    test = Label("@pycross_internal_deps//:BUILD.bazel")
    return test.workspace_root.startswith("..")

def resolve_import_path_fn(workspace_name, root_path, sibling_layout):
    """Returns a function mapping PyInfo.imports entries to execroot paths.

    Args:
        workspace_name: str, the main workspace name.
        root_path: str, the File root path (empty string for source files).
        sibling_layout: bool, whether sibling repository layout is enabled.

    Returns:
        A function accepting an import_name string and returning an execroot path.
    """
    if not root_path:
        def source_fn(import_name):
            import_repo, _, import_path = import_name.partition("/")
            if import_repo == workspace_name:
                return import_path or "."
            if sibling_layout:
                return paths.join("..", import_repo, import_path) if import_path else paths.join("..", import_repo)
            return paths.join("external", import_repo, import_path) if import_path else paths.join("external", import_repo)

        return source_fn

    bin_dir_parts = root_path.split("/")
    output_dir = bin_dir_parts[0]
    bin_dir = paths.join(*bin_dir_parts[-2:])

    def fn(import_name):
        import_repo, _, import_path = import_name.partition("/")
        if import_repo == workspace_name:
            return paths.join(output_dir, bin_dir, import_path) if import_path else paths.join(output_dir, bin_dir)
        if sibling_layout:
            return paths.join(output_dir, import_repo, bin_dir, import_path) if import_path else paths.join(output_dir, import_repo, bin_dir)
        return paths.join(output_dir, bin_dir, "external", import_repo, import_path) if import_path else paths.join(output_dir, bin_dir, "external", import_repo)

    return fn

def validate_build_requires(build_requires, build_deps, sdist_name):
    """Validate PEP 508 build-system.requires against resolved build_deps versions.

    Args:
        build_requires: list[str] of PEP 508 requirement strings.
        build_deps: list[Target] of resolved build dependency targets (may carry PycrossPackageInfo).
        sdist_name: str, basename of the sdist archive for warning messages.

    Returns:
        list[str] of warning messages for any unsatisfied version specifiers.
    """
    if not build_requires:
        return []

    versions_by_pkg = {}
    for dep in build_deps:
        if PycrossPackageInfo not in dep:
            continue
        info = dep[PycrossPackageInfo]
        if not info.package_name or not info.package_version:
            continue
        if pypackaging.version.try_parse(info.package_version) == None:
            continue
        norm = pypackaging.utils.canonicalize_name(info.package_name)
        versions = versions_by_pkg.setdefault(norm, [])
        if info.package_version not in versions:
            versions.append(info.package_version)

    if not versions_by_pkg:
        return []

    warnings = []
    for req_str in build_requires:
        req = pypackaging.requirements.parse(req_str)
        if req.marker or not req.specifier or not req.specifier.specs:
            continue

        req_name = req.name
        if req_name == "oldest-supported-numpy":
            req_name = "numpy"

        versions = versions_by_pkg.get(req_name)
        if not versions:
            continue

        if any([pypackaging.specifiers.set_contains(req.specifier, v) for v in versions]):
            continue

        if len(versions) == 1:
            warnings.append(
                "WARNING: The build environment provides '{}=={}', but '{}' requires '{}' in pyproject.toml.".format(
                    req_name,
                    versions[0],
                    sdist_name,
                    req_str,
                ),
            )
        else:
            warnings.append(
                "WARNING: None of the provided '{}' versions ({}) satisfy '{}' required by '{}' in pyproject.toml.".format(
                    req_name,
                    ", ".join(versions),
                    req_str,
                    sdist_name,
                ),
            )

    return warnings

def register_pep517_action(
        ctx,
        builder,
        additional_build_deps = [],
        layers = [],
        tool_executables = [],
        extra_files = {},
        extra_inputs = [],
        env = {},
        resource_set = None):
    """Registers the PEP 517 wheel build action.

    Common attributes (sdist, deps, build_deps, site_hooks, pre_build_patches,
    config_settings, pkg_config_files) are extracted directly from ctx.attr/ctx.file/ctx.files.
    This avoids repetitive plumbing in each build rule implementation.

    Args:
        ctx: The rule context.
        builder: Target, the builder executable.
        additional_build_deps: list[Target], extra build-time deps to merge with ctx.attr.build_deps.
        layers: list[struct], CC/Rust environment from extract_*_layer().
        tool_executables: list[struct(name, file)], executables to place on PATH.
        extra_files: dict[str, File], files to inject into the sdist directory
            before building, keyed by their target filename (e.g. "package.json").
        extra_inputs: list[File], extra inputs to the action.
        env: dict[str, str], extra environment variables to pass to the action.
        resource_set: function or dict, resource requirements for the action.

    Returns:
        struct(
            wheel_dir = File,  # TreeArtifact containing one .whl file
        )
    """

    # Extract common attributes from ctx
    sdist = ctx.file.sdist
    deps = list(ctx.attr.deps)
    build_deps = list(ctx.attr.build_deps) + list(additional_build_deps)
    build_requires = list(getattr(ctx.attr, "build_requires", []))
    if build_requires:
        version_check_deps = build_deps + list(getattr(ctx.attr, "tool_deps", []))
        for warning in validate_build_requires(build_requires, version_check_deps, sdist.basename):
            # buildifier: disable=print
            print(warning)
    site_hooks = list(ctx.attr.site_hooks)
    pre_build_patches = list(ctx.files.pre_build_patches)
    config_settings = dict(getattr(ctx.attr, "config_settings", {}))
    build_env = dict(getattr(ctx.attr, "build_env", {}))
    data = list(getattr(ctx.attr, "data", []))
    pre_build_hooks = list(getattr(ctx.attr, "pre_build_hooks", []))
    post_build_hooks = list(getattr(ctx.attr, "post_build_hooks", []))
    pkg_config_files = list(getattr(ctx.files, "pkg_config_files", []))
    whldir_name = getattr(ctx.attr, "whldir_name", "") or (ctx.attr.name + ".whldir")

    inputs = [sdist] + extra_inputs
    transitive_inputs = []
    tools = []

    # Resolve interpreters
    exec_python = None
    target_python = None

    py_toolchain = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE].py3_runtime
    if py_toolchain.files:
        transitive_inputs.append(py_toolchain.files)

    if PYCROSS_TOOLCHAIN_TYPE in ctx.toolchains and ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE]:
        pycross_info = ctx.toolchains[PYCROSS_TOOLCHAIN_TYPE].pycross_info
        exec_python = pycross_info.exec_python_executable
        target_python = pycross_info.target_python_executable
        if pycross_info.exec_python_files:
            transitive_inputs.append(pycross_info.exec_python_files)
        if pycross_info.target_python_files:
            transitive_inputs.append(pycross_info.target_python_files)
        if pycross_info.exec_python_files_to_run:
            tools.append(pycross_info.exec_python_files_to_run)
        if pycross_info.target_python_files_to_run:
            tools.append(pycross_info.target_python_files_to_run)
    else:
        files_to_run = getattr(py_toolchain, "interpreter_files_to_run", None)
        if files_to_run and files_to_run.executable:
            interpreter = files_to_run.executable.path
            tools.append(files_to_run)
        elif py_toolchain.interpreter_path:
            interpreter = py_toolchain.interpreter_path
        else:
            interpreter = py_toolchain.interpreter.path
        exec_python = interpreter
        target_python = interpreter

    # Resolve site-packages python paths for dependencies
    dummy_target = ctx.attr._dummy_bin_file[0] if type(ctx.attr._dummy_bin_file) == "list" else ctx.attr._dummy_bin_file
    deps_bin_dir = dummy_target[DefaultInfo].files.to_list()[0].root.path

    all_deps = deps + build_deps
    imports = depset(transitive = [d[PyInfo].imports for d in all_deps])
    map_fn = resolve_import_path_fn(
        ctx.workspace_name,
        deps_bin_dir,
        is_sibling_repository_layout_enabled(),
    )
    python_paths = [map_fn(imp) for imp in imports.to_list()]

    # Installed wheels (pycross_wheel_library TreeArtifacts) don't list their site-packages in
    # PyInfo.imports under venvs_site_packages, so add them from the sources as well.
    sources = depset(transitive = [dep[PyInfo].transitive_sources for dep in all_deps])
    for src in sources.to_list():
        if src.is_directory:
            site_packages = paths.join(src.path, "site-packages")
            if site_packages not in python_paths:
                python_paths.append(site_packages)
    transitive_inputs.append(sources)

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
    out_wheel_dir = ctx.actions.declare_directory(paths.join(ctx.attr.name, whldir_name))

    # Write main config file
    main_config = {
        "sdist": sdist.path,
        "source_dir": getattr(ctx.attr, "source_dir", ""),
        "exec_python": exec_python,
        "target_python": target_python,
        "python_paths": python_paths,
        "layers": layer_jsons,
        "config_settings_raw": config_settings_file.path if config_settings_file else None,
        "site_hooks": expanded_site_hooks,
        "pkg_config_files": pkg_config_paths,
        "path_tools": path_tools_list,
        "wheel_dir": out_wheel_dir.path,
    }

    # Merge programmatic env defaults (e.g. parallelism flags from
    # resource_size) with user-specified build_env.  User values win.
    merged_env = dict(env)
    merged_env.update(build_env)
    if merged_env:
        unique_deps = []
        seen_labels = {}
        for dep in deps + build_deps + data:
            if dep.label not in seen_labels:
                seen_labels[dep.label] = True
                unique_deps.append(dep)
        expanded_env = {}
        for key, value in merged_env.items():
            expanded_env[key] = ctx.expand_location(value, unique_deps)
        main_config["build_env"] = expanded_env

    # Data files: make available in the sandbox.
    for d in data:
        transitive_inputs.append(d[DefaultInfo].files)

    # Pre-build hooks: executables run before the PEP 517 build.
    if pre_build_hooks:
        hook_paths = []
        for hook in pre_build_hooks:
            exe = hook[DefaultInfo].files_to_run.executable
            hook_paths.append(exe.path)
            tools.append(hook[DefaultInfo].files_to_run)
        main_config["pre_build_hooks"] = hook_paths

    # Post-build hooks: executables run after the wheel is built.
    if post_build_hooks:
        hook_paths = []
        for hook in post_build_hooks:
            exe = hook[DefaultInfo].files_to_run.executable
            hook_paths.append(exe.path)
            tools.append(hook[DefaultInfo].files_to_run)
        main_config["post_build_hooks"] = hook_paths

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

    # Undeclared scratch dirs, unique per target (out_wheel_dir.dirname
    # includes the repo, package and target name). The builder wipes them
    # before use, since non-sandboxed strategies leave them behind.
    sdist_root = out_wheel_dir.dirname + "/sdist"
    build_root = out_wheel_dir.dirname + "/_tmp"

    action_env = dict(ctx.configuration.default_shell_env)
    action_env.update({
        "PYCROSS_BUILD_ROOT": build_root,
        "PYCROSS_SDIST_DIR": sdist_root,
        "PYTHONPATH": ":".join([sdist_root] + python_paths),
    })

    # Also set programmatic env on the action so subprocesses inherit
    # them directly, in addition to build_env in the config JSON.
    action_env.update(env)

    # No "supports-path-mapping": paths are embedded in the config JSON and
    # env, which Bazel doesn't rewrite.
    ctx.actions.run(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_wheel_dir],
        executable = builder[DefaultInfo].files_to_run.executable,
        arguments = [config_json.path],
        env = action_env,
        tools = tools,
        mnemonic = "PycrossPep517Build",
        progress_message = "Building wheel %s" % sdist.basename,
        resource_set = resource_set,
    )

    return struct(
        wheel_dir = out_wheel_dir,
    )
