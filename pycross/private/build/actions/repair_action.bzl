"""Action logic for repairing wheels (bundling native libraries)."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("//pycross/private:cc_toolchain_util.bzl", "get_libraries")

def register_repair_action(
        ctx,
        input_wheel_dir,
        repair_tool,
        native_deps = [],
        target_environment = None,
        repair_deps = []):
    """Registers the repairwheel action to bundle native shared libs.

    Args:
        ctx: The rule context.
        input_wheel_dir: File, the input wheel directory TreeArtifact.
        native_deps: list[Target], CcInfo deps whose shared libs to bundle.
        repair_tool: Target, the repair_wheel executable.
        target_environment: File (optional), the target environment JSON.
        repair_deps: list[Target], optional PyInfo targets (e.g. user-provided
            repairwheel) whose site-packages are prepended to PYTHONPATH,
            shadowing the bundled version.

    Returns:
        struct(
            wheel_dir = File,      # tree artifact of repaired wheel contents
        )
    """

    # Use the same whldir_name as the build action for consistency.
    whldir_name = getattr(ctx.attr, "whldir_name", "") or (ctx.attr.name + ".whldir")

    # Declare outputs.
    out_wheel_dir = ctx.actions.declare_directory(whldir_name)

    # Extract library paths from CcInfo.
    lib_dirs = []
    data_inputs = []
    for dep in native_deps:
        if CcInfo in dep:
            for lib in get_libraries(dep[CcInfo]):
                lib_dirs.append(lib.dirname)
                data_inputs.append(depset([lib]))

    # Collect user-provided repair deps (e.g. repairwheel override).
    repair_dep_paths = []
    for dep in repair_deps:
        if PyInfo in dep:
            py_info = dep[PyInfo]
            data_inputs.append(py_info.transitive_sources)
            for imp in py_info.imports.to_list():
                repair_dep_paths.append(imp)

    # Collect inputs.
    input_files = [input_wheel_dir]
    if target_environment:
        input_files.append(target_environment)

    # Build arguments for the repair tool.
    args = ctx.actions.args()
    args.add("--wheel-dir", input_wheel_dir.path)
    args.add("--out-wheel-dir", out_wheel_dir.path)

    for d in depset(lib_dirs).to_list():
        args.add("--lib-dir", d)

    if target_environment:
        args.add("--target-environment", target_environment.path)

    outputs = [out_wheel_dir]

    # Build environment: inject user repair deps into PYTHONPATH if provided.
    env = {}
    if repair_dep_paths:
        env["REPAIRWHEEL_PYTHONPATH"] = ":".join(repair_dep_paths)

    ctx.actions.run(
        executable = repair_tool,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        env = env,
        mnemonic = "PycrossRepairWheel",
        progress_message = "Repairing %s" % input_wheel_dir.basename,
    )

    return struct(
        wheel_dir = out_wheel_dir,
    )
