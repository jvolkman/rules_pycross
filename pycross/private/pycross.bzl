"""Pycross internal deps."""

load("@bazel_features//:features.bzl", "bazel_features")
load("//pycross/private:deps_toml_repo.bzl", "pycross_deps_toml_repo")
load("//pycross/private:internal_repo.bzl", "create_internal_repo")
load(":lock_attrs.bzl", "CONFIGURE_TOOLCHAINS_ATTRS")

def _pycross_impl(module_ctx):
    interpreter_tag = None
    toolchains_tag = None

    for module in module_ctx.modules:
        if module.name != "rules_pycross" and not module.is_root:
            continue

        if not interpreter_tag:
            for tag in module.tags.configure_interpreter:
                interpreter_tag = tag
                break

        if not toolchains_tag:
            for tag in module.tags.configure_toolchains:
                toolchains_tag = tag
                break

        # Deprecated alias: configure_environments -> configure_toolchains
        if not toolchains_tag:
            for tag in module.tags.configure_environments:
                # buildifier: disable=print
                print("WARNING: pycross.configure_environments() is deprecated. Use pycross.configure_toolchains() instead.")
                toolchains_tag = tag
                break

    python_interpreter_target = None
    python_defs_file = None

    if interpreter_tag.python_interpreter_target:
        python_interpreter_target = interpreter_tag.python_interpreter_target

    if interpreter_tag.python_defs_file:
        python_defs_file = interpreter_tag.python_defs_file

    if not python_interpreter_target or not python_defs_file:
        fail(
            "Both python_interpreter_target and python_defs_file must be set",
        )

    toolchains_attrs = {
        k: getattr(toolchains_tag, k)
        for k in CONFIGURE_TOOLCHAINS_ATTRS.keys()
    }

    create_internal_repo(
        toolchains_attrs = toolchains_attrs,
        python_interpreter_target = python_interpreter_target,
        python_defs_file = python_defs_file,
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

pycross = module_extension(
    doc = "Configure rules_pycross.",
    implementation = _pycross_impl,
    tag_classes = {
        "configure_environments": tag_class(
            doc = "Deprecated: use configure_toolchains instead.",
            attrs = CONFIGURE_TOOLCHAINS_ATTRS,
        ),
        "configure_interpreter": tag_class(
            attrs = {
                "python_interpreter_target": attr.label(
                    doc = "The label to a python executable to use for invoking internal tools.",
                ),
                "python_defs_file": attr.label(
                    doc = "A label to a .bzl file that provides py_binary and py_test.",
                ),
            },
        ),
        "configure_toolchains": tag_class(
            attrs = CONFIGURE_TOOLCHAINS_ATTRS,
        ),
    },
)

def _pycross_dev_impl(module_ctx):
    pycross_deps_toml_repo(
        name = "rules_pycross_deps",
        project_file = Label("//:pyproject.toml"),
        lock_file = Label("//:uv.lock"),
    )
    return module_ctx.extension_metadata(reproducible = True)

pycross_dev = module_extension(
    doc = "Development-only extension for rules_pycross.",
    implementation = _pycross_dev_impl,
)
