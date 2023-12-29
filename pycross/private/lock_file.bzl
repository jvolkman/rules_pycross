"""Implementation of the pycross_lock_file rule."""

load(":lock_attrs.bzl", "COMMON_ATTRS", "handle_common_attrs")

def fully_qualified_label(ctx, label):
    return "@%s//%s:%s" % (label.workspace_name or ctx.workspace_name, label.package, label.name)

def _pycross_lock_file_impl(ctx):
    out = ctx.outputs.out

    args = ctx.actions.args().use_param_file("--flagfile=%s")

    args.add("--lock-model-file", ctx.file.lock_model_file)
    args.add("--output", out)

    for local_wheel in ctx.files.local_wheels:
        if not local_wheel.owner:
            fail("Could not determine owning label for local wheel: %s" % local_wheel)
        args.add_all("--local-wheel", [local_wheel.basename, local_wheel.owner])

    def qualify(label):
        if ctx.attr.fully_qualified_environment_labels:
            return fully_qualified_label(ctx, label)
        else:
            return label

    environment_files_and_labels = [(t.path, qualify(t.owner)) for t in ctx.files.target_environments]
    args.add_all(handle_common_attrs(ctx.attr, environment_files_and_labels))

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
    attrs = dict(
        lock_model_file = attr.label(
            doc = "The lock model JSON file.",
            allow_single_file = [".json"],
            mandatory = True,
        ),
        local_wheels = attr.label_list(
            doc = "A list of wheel files.",
            allow_files = [".whl"],
        ),
        fully_qualified_environment_labels = attr.bool(
            doc = "Generate fully-qualified environment labels.",
            default = True,
        ),
        out = attr.output(
            doc = "The output file.",
            mandatory = True,
        ),
        _tool = attr.label(
            default = Label("//pycross/private/tools:bzl_lock_generator"),
            cfg = "exec",
            executable = True,
        ),
        **COMMON_ATTRS
    ),
)
