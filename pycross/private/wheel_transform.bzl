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
    env = {}
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

    # Build arguments for the wheel transformer wrapper.
    args = ctx.actions.args()
    args.add("--wheel-file", input_wheel)
    args.add("--output-dir", out_wheel_directory.path)
    args.add("--out-wheel-file", out_wheel.path)
    args.add("--out-wheel-name-file", out_wheel_name.path)
    args.add("--out-wheel-dir-basename", out_wheel_directory.basename)
    args.add("--tool", ctx.executable.transform)

    if input_wheel_directory:
        args.add("--wheel-directory", input_wheel_directory.path)
    elif input_name_file:
        args.add("--wheel-name-file", input_name_file.path)
        args.add("--staging-dir", staging_dir.path)
    else:
        args.add("--staging-dir", staging_dir.path)

    for key, value in env.items():
        args.add("--env", "%s=%s" % (key, value))

    outputs = [out_wheel_directory, out_wheel, out_wheel_name]
    if staging_dir:
        outputs.append(staging_dir)

    ctx.actions.run(
        executable = ctx.executable._wheel_transformer,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        tools = [ctx.attr.transform[DefaultInfo].files_to_run],
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
        "_wheel_transformer": attr.label(
            default = Label("//pycross/private/build/tools:wheel_transformer"),
            executable = True,
            cfg = "exec",
        ),
    },
)
