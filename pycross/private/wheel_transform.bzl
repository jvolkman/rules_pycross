"""Implementation of the pycross_wheel_transform rule."""

def _pycross_wheel_transform_impl(ctx):
    wheel_input = ctx.files.wheel[0]

    # Declare outputs.
    out_wheel_dir = ctx.actions.declare_directory(ctx.attr.name + ".whldir")

    # Build env vars with make variable expansion.
    env = {}
    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_make_variables("env", ctx.expand_location(value, ctx.attr.data), {})

    # Collect inputs.
    input_files = [wheel_input]
    data_inputs = [dep[DefaultInfo].files for dep in ctx.attr.data]

    # Build arguments for the wheel transformer wrapper.
    args = ctx.actions.args()
    if type(wheel_input) == "File" and wheel_input.is_directory:
        args.add("--in-wheel-dir", wheel_input.path)
    else:
        # Plain file (e.g., local override wheel) — pass its directory
        args.add("--in-wheel-dir", wheel_input.dirname)
    args.add("--out-wheel-dir", out_wheel_dir.path)
    args.add("--tool", ctx.executable.transform)

    for key, value in env.items():
        args.add("--env", "%s=%s" % (key, value))

    outputs = [out_wheel_dir]

    ctx.actions.run(
        executable = ctx.executable._wheel_transformer,
        arguments = [args],
        inputs = depset(input_files, transitive = data_inputs),
        outputs = outputs,
        tools = [ctx.attr.transform[DefaultInfo].files_to_run],
        mnemonic = "PycrossWheelTransform",
        execution_requirements = {"supports-path-mapping": "1"},
        progress_message = "Transforming %s" % wheel_input.basename,
    )

    return [DefaultInfo(files = depset([out_wheel_dir]))]

pycross_wheel_transform = rule(
    implementation = _pycross_wheel_transform_impl,
    attrs = {
        "wheel": attr.label(
            doc = "The input wheel file or TreeArtifact directory containing a .whl file.",
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
