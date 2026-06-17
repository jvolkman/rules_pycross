"""Test rules for lock models."""

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_attrs.bzl", "PDM_IMPORT_ATTRS", "POETRY_IMPORT_ATTRS", "PYLOCK_IMPORT_ATTRS", "UV_IMPORT_ATTRS")

# buildifier: disable=bzl-visibility
load("//pycross/private:pdm_lock_model.bzl", handle_pdm_args = "handle_args")

# buildifier: disable=bzl-visibility
load("//pycross/private:poetry_lock_model.bzl", handle_poetry_args = "handle_args")

# buildifier: disable=bzl-visibility
load("//pycross/private:pylock_lock_model.bzl", handle_pylock_args = "handle_args")

# buildifier: disable=bzl-visibility
load("//pycross/private:uv_lock_model.bzl", handle_uv_args = "handle_args")

def _pycross_pdm_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add_all(
        handle_pdm_args(
            ctx.attr,
            ctx.file.project_file.path,
            ctx.file.lock_file.path,
            out.path,
        ),
    )

    ctx.actions.run(
        inputs = (
            ctx.files.project_file +
            ctx.files.lock_file
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        mnemonic = "PycrossPdmTranslate",
        execution_requirements = {"supports-path-mapping": "1"},
        arguments = [args],
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
    ]

pycross_pdm_lock_model = rule(
    implementation = _pycross_pdm_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:pdm_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | PDM_IMPORT_ATTRS,
)

def _pycross_poetry_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add_all(
        handle_poetry_args(
            ctx.attr,
            ctx.file.project_file.path,
            ctx.file.lock_file.path,
            out.path,
        ),
    )

    ctx.actions.run(
        inputs = (
            ctx.files.project_file +
            ctx.files.lock_file
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        mnemonic = "PycrossPoetryTranslate",
        execution_requirements = {"supports-path-mapping": "1"},
        arguments = [args],
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
    ]

pycross_poetry_lock_model = rule(
    implementation = _pycross_poetry_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:poetry_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | POETRY_IMPORT_ATTRS,
)

def _pycross_pylock_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")

    project_file_path = ctx.file.project_file.path if getattr(ctx.file, "project_file", None) else None
    args.add_all(
        handle_pylock_args(
            ctx.attr,
            project_file_path,
            ctx.file.lock_file.path,
            out.path,
        ),
    )

    inputs = []
    if getattr(ctx.file, "project_file", None):
        inputs.append(ctx.file.project_file)
    inputs.append(ctx.file.lock_file)

    ctx.actions.run(
        inputs = inputs,
        outputs = [out],
        executable = ctx.executable._tool,
        mnemonic = "PycrossPylockTranslate",
        execution_requirements = {"supports-path-mapping": "1"},
        arguments = [args],
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
    ]

pycross_pylock_lock_model = rule(
    implementation = _pycross_pylock_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:pylock_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | PYLOCK_IMPORT_ATTRS,
)

def _pycross_uv_lock_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".json")

    args = ctx.actions.args().use_param_file("--flagfile=%s")
    args.add_all(
        handle_uv_args(
            ctx.attr,
            ctx.file.project_file.path,
            ctx.file.lock_file.path,
            out.path,
        ),
    )

    ctx.actions.run(
        inputs = (
            ctx.files.project_file +
            ctx.files.lock_file
        ),
        outputs = [out],
        executable = ctx.executable._tool,
        mnemonic = "PycrossUvTranslate",
        execution_requirements = {"supports-path-mapping": "1"},
        arguments = [args],
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
    ]

pycross_uv_lock_model = rule(
    implementation = _pycross_uv_lock_model_impl,
    attrs = {
        "_tool": attr.label(
            default = Label("//pycross/private/tools:uv_translator"),
            cfg = "exec",
            executable = True,
        ),
    } | UV_IMPORT_ATTRS,
)
