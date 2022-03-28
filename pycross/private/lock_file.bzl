"""Implementation of the target_python rule."""

load(":target_environment.bzl", "TargetEnvironmentInfo")

def _pycross_lock_file_impl(ctx):
    out = ctx.outputs.out

    args = [
        "--prefix",
        ctx.attr.name.lower().replace("-", "_"),
        "--poetry-project-file",
        ctx.file.poetry_project_file.path,
        "--poetry-lock-file",
        ctx.file.poetry_lock_file.path,
        "--output",
        out.path,
    ]

    for t in ctx.files.target_environments:
        args.extend([
            "--target-environment-file",
            t.path,
        ])

    for f, u in ctx.attr.file_url_overrides.items():
        args.extend([
            "--file-url",
            "%s=%s" % (f, u)
        ])

    ctx.actions.run(
        inputs = (
            ctx.files.poetry_project_file +
            ctx.files.poetry_lock_file +
            ctx.files.target_environments
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
    )

    return [
        DefaultInfo(
            files=depset([out])
        ),
    ]


pycross_lock_file = rule(
    implementation = _pycross_lock_file_impl,
    attrs = {
        "target_environments": attr.label_list(
            doc = "A list of pycross_target_environment labels.",
            allow_files = True,
            providers = [TargetEnvironmentInfo],
        ),
        "poetry_project_file": attr.label(
            doc = "The pyproject.toml file with Poetry dependencies.",
            allow_single_file = True,
            mandatory = True,
        ),
        "poetry_lock_file": attr.label(
            doc = "The poetry.lock file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "file_url_overrides": attr.string_dict(
            doc = "An optional mapping of wheel or sdist filenames to their URLs.",
        ),
        "out": attr.output(
            doc = "The output file.",
            mandatory = True,
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:bzl_lock_generator"),
            cfg = "host",
            executable = True,
        ),
    }
)
