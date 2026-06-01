"""Action logic for repairing wheels (bundling native libraries)."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private:cc_toolchain_util.bzl", "get_libraries")

def register_repair_action(
        ctx,
        input_wheel,
        input_name_file,
        input_wheel_directory,
        native_deps,
        repair_tool,
        target_environment = None):
    """Registers the repairwheel action to bundle native shared libs.

    Args:
        ctx: The rule context.
        input_wheel: File, the raw wheel to repair.
        input_name_file: File, the raw wheel name file.
        input_wheel_directory: File (optional), the unzipped wheel directory.
        native_deps: list[Target], CcInfo deps whose shared libs to bundle.
        repair_tool: Target, the repair_wheel executable.
        target_environment: File (optional), the target environment JSON.

    Returns:
        struct(
            wheel = File,           # the repaired .whl
            name_file = File,       # the repaired name file
            wheel_directory = File, # tree artifact of repaired wheel contents
        )
    """

    # Declare outputs.
    out_wheel = ctx.actions.declare_symlink(ctx.attr.name + "_repaired.whl")
    out_wheel_name = ctx.actions.declare_file(ctx.attr.name + "_repaired.whl.name")
    out_wheel_directory = ctx.actions.declare_directory(ctx.attr.name + "_repaired_wheel")

    staging_dir = None
    if not input_wheel_directory:
        staging_dir = ctx.actions.declare_directory(ctx.attr.name + "_staging")

    # Extract library paths from CcInfo.
    lib_dirs = []
    data_inputs = []
    for dep in native_deps:
        if CcInfo in dep:
            for lib in get_libraries(dep[CcInfo]):
                lib_dirs.append(lib.dirname)
                data_inputs.append(depset([lib]))

    # Collect inputs.
    input_files = [input_wheel]
    if input_name_file:
        input_files.append(input_name_file)
    if input_wheel_directory:
        input_files.append(input_wheel_directory)
    if target_environment:
        input_files.append(target_environment)

    # Build arguments for the repair tool.
    args = ctx.actions.args()
    args.add("--wheel-file", input_wheel)
    args.add("--output-dir", out_wheel_directory.path)
    args.add("--out-wheel-file", out_wheel.path)
    args.add("--out-wheel-name-file", out_wheel_name.path)
    args.add("--out-wheel-dir-basename", out_wheel_directory.basename)

    if input_wheel_directory:
        args.add("--wheel-directory", input_wheel_directory.path)
    elif input_name_file:
        args.add("--wheel-name-file", input_name_file.path)
        args.add("--staging-dir", staging_dir.path)
    else:
        args.add("--staging-dir", staging_dir.path)

    for d in depset(lib_dirs).to_list():
        args.add("--lib-dir", d)

    if target_environment:
        args.add("--target-environment", target_environment.path)

    outputs = [out_wheel_directory, out_wheel, out_wheel_name]
    if staging_dir:
        outputs.append(staging_dir)

    ctx.actions.run(
        executable = repair_tool,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        mnemonic = "RepairWheel",
        progress_message = "Repairing %s" % input_wheel.basename,
    )

    return struct(
        wheel = out_wheel,
        name_file = out_wheel_name,
        wheel_directory = out_wheel_directory,
    )
