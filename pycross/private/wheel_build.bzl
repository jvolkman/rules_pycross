"""Implementation of the pycross_wheel_build rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python//python:defs.bzl", "PyInfo")

def _pycross_wheel_build_impl(ctx):
    out = ctx.actions.declare_file(paths.join(ctx.attr.name, "wheel.whl"))

    args = [
        "--sdist",
        ctx.file.sdist.path,
        "--wheel",
        out.path,
    ]

    imports = depset(
        transitive = [d[PyInfo].imports for d in ctx.attr.deps],
    )

    for import_name in imports.to_list():
        # The build action doesn't run in a runfiles path, so the import names aren't correct.
        # Local-repo imports show up in ctx.bin_dir, whereas external imports show up in external/.

        import_name_parts = import_name.split("/", 1)
        if import_name_parts[0] == ctx.workspace_name:
            # Local package; will be in ctx.bin_dir
            args.extend([
                "--path",
                paths.join(ctx.bin_dir.path, import_name_parts[1])
            ])
        else:
            # External package; will be in "external".
            args.extend([
                "--path",
                paths.join("external", import_name)
            ])

    ctx.actions.run(
        inputs = [ctx.file.sdist] + ctx.files.deps,
        outputs = [out],
        executable = ctx.executable._tool,
        arguments = args,
        mnemonic = "WheelBuild",
        progress_message = "Building %s" % ctx.file.sdist.basename,
    )

    return [
        DefaultInfo(
            files = depset(direct = [out]),
        ),
    ]

pycross_wheel_build = rule(
    implementation = _pycross_wheel_build_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "A list of build dependencies for the wheel.",
            providers = [DefaultInfo, PyInfo],
        ),
        "sdist": attr.label(
            doc = "The sdist file.",
            allow_single_file = [".tar.gz"],
            mandatory = True,
        ),
        "_tool": attr.label(
            default = Label("//pycross/private/tools:wheel_builder"),
            cfg = "host",
            executable = True,
        ),
    }
)
