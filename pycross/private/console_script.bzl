"""Macro for exposing wheel console scripts as executable targets."""

load("@rules_python//python:defs.bzl", "py_binary")
load(
    ":providers.bzl",
    "PycrossExtractedWheelInfo",
)

def _pycross_console_script_extractor_impl(ctx):
    if not ctx.attr.pkg:
        fail("Must specify pkg")

    if PycrossExtractedWheelInfo in ctx.attr.pkg:
        site_packages = ctx.attr.pkg[PycrossExtractedWheelInfo].site_packages
    else:
        fail("pkg must provide PycrossExtractedWheelInfo")

    out = ctx.actions.declare_file(ctx.attr.out)

    args = ctx.actions.args()
    args.add("--site-packages", site_packages.path)
    args.add("--script", ctx.attr.script)
    args.add("--out", out)

    ctx.actions.run(
        executable = ctx.executable._extract_console_script,
        arguments = [args],
        inputs = [site_packages],
        outputs = [out],
        mnemonic = "ExtractConsoleScript",
        progress_message = "Extracting console script %s" % ctx.attr.script,
    )

    return [DefaultInfo(files = depset([out]))]

_pycross_console_script_extractor = rule(
    implementation = _pycross_console_script_extractor_impl,
    attrs = {
        "pkg": attr.label(
            doc = "Label of the wheel library target.",
            mandatory = True,
            providers = [PycrossExtractedWheelInfo],
        ),
        "script": attr.string(
            mandatory = True,
            doc = "The name of the console script to expose.",
        ),
        "out": attr.string(
            mandatory = True,
            doc = "The output script filename.",
        ),
        "_extract_console_script": attr.label(
            default = Label("//pycross/private/tools:extract_console_script"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def pycross_console_script_binary(name, script, pkg, deps = None, **kwargs):
    """Exposes a console script from a wheel as an executable target.

    Args:
        name: Name of the resulting target.
        script: The name of the console script to expose.
        pkg: Label of the wheel library target.
        deps: Additional dependencies to pass to the binary.
        **kwargs: Additional arguments like visibility or tags.
    """
    script_target_name = name + "_script"
    script_file_name = name + ".py"

    _pycross_console_script_extractor(
        name = script_target_name,
        pkg = pkg,
        script = script,
        out = script_file_name,
        tags = ["manual"],
    )

    py_binary(
        name = name,
        srcs = [script_target_name],
        main = script_file_name,
        deps = (deps or []) + [pkg],
        **kwargs
    )
