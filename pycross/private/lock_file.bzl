"""Implementation of the pycross_lock_file rule."""

load(":target_environment.bzl", "TargetEnvironmentInfo")

def fully_qualified_label(label):
    return "@%s//%s:%s" % (label.workspace_name, label.package, label.name)


def _pycross_lock_file_impl(ctx):
    out = ctx.outputs.out

    if ctx.attr.repo_prefix:
        repo_prefix = ctx.attr.repo_prefix
    else:
        repo_prefix = ctx.attr.name.lower().replace("-", "_")

    args = [
        "--lock-model-file",
        ctx.file.lock_model_file.path,
        "--repo-prefix",
        repo_prefix,
        "--package-prefix",
        ctx.attr.package_prefix,
        "--build-prefix",
        ctx.attr.build_prefix,
        "--environment-prefix",
        ctx.attr.environment_prefix,
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
            "--file-url-override",
            "%s=%s" % (f, u),
        ])

    for local_wheel in ctx.files.local_wheels:
        if not local_wheel.owner:
            fail("Could not determine owning lable for local wheel: %s" % local_wheel)
        args.extend([
            "--local-wheel",
            "%s=%s" % (local_wheel.basename, fully_qualified_label(local_wheel.owner)),
        ])

    for remote_wheel_url, sha256 in ctx.attr.remote_wheels.items():
        args.extend([
            "--remote-wheel",
            "%s=%s" % (remote_wheel_url, sha256),
        ])

    if ctx.attr.package_prefix != None:
        args.extend([
            "--package-prefix",
            ctx.attr.package_prefix,
        ])

    if ctx.attr.build_prefix != None:
        args.extend([
            "--build-prefix",
            ctx.attr.build_prefix,
        ])

    if ctx.attr.environment_prefix != None:
        args.extend([
            "--environment-prefix",
            ctx.attr.environment_prefix,
        ])

    if ctx.attr.default_pin_latest:
        args.append("--default-pin-latest")

    ctx.actions.run(
        inputs = (
            ctx.files.lock_model_file +
            ctx.files.target_environments
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
    )

    return [
        DefaultInfo(
            files = depset([out]),
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
        "lock_model_file": attr.label(
            doc = "The lock model JSON file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "file_url_overrides": attr.string_dict(
            doc = "An optional mapping of wheel or sdist filenames to their URLs.",
        ),
        "local_wheels": attr.label_list(
            doc = "A list of wheel files.",
            allow_files = [".whl"],
        ),
        "remote_wheels": attr.string_dict(
            doc = "A mapping of remote wheels to their sha256 hashes.",
        ),
        "repo_prefix": attr.string(
            doc = "The prefix to apply to repository targets. Defaults to the lock file target name.",
            default = "",
        ),
        "package_prefix": attr.string(
            doc = "An optional prefix to apply to package targets.",
            default = "",
        ),
        "build_prefix": attr.string(
            doc = "An optional prefix to apply to package build targets. Defaults to _build",
            default = "_build",
        ),
        "environment_prefix": attr.string(
            doc = "An optional prefix to apply to environment targets. Defaults to _env",
            default = "_env",
        ),
        "default_pin_latest": attr.bool(
            doc = "Generate aliases for the latest versions of packages not covered by the lock model's pins.",
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
    },
)
