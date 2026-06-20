"""Rule to expose dist-info files from a pycross_wheel_library target.

This enables compatibility with rules_python's py_console_script_binary,
which expects a :dist_info target providing entry_points.txt as a file.
"""

def _pycross_dist_info_impl(ctx):
    return [DefaultInfo(
        files = ctx.attr.pkg[OutputGroupInfo].dist_info,
    )]

pycross_dist_info = rule(
    implementation = _pycross_dist_info_impl,
    doc = """Exposes the dist-info files (entry_points.txt) from a pycross_wheel_library target.

    This rule forwards the dist_info output group from a pycross_wheel_library
    target as DefaultInfo, making it compatible with rules_python's
    py_console_script_binary which expects a :dist_info filegroup.
    """,
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            doc = "A pycross_wheel_library target.",
        ),
    },
)
