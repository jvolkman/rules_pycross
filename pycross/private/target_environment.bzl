"""Implementation of the pycross_target_environment rule."""

load("//pycross:providers.bzl", "PycrossTargetEnvironmentInfo")

def fully_qualified_label(label):
    return "@%s//%s:%s" % (label.workspace_name, label.package, label.name)


def _target_python_impl(ctx):
    f = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = [
        "--name",
        ctx.attr.name,
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

    for constraint in ctx.attr.python_compatible_with:
        args.extend([
            "--python-compatible-with",
            fully_qualified_label(constraint.label),
        ])

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
        PycrossTargetEnvironmentInfo(
            python_compatible_with=ctx.attr.python_compatible_with,
            file=f,
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
        "python_compatible_with": attr.label_list(
            doc = (
                "A list of constraints that, when satisfied, indicates this " +
                "target_platform should be selected."
            ),
            mandatory = True,
            allow_empty = False,
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

def _macos_target_python_impl(ctx):
    f = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = [
        "--name",
        ctx.attr.name,
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

    for constraint in ctx.attr.python_compatible_with:
        args.extend([
            "--python-compatible-with",
            fully_qualified_label(constraint.label),
        ])

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
        PycrossTargetEnvironmentInfo(
            python_compatible_with=ctx.attr.python_compatible_with,
            file=f,
        ),
        DefaultInfo(
            files=depset([f])
        ),
    ]


pycross_macos_environment = rule(
    implementation = _macos_target_python_impl,
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
        "python_compatible_with": attr.label_list(
            doc = (
                "A list of constraints that, when satisfied, indicates this " +
                "target_platform should be selected."
            ),
            mandatory = True,
            allow_empty = False,
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
