"""Rule to wrap an executable with a custom PATH name.

Use this to place a binary target on PATH during pycross builds
under a different name than its default basename. For example,
to make a ``cmake3`` binary available as ``cmake``:

.. code-block:: python

    pycross_path_tool(
        name = "cmake_tool",
        tool = "//tools:cmake3",
        executable_name = "cmake",
    )

Then pass it in the build rule's ``path_tools``:

.. code-block:: python

    setuptools_build(
        ...
        path_tools = [":cmake_tool"],
    )

Without a wrapper, a plain label in ``path_tools`` uses the
executable's basename automatically.
"""

load("//pycross/private:providers.bzl", "PycrossPathToolInfo")

def _pycross_path_tool_impl(ctx):
    target_tool = ctx.attr.tool
    di = target_tool[DefaultInfo]
    executable = di.files_to_run.executable
    if not executable:
        files = di.files.to_list()
        if not files:
            fail("Tool target must provide at least one file.")
        executable = files[0]

    return [
        DefaultInfo(
            files = di.files,
            runfiles = di.default_runfiles,
        ),
        PycrossPathToolInfo(
            executable = executable,
            name = ctx.attr.executable_name,
        ),
    ]

pycross_path_tool = rule(
    doc = "Wraps an executable target with a custom PATH name for use in pycross build rules.",
    implementation = _pycross_path_tool_impl,
    attrs = {
        "tool": attr.label(
            doc = "The executable target to wrap.",
            mandatory = True,
            executable = True,
            cfg = "target",
        ),
        "executable_name": attr.string(
            doc = "The name this tool should have on PATH during builds.",
            mandatory = True,
        ),
    },
)
