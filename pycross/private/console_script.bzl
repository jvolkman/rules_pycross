"""Macro for exposing wheel console scripts as executable targets."""

def _pycross_console_script_binary_impl(ctx):
    wheel_file = None
    files = ctx.attr.wheel[DefaultInfo].files.to_list()
    for f in files:
        if f.basename.endswith(".whl"):
            wheel_file = f
            break
    if not wheel_file:
        wheel_file = files[0]

    out = ctx.actions.declare_file(ctx.attr.name + "_dir/" + ctx.attr.script)

    args = ctx.actions.args()
    args.add(wheel_file)
    args.add(ctx.attr.script)
    args.add(out)

    ctx.actions.run(
        executable = ctx.executable._extract_console_script,
        arguments = [args],
        inputs = [wheel_file],
        outputs = [out],
        mnemonic = "ExtractConsoleScript",
        progress_message = "Extracting console script %s" % ctx.attr.script,
    )

    return [DefaultInfo(executable = out)]

_pycross_console_script_binary = rule(
    implementation = _pycross_console_script_binary_impl,
    attrs = {
        "wheel": attr.label(
            allow_files = True,
            mandatory = True,
            doc = "Label of the wheel target.",
        ),
        "script": attr.string(
            mandatory = True,
            doc = "The name of the console script to expose.",
        ),
        "_extract_console_script": attr.label(
            default = Label("//pycross/private/tools:extract_console_script"),
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
)

def pycross_console_script_binary(name, wheel, script, **kwargs):
    """Exposes a console script from a wheel as an executable target.

    Args:
        name: Name of the resulting target.
        wheel: Label of the wheel target.
        script: The name of the console script to expose.
        **kwargs: Additional arguments like visibility or tags.
    """
    _pycross_console_script_binary(
        name = name,
        wheel = wheel,
        script = script,
        **kwargs
    )
