"""Implementation of the pycross_target_environment rule."""


TargetEnvironmentInfo = provider()


def _target_python_impl(ctx):
    f = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = [
        "--output",
        f.path,
        "--implementation",
        ctx.attr.implementation,
        "--version",
        ctx.attr.version,
    ]

    for abi in ctx.attr.abis:
        args.extend(["--abi", abi])

    for platform in ctx.attr.platforms:
        args.extend(["--platform", platform])

    for key, val in ctx.attr.envornment_markers.items():
        args.extend([
            "--environment-marker",
            "%s=%s" % (key, val),
        ])

    ctx.actions.run(
        outputs = [f],
        executable = ctx.executable._tool,
        arguments = args,
    )

    return [
        TargetEnvironmentInfo(
            python_compatible_with=ctx.attr.python_compatible_with,
            output=f,
        ),
        DefaultInfo(
            files=depset([f])
        ),
    ]


pycross_target_environment = rule(
    implementation = _target_python_impl,
    attrs = {
        "implementation": attr.string(
            doc = (
                "The PEP 425 implementation abbreviation " +
                "(defaults to 'cp' for CPython)."
            ),
            mandatory = False,
            default = "cp",
        ),
        "version": attr.string(
            doc = "The python version.",
            mandatory = True,
        ),
        "abis": attr.string_list(
            doc = "A list of PEP 425 abi tags.",
            mandatory = False,
            default = [],
        ),
        "platforms": attr.string_list(
            doc = "A list of PEP 425 platform tags.",
            mandatory = False,
            default = [],
        ),
        "python_compatible_with": attr.label(
            doc = (
                "A constraint that, when satisfied, indicates this " +
                "target_platform should be selected."
            ),
            mandatory = True,
        ),
        "envornment_markers": attr.string_dict(
            doc = "Environment marker overrides.",
            mandatory = False,
            default = {},
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:target_environment_generator"),
            cfg = "host",
            executable = True,
        ),
    }
)
