"""Action logic for repairing wheels (bundling native libraries)."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("//pycross/private/build:cc_toolchain_util.bzl", "get_libraries")
load("//pycross/private/build:wheel_shared_libraries.bzl", "wheel_shared_libraries")
load(
    "//pycross/private/build/actions:pep517_action.bzl",
    "is_sibling_repository_layout_enabled",
    "resolve_import_path_fn",
)

def _file_dirname(f):
    return f.dirname

def register_repair_action(
        ctx,
        input_wheel_dir,
        repair_tool,
        native_deps = [],
        target_environment = None,
        repair_exclude_globs = [],
        repair_deps = [],
        resource_set = None):
    """Registers the repairwheel action to bundle native shared libs.

    Args:
        ctx: The rule context.
        input_wheel_dir: File, the input wheel directory TreeArtifact.
        native_deps: list[Target], CcInfo deps whose shared libs to bundle. Shared
            libraries from `pycross_wheel_cc_import` targets belong to other wheels:
            repair can find them, but excludes them from the repaired wheel.
        repair_tool: Target, the repair_wheel executable.
        target_environment: File (optional), the target environment JSON.
        repair_exclude_globs: list[str], shared library globs to leave unbundled.
        repair_deps: list[Target], optional PyInfo targets (e.g. user-provided
            repairwheel) whose site-packages are prepended to PYTHONPATH,
            shadowing the bundled version.
        resource_set: function or dict, resource requirements for the action.

    Returns:
        struct(
            wheel_dir = File,      # tree artifact of repaired wheel contents
        )
    """

    # Use the same whldir_name as the build action for consistency.
    whldir_name = getattr(ctx.attr, "whldir_name", "") or (ctx.attr.name + ".whldir")

    # Declare outputs.
    out_wheel_dir = ctx.actions.declare_directory(whldir_name)

    # Extract dynamic library files from CcInfo (skipping static/interface archives).
    lib_files = []
    data_inputs = []
    wheel_lib_excludes = []
    for dep in native_deps:
        if CcInfo in dep:
            lib_files.extend(get_libraries(dep[CcInfo]).dynamic)

    # Another wheel ships these at runtime. Bundling a copy would load the library twice,
    # with separate state.
    for lib in wheel_shared_libraries(native_deps).to_list():
        lib_files.append(lib)
        wheel_lib_excludes.append(lib.basename)

    # Collect user-provided repair deps (e.g. repairwheel override).
    repair_dep_paths = []
    seen_repair_paths = {}
    sibling_layout = is_sibling_repository_layout_enabled()
    for dep in repair_deps:
        if PyInfo in dep:
            py_info = dep[PyInfo]
            data_inputs.append(py_info.transitive_sources)
            dep_sources = py_info.transitive_sources.to_list()
            root_paths = collections.uniq([src.root.path for src in dep_sources]) or [ctx.bin_dir.path]
            map_fns = [
                resolve_import_path_fn(ctx.workspace_name, root_path, sibling_layout)
                for root_path in root_paths
            ]
            for imp in py_info.imports.to_list():
                for map_fn in map_fns:
                    resolved = map_fn(imp)
                    if resolved not in seen_repair_paths:
                        seen_repair_paths[resolved] = True
                        repair_dep_paths.append(resolved)

            # Installed wheels don't list their site-packages in PyInfo.imports under
            # venvs_site_packages (see pep517_action.bzl).
            for src in dep_sources:
                if src.is_directory:
                    site_packages = src.path + "/site-packages"
                    if site_packages not in seen_repair_paths:
                        seen_repair_paths[site_packages] = True
                        repair_dep_paths.append(site_packages)

    # Collect inputs.
    input_files = [input_wheel_dir] + lib_files
    if target_environment:
        input_files.append(target_environment)

    # Build arguments for the repair tool.
    # Pass File objects (not .path strings) so Bazel path mapping can rewrite them.
    args = ctx.actions.args()
    args.add_all([input_wheel_dir], before_each = "--wheel-dir", expand_directories = False)
    args.add_all([out_wheel_dir], before_each = "--out-wheel-dir", expand_directories = False)

    if lib_files:
        args.add_all(
            lib_files,
            before_each = "--lib-dir",
            map_each = _file_dirname,
            uniquify = True,
        )

    for pattern in repair_exclude_globs + collections.uniq(wheel_lib_excludes):
        args.add("--exclude", pattern)

    if target_environment:
        args.add("--target-environment", target_environment)

    outputs = [out_wheel_dir]

    # Build environment: inject user repair deps into PYTHONPATH if provided.
    env = {}
    execution_requirements = {"supports-path-mapping": "1"}
    if repair_dep_paths:
        env["REPAIRWHEEL_PYTHONPATH"] = ":".join(repair_dep_paths)

        # REPAIRWHEEL_PYTHONPATH embeds raw .path strings in env, which path mapping does not rewrite.
        execution_requirements = {}

    ctx.actions.run(
        executable = repair_tool,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        env = env,
        mnemonic = "PycrossRepairWheel",
        execution_requirements = execution_requirements,
        progress_message = "Repairing %s" % input_wheel_dir.basename,
        resource_set = resource_set,
    )

    return struct(
        wheel_dir = out_wheel_dir,
    )
