"""Implementation of the target_python rule."""

load(":target_environment.bzl", "TargetEnvironmentInfo")

def _pycross_lock_file_impl(ctx):
    out = ctx.outputs.out

    args = [
        "--pdm-project-file",
        ctx.file.pdm_project_file.path,
        "--pdm-lock-file",
        ctx.file.pdm_lock_file.path,
        "--output",
        out.path,
    ]

    for t in ctx.files.target_environments:
        args.extend([
            "--target-environment-file",
            t.path,
        ])

    ctx.actions.run(
        inputs = (
            ctx.files.pdm_project_file +
            ctx.files.pdm_lock_file +
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
        "pdm_project_file": attr.label(
            doc = "The pyproject.toml file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "pdm_lock_file": attr.label(
            doc = "The pdm.lock file.",
            allow_single_file = True,
            mandatory = True,
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
