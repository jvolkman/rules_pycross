"""Implementation of the pycross_lock_file rule."""

load(":lock_attrs.bzl", "RENDER_ATTRS", "RESOLVE_ATTRS", "handle_render_attrs", "handle_resolve_attrs")

def fully_qualified_label(ctx, label):
    return "@%s//%s:%s" % (label.workspace_name or ctx.workspace_name, label.package, label.name)

def _pycross_lock_file_impl(ctx):
    out = ctx.outputs.out

    args = ctx.actions.args().use_param_file("--flagfile=%s")

    args.add("--lock-model-file", ctx.file.lock_model_file)
    args.add("--output", out)

    def qualify(label):
        if ctx.attr.fully_qualified_environment_labels:
            return fully_qualified_label(ctx, label)
        else:
            return label

    def whl_name_and_label(whl_file):
        if not whl_file.owner:
            fail("Could not determine owning label for local wheel: %s" % whl_file)
        return whl_file.basename, whl_file.owner

    environment_files_and_labels = [(t.path, qualify(t.owner)) for t in ctx.files.target_environments]
    wheel_names_and_labels = [whl_name_and_label(f) for f in ctx.files.local_wheels]
    args.add_all(handle_resolve_attrs(ctx.attr, environment_files_and_labels, wheel_names_and_labels))
    args.add_all(handle_render_attrs(ctx.attr))

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
        **(RENDER_ATTRS | RESOLVE_ATTRS)
    ),
)
