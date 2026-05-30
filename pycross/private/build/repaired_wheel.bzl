"""Rule for repairing wheels by bundling native shared libraries."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private:cc_toolchain_util.bzl", "get_libraries")
load("//pycross/private:providers.bzl", "PycrossWheelInfo")

def _pycross_repaired_wheel_impl(ctx):
    # Resolve input wheel file and name file.
    input_wheel_directory = None
    if PycrossWheelInfo in ctx.attr.wheel:
        wheel_info = ctx.attr.wheel[PycrossWheelInfo]
        input_wheel = wheel_info.wheel_file
        input_name_file = wheel_info.name_file
        input_wheel_directory = getattr(wheel_info, "wheel_directory", None)
    else:
        whl_files = [f for f in ctx.files.wheel if f.path.endswith(".whl")]
        if len(whl_files) != 1:
            fail("wheel target must produce exactly one .whl file, got: %s" % [f.path for f in ctx.files.wheel])
        input_wheel = whl_files[0]
        name_files = [f for f in ctx.files.wheel if f.path.endswith(".whl.name")]
        input_name_file = name_files[0] if name_files else None

    # Declare outputs.
    out_wheel = ctx.actions.declare_symlink(ctx.attr.name + ".whl")
    out_wheel_name = ctx.actions.declare_file(ctx.attr.name + ".whl.name")
    out_wheel_directory = ctx.actions.declare_directory(ctx.attr.name + "_wheel")

    staging_dir = None
    if not input_wheel_directory:
        staging_dir = ctx.actions.declare_directory(ctx.attr.name + "_staging")

    # Extract library paths from CcInfo.
    lib_dirs = []
    data_inputs = []
    for dep in ctx.attr.native_deps:
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

    # Resolve optional target environment config JSON for name compatibility safety check
    target_env_file = None
    if ctx.files.target_environment:
        target_env_file = ctx.files.target_environment[0]
        input_files.append(target_env_file)

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

    if target_env_file:
        args.add("--target-environment", target_env_file.path)

    outputs = [out_wheel_directory, out_wheel, out_wheel_name]
    if staging_dir:
        outputs.append(staging_dir)

    ctx.actions.run(
        executable = ctx.executable._repair_tool,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        mnemonic = "RepairWheel",
        progress_message = "Repairing %s" % input_wheel.basename,
    )

    return [
        PycrossWheelInfo(
            wheel_file = out_wheel,
            name_file = out_wheel_name,
            wheel_directory = out_wheel_directory,
        ),
        DefaultInfo(
            files = depset([out_wheel, out_wheel_directory]),
        ),
    ]

pycross_repaired_wheel = rule(
    implementation = _pycross_repaired_wheel_impl,
    attrs = {
        "wheel": attr.label(
            doc = "The input wheel to repair.",
            mandatory = True,
            allow_files = True,
        ),
        "native_deps": attr.label_list(
            doc = "Native dependencies providing shared libraries to bundle.",
            providers = [CcInfo],
        ),
        "target_environment": attr.label(
            doc = "The target environment mapping JSON (resolved dynamically via alias filegroup).",
            default = Label("@pycross_environments//:current"),
            allow_files = True,
        ),
        "_repair_tool": attr.label(
            default = Label("//pycross/private/build/tools:repair_wheel_hook"),
            executable = True,
            cfg = "exec",
        ),
    },
)
