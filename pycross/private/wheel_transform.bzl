"""Implementation of the pycross_wheel_transform rule."""

load(":providers.bzl", "PycrossWheelInfo")

def _pycross_wheel_transform_impl(ctx):
    # Resolve input wheel file and name file from PycrossWheelInfo or dynamically from files
    input_wheelhouse = None
    if PycrossWheelInfo in ctx.attr.wheel:
        wheel_info = ctx.attr.wheel[PycrossWheelInfo]
        input_wheelhouse = wheel_info.wheelhouse
    else:
        # Assuming the fallback is the wheelhouse filegroup
        input_wheelhouse = ctx.files.wheel[0]

    # Declare outputs.
    out_wheelhouse = ctx.actions.declare_directory(ctx.attr.name + "_wheelhouse")

    # Build env vars with make variable expansion.
    env = {}
    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_make_variables("env", ctx.expand_location(value, ctx.attr.data), {})

    # Collect inputs.
    input_files = [input_wheelhouse]
    data_inputs = [dep[DefaultInfo].files for dep in ctx.attr.data]

    # Build arguments for the wheel transformer wrapper.
    args = ctx.actions.args()
    args.add("--wheelhouse", input_wheelhouse.path)
    args.add("--output-dir", out_wheelhouse.path)
    args.add("--tool", ctx.executable.transform)

    for key, value in env.items():
        args.add("--env", "%s=%s" % (key, value))

    outputs = [out_wheelhouse]

    ctx.actions.run(
        executable = ctx.executable._wheel_transformer,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        tools = [ctx.attr.transform[DefaultInfo].files_to_run],
        mnemonic = "WheelTransform",
        progress_message = "Transforming %s" % input_wheelhouse.basename,
    )

    return [
        PycrossWheelInfo(
            wheelhouse = out_wheelhouse,
        ),
        DefaultInfo(
            files = depset([out_wheelhouse]),
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
