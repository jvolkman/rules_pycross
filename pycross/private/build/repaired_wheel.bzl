"""Rule for repairing wheels by bundling native shared libraries."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private:cc_toolchain_util.bzl", "get_libraries")
load("//pycross/private:providers.bzl", "PycrossWheelInfo")

def _pycross_repaired_wheel_impl(ctx):
    # Resolve input wheel file and name file.
    if PycrossWheelInfo in ctx.attr.wheel:
        wheel_info = ctx.attr.wheel[PycrossWheelInfo]
        input_wheel = wheel_info.wheel_file
        input_name_file = wheel_info.name_file
    else:
        whl_files = [f for f in ctx.files.wheel if f.path.endswith(".whl")]
        if len(whl_files) != 1:
            fail("wheel target must produce exactly one .whl file, got: %s" % [f.path for f in ctx.files.wheel])
        input_wheel = whl_files[0]
        name_files = [f for f in ctx.files.wheel if f.path.endswith(".whl.name")]
        input_name_file = name_files[0] if name_files else None

    # Declare outputs.
    out_wheel = ctx.actions.declare_file(ctx.attr.name + ".whl")
    out_wheel_name = ctx.actions.declare_file(ctx.attr.name + ".whl.name")
    out_dir = ctx.actions.declare_directory(ctx.attr.name + "_out")
    staging_dir = ctx.actions.declare_directory(ctx.attr.name + "_staging")

    # Extract library paths from CcInfo.
    lib_dirs = []
    data_inputs = []
    for dep in ctx.attr.native_deps:
        if CcInfo in dep:
            for lib in get_libraries(dep[CcInfo]):
                lib_dirs.append(lib.dirname)
                data_inputs.append(depset([lib]))

    # Build environment.
    env = dict(ctx.configuration.default_shell_env)
    env["PYCROSS_WHEEL_OUTPUT_ROOT"] = out_dir.path

    if lib_dirs:
        env["PYCROSS_LIBRARY_PATH"] = ":".join(["$PWD/" + d for d in depset(lib_dirs).to_list()])

    # Collect inputs.
    input_files = [input_wheel]
    if input_name_file:
        input_files.append(input_name_file)

    # Resolve optional target environment config JSON for name compatibility safety check
    target_env_file = None
    if ctx.files.target_environment:
        target_env_file = ctx.files.target_environment[0]
        input_files.append(target_env_file)
        env["PYCROSS_TARGET_ENVIRONMENT"] = target_env_file.path

    # Staging: rename wheel to its real name so repairwheel can parse the filename.
    if input_name_file:
        setup_cmd = """\
REAL_NAME=$(cat {name_file})
cp {wheel} {staging}/"$REAL_NAME"
export PYCROSS_WHEEL_FILE={staging}/"$REAL_NAME"
""".format(
            wheel = input_wheel.path,
            name_file = input_name_file.path,
            staging = staging_dir.path,
        )
    else:
        setup_cmd = """\
cp {wheel} {staging}/
export PYCROSS_WHEEL_FILE={staging}/{basename}
""".format(
            wheel = input_wheel.path,
            staging = staging_dir.path,
            basename = input_wheel.basename,
        )

    env_exports = "\n".join([
        'export %s="%s"' % (k, v)
        for k, v in env.items()
    ])

    tool_exe = ctx.executable._repair_tool

    ctx.actions.run_shell(
        inputs = depset(input_files, transitive = data_inputs),
        outputs = [out_dir, out_wheel, out_wheel_name, staging_dir],
        tools = [ctx.attr._repair_tool[DefaultInfo].files_to_run],
        command = """\
set -e
mkdir -p {staging}
{env_exports}
{setup_cmd}
{tool}

# Collect output
WHEEL=$(ls {out_dir}/*.whl 2>/dev/null | head -1)
if [ -z "$WHEEL" ]; then
    echo "ERROR: No .whl file found in repair output" >&2
    exit 1
fi
cp "$WHEEL" {out_wheel}
basename "$WHEEL" > {out_wheel_name}
""".format(
            staging = staging_dir.path,
            env_exports = env_exports,
            setup_cmd = setup_cmd,
            tool = tool_exe.path,
            out_dir = out_dir.path,
            out_wheel = out_wheel.path,
            out_wheel_name = out_wheel_name.path,
        ),
        mnemonic = "RepairWheel",
        progress_message = "Repairing %s" % input_wheel.basename,
    )

    return [
        PycrossWheelInfo(
            wheel_file = out_wheel,
            name_file = out_wheel_name,
        ),
        DefaultInfo(
            files = depset([out_wheel]),
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
