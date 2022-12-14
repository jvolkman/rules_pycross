"""Implementation of the pycross_lock_file rule."""

load(":providers.bzl", "PycrossTargetEnvironmentInfo")

def fully_qualified_label(label):
    return "@%s//%s:%s" % (label.workspace_name, label.package, label.name)


def _pycross_lock_file_impl(ctx):
    out = ctx.outputs.out

    if ctx.attr.repo_prefix:
        repo_prefix = ctx.attr.repo_prefix
    else:
        repo_prefix = ctx.attr.name.lower().replace("-", "_")

    args = ctx.actions.args().use_param_file("--flagfile=%s")

    args.add("--lock-model-file", ctx.file.lock_model_file)
    args.add("--repo-prefix", repo_prefix)
    args.add("--output", out)

    for t in ctx.attr.target_environments:
        args.add_all("--target-environment", [t[PycrossTargetEnvironmentInfo].file.path, fully_qualified_label(t.label)])

    for local_wheel in ctx.files.local_wheels:
        if not local_wheel.owner:
            fail("Could not determine owning lable for local wheel: %s" % local_wheel)
        args.add_all("--local-wheel", [local_wheel.basename, fully_qualified_label(local_wheel.owner)])

    for remote_wheel_url, sha256 in ctx.attr.remote_wheels.items():
        args.add_all("--remote-wheel", [remote_wheel_url, sha256])

    if ctx.attr.package_prefix:
        args.add("--package-prefix", ctx.attr.package_prefix)

    if ctx.attr.build_prefix:
        args.add("--build-prefix", ctx.attr.build_prefix)

    if ctx.attr.environment_prefix:
        args.add("--environment-prefix", ctx.attr.environment_prefix)

    if ctx.attr.default_alias_single_version:
        args.add("--default-alias-single-version")

    for k, t in ctx.attr.build_target_overrides.items():
        args.add_all("--build-target-override", [k, t])

    for k in ctx.attr.always_build_packages:
        args.add("--always-build-package", k)

    for k, d in ctx.attr.package_build_dependencies.items():
        for dep in d:
            args.add_all("--build-dependency", [k, dep])

    if ctx.attr.pypi_index:
        args.add("--pypi-index", ctx.attr.pypi_index)

    ctx.actions.run(
        inputs = (
            ctx.files.lock_model_file +
            ctx.files.target_environments
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = [args],
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
            providers = [PycrossTargetEnvironmentInfo],
        ),
        "lock_model_file": attr.label(
            doc = "The lock model JSON file.",
            allow_single_file = True,
            mandatory = True,
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
        "default_alias_single_version": attr.bool(
            doc = "Generate aliases for all packages that have a single version in the lock file.",
        ),
        "build_target_overrides": attr.string_dict(
            doc = "A mapping of package keys (name or name@version) to existing pycross_wheel_build build targets.",
        ),
        "always_build_packages": attr.string_list(
            doc = "A list of package keys (name or name@version) to always build from source.",
        ),
        "package_build_dependencies": attr.string_list_dict(
            doc = "A dict of package keys (name or name@version) to a list of that packages build dependency keys."
        ),
        "pypi_index": attr.string(
            doc = "The PyPI-compatible index to use (must support the JSON API).",
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
