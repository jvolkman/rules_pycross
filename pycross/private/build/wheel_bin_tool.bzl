"""Rule for extracting a binary from an installed wheel library as an executable target."""

def _pycross_wheel_bin_tool_impl(ctx):
    wheel_dir = ctx.files.wheel[0]
    binary_name = ctx.attr.binary_name
    out_file = ctx.actions.declare_file(binary_name)

    # Copy the pre-compiled binary from bin/ inside the installed site-packages directory
    ctx.actions.run_shell(
        inputs = [wheel_dir],
        outputs = [out_file],
        command = "cp \"$1/bin/$2\" \"$3\"",
        arguments = [wheel_dir.path, binary_name, out_file.path],
        mnemonic = "ExtractWheelBin",
        progress_message = "Extracting binary %s from wheel %s" % (binary_name, ctx.attr.wheel.label.name),
    )

    return [
        DefaultInfo(
            files = depset([out_file]),
            executable = out_file,
        ),
    ]

pycross_wheel_bin_tool = rule(
    implementation = _pycross_wheel_bin_tool_impl,
    attrs = {
        "wheel": attr.label(
            mandatory = True,
            providers = [DefaultInfo],
            doc = "The pycross_wheel_library target containing the installed wheel.",
        ),
        "binary_name": attr.string(
            mandatory = True,
            doc = "The name of the binary inside the wheel's bin/ directory.",
        ),
    },
    executable = True,
)
