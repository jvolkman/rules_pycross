"""Macro for exposing wheel console scripts as executable targets."""

load("@rules_python//python:defs.bzl", "py_binary")

def pycross_console_script_binary(name, wheel, script, deps = [], **kwargs):
    """Exposes a console script from a wheel as a py_binary target.

    Args:
        name: Name of the resulting py_binary target.
        wheel: Label of the wheel file (.whl) containing the entry_points.txt.
        script: The name of the console script to expose (e.g., "ninja").
        deps: Dependencies for the py_binary. This should include the pycross_wheel_library target for the wheel so the script's code is available.
        **kwargs: Additional arguments passed to py_binary.
    """
    script_src = name + "_script.py"

    native.genrule(
        name = name + "_gen_script",
        srcs = [wheel],
        outs = [script_src],
        cmd = "$(execpath @rules_pycross//pycross/private/tools:extract_console_script) $< %s $@" % script,
        tools = ["@rules_pycross//pycross/private/tools:extract_console_script"],
        visibility = ["//visibility:private"],
    )

    py_binary(
        name = name,
        srcs = [script_src],
        main = script_src,
        deps = deps,
        **kwargs
    )
