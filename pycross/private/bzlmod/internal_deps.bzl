load("@pythons_hub//:interpreters.bzl", "INTERPRETER_LABELS")
load("//pycross/private:internal_repo.bzl", "create_internal_repo")
load("//pycross/private:pycross_deps.lock.bzl", pypi_all_repositories = "repositories")
load("//pycross/private:pycross_deps_core.lock.bzl", core_files = "FILES")

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _internal_deps_impl(module_ctx):
    install_tag_to_use = None
    for module in module_ctx.modules:
        if module.name != "rules_pycross" and not module.is_root:
            _print_warn("Ignoring install tag from non-root, non-pycross module {}".format(module.name))
            continue
        for install_tag in module.tags.install:
            install_tag_to_use = install_tag
            break

        if install_tag_to_use:
            # Use the first tag. Root comes first in modules iteration order, so root can override.
            break

    if not install_tag_to_use:
        # This shouldn't happen since we register our own default tag.
        fail("No install tag found")

    python_interpreter_target = None
    python_defs_file = None

    requested_version = install_tag_to_use.registered_python_version
    if requested_version:
        repo_name = "python_{}".format(requested_version.replace(".", "_"))
        if repo_name not in INTERPRETER_LABELS:
            fail("Python version {} has not been registered".format(requested_version))
        python_interpreter_target = INTERPRETER_LABELS[repo_name]
        python_defs_file = Label("@python_versions//{}:defs.bzl".format(requested_version))

    if install_tag_to_use.python_interpreter_target:
        python_interpreter_target = install_tag_to_use.python_interpreter_target

    if install_tag_to_use.python_defs_file:
        python_defs_file = install_tag_to_use.python_defs_file

    if not python_interpreter_target or not python_defs_file:
        fail(
            "Both python_interpreter_target and python_defs_file must be set - " +
            "either explicitly, or via registered_python_version",
        )

    pypi_all_repositories()
    create_internal_repo(
        python_interpreter_target = python_interpreter_target,
        python_defs_file = python_defs_file,
        wheels = core_files,
    )

internal_deps = module_extension(
    doc = "Register internal rules_pycross dependecies.",
    implementation = _internal_deps_impl,
    tag_classes = {
        "install": tag_class(
            attrs = {
                "registered_python_version": attr.string(
                    doc = "The version of a rules_python-registered interpreter to use.",
                ),
                "python_interpreter_target": attr.label(
                    doc = "The label to a python executable to use for invoking internal tools.",
                ),
                "python_defs_file": attr.label(
                    doc = "A label to a .bzl file that provides py_binary and py_test.",
                ),
            },
        ),
    },
)
