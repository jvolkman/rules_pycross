"""Implementation of the pycross_wheel_transform rule."""

load(":providers.bzl", "PycrossWheelInfo")

def _pycross_wheel_transform_impl(ctx):
    # Resolve input wheel file and name file from PycrossWheelInfo or dynamically from files
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

    # Build env vars with make variable expansion.
    env = dict(ctx.configuration.default_shell_env)
    env["PYCROSS_WHEEL_OUTPUT_ROOT"] = out_wheel_directory.path

    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_make_variables("env", ctx.expand_location(value, ctx.attr.data), {})

    # Collect inputs.
    input_files = [input_wheel]
    if input_name_file:
        input_files.append(input_name_file)
    if input_wheel_directory:
        input_files.append(input_wheel_directory)
    data_inputs = [dep[DefaultInfo].files for dep in ctx.attr.data]

    staging_dir = None
    if not input_wheel_directory:
        staging_dir = ctx.actions.declare_directory(ctx.attr.name + "_staging")

    if input_wheel_directory:
        setup_cmd = """WHEEL_FILE=$(ls {wheel_dir}/*.whl)
export PYCROSS_WHEEL_FILE="$WHEEL_FILE"
""".format(
            wheel_dir = input_wheel_directory.path,
        )
    elif input_name_file:
        setup_cmd = """mkdir -p {staging}
REAL_NAME=$(cat {name_file})
cp {wheel} {staging}/"$REAL_NAME"
export PYCROSS_WHEEL_FILE={staging}/"$REAL_NAME"
""".format(
            wheel = input_wheel.path,
            name_file = input_name_file.path,
            staging = staging_dir.path,
        )
    else:
        setup_cmd = """mkdir -p {staging}
cp {wheel} {staging}/
export PYCROSS_WHEEL_FILE={staging}/{basename}
""".format(
            wheel = input_wheel.path,
            staging = staging_dir.path,
            basename = input_wheel.basename,
        )

    # Build the env export commands.
    env_exports = "\n".join([
        'export %s="%s"' % (k, v)
        for k, v in env.items()
    ])

    tool_exe = ctx.executable.transform

    outputs = [out_wheel_directory, out_wheel, out_wheel_name]
    if staging_dir:
        outputs.append(staging_dir)

    ctx.actions.run_shell(
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        tools = [ctx.attr.transform[DefaultInfo].files_to_run],
        command = """set -e
{env_exports}
{setup_cmd}
{tool}

# Collect output
WHEEL=$(ls {out_wheel_dir}/*.whl 2>/dev/null | head -1)
if [ -z "$WHEEL" ]; then
    echo "ERROR: No .whl file found in transform output" >&2
    exit 1
fi
ln -sf "{wheel_dir_basename}/$(basename "$WHEEL")" {out_wheel}
basename "$WHEEL" > {out_wheel_name}
""".format(
            env_exports = env_exports,
            setup_cmd = setup_cmd,
            tool = tool_exe.path,
            out_wheel_dir = out_wheel_directory.path,
            wheel_dir_basename = out_wheel_directory.basename,
            out_wheel = out_wheel.path,
            out_wheel_name = out_wheel_name.path,
        ),
        mnemonic = "WheelTransform",
        progress_message = "Transforming %s" % input_wheel.basename,
    )

    return [
        PycrossWheelInfo(
            wheel_file = out_wheel,
            name_file = out_wheel_name,
            wheel_directory = out_wheel_directory,
        ),
        DefaultInfo(
            files = depset([out_wheel]),
        ),
    ]

pycross_wheel_transform = rule(
    implementation = _pycross_wheel_transform_impl,
    attrs = {
        "wheel": attr.label(
            doc = "The input wheel target. Can produce multiple files (.whl and .whl.name).",
            mandatory = True,
            allow_files = True,
        ),
        "transform": attr.label(
            doc = "The transform tool to execute.",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "data": attr.label_list(
            doc = "Additional data dependencies available to the tool.",
            allow_files = True,
        ),
        "env": attr.string_dict(
            doc = (
                "Environment variables passed to the tool. " +
                "Values are subject to make variable and location expansion."
            ),
        ),
    },
)
