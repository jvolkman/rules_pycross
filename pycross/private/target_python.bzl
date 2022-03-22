"""Implementation of the target_python rule."""


TargetPythonInfo = provider()


def _target_python_impl(ctx):
    f = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = [
        "--platform-tag",
        ctx.attr.platform_tag,
        "--output",
        f.path,
    ]

    for key, val in ctx.attr.marker_overrides.items():
        args.extend([
            "--marker-override",
            "%s=%s" % (key, val),
        ])

    ctx.actions.run(
        outputs = [f],
        executable = ctx.executable._tool,
        arguments = args,
    )

    return [
        TargetPythonInfo(
            platform=ctx.attr.platform,
            output=f,
        ),
        DefaultInfo(
            files=depset([f])
        ),
    ]


target_python = rule(
    implementation = _target_python_impl,
    attrs = {
        "platform": attr.label(
            doc = (
                "A constraint that, when satisfied, indicates this " +
                "target_platform should be selected."
            ),
            mandatory = True,
        ),
        "platform_tag": attr.string(
            doc = "A PEP 425 tag representing this platform.",
            mandatory = True,
        ),
        "marker_overrides": attr.string_dict(
            doc = "Environment marker overrides.",
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:target_python"),
            cfg = "host",
            executable = True,
        ),
    }
)
