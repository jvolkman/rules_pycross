"""Rule to define a path tool with a custom name.

This rule is intended for internal use by the pycross_wheel_build macro.
It should not be used standalone because its tool attr uses cfg="target",
relying on the parent rule's pycross_exec_platform_transition to apply
the correct exec configuration.
"""

load("//pycross/private:providers.bzl", "PycrossPathToolInfo")

def _pycross_path_tool_impl(ctx):
    # Retrieve executable from target_tool
    target_tool = ctx.attr.tool
    executable = target_tool[DefaultInfo].files_to_run.executable
    if not executable:
        # Fallback to the first file in DefaultInfo files if not executable directly
        files = target_tool[DefaultInfo].files.to_list()
        if not files:
            fail("Tool target must provide at least one file.")
        executable = files[0]

    return [
        DefaultInfo(files = target_tool[DefaultInfo].files),
        PycrossPathToolInfo(
            executable = executable,
            name = ctx.attr.executable_name,
        ),
    ]

pycross_path_tool = rule(
    doc = "Wraps an executable target with a custom PATH name. " +
          "Used internally by pycross_wheel_build; not intended for standalone use.",
    implementation = _pycross_path_tool_impl,
    attrs = {
        "tool": attr.label(
            mandatory = True,
            executable = True,
            cfg = "target",  # Transitioned by the parent rule's path_tools attr
        ),
        "executable_name": attr.string(mandatory = True),
    },
)
