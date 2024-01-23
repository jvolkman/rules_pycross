"""Pycross internal deps."""

load("@pythons_hub//:interpreters.bzl", "INTERPRETER_LABELS")
load("//pycross/private:internal_repo.bzl", "create_internal_repo")
load("//pycross/private:pycross_deps.lock.bzl", pypi_all_repositories = "repositories")
load("//pycross/private:pycross_deps_core.lock.bzl", core_files = "FILES")
load(":tag_attrs.bzl", "CREATE_ENVIRONMENTS_ATTRS", "REGISTER_TOOLCHAINS_ATTRS")

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _pycross_impl(module_ctx):
    environments_tag = None
    interpreter_tag = None
    toolchains_tag = None

    for module in module_ctx.modules:
        if module.name != "rules_pycross" and not module.is_root:
            _print_warn("Ignoring `pycross` extension usage from non-root, non-rules_pycross module {}".format(module.name))
            continue

        if not environments_tag:
            for tag in module.tags.configure_environments:
                environments_tag = tag
                break

        if not interpreter_tag:
            for tag in module.tags.configure_interpreter:
                interpreter_tag = tag
                break

        if not toolchains_tag:
            for tag in module.tags.configure_toolchains:
                toolchains_tag = tag
                break

    python_interpreter_target = None
    python_defs_file = None

    requested_version = interpreter_tag.registered_python_version
    if requested_version:
        repo_name = "python_{}".format(requested_version.replace(".", "_"))
        if repo_name not in INTERPRETER_LABELS:
            fail("Python version {} has not been registered".format(requested_version))
        python_interpreter_target = INTERPRETER_LABELS[repo_name]
        python_defs_file = Label("@python_versions//{}:defs.bzl".format(requested_version))

    if interpreter_tag.python_interpreter_target:
        python_interpreter_target = interpreter_tag.python_interpreter_target

    if interpreter_tag.python_defs_file:
        python_defs_file = interpreter_tag.python_defs_file

    if not python_interpreter_target or not python_defs_file:
        fail(
            "Both python_interpreter_target and python_defs_file must be set - " +
            "either explicitly, or via registered_python_version",
        )

    pypi_all_repositories()

    environments_attrs = {k: getattr(environments_tag, k) for k in dir(environments_tag)}
    toolchains_attrs = {k: getattr(toolchains_tag, k) for k in dir(toolchains_tag)}

    create_internal_repo(
        python_interpreter_target = python_interpreter_target,
        python_defs_file = python_defs_file,
        wheels = core_files,
        **(environments_attrs | toolchains_attrs)
    )

pycross = module_extension(
    doc = "Configure rules_pycross.",
    implementation = _pycross_impl,
    # OS and arch dependent since we load from @pythons_hub//:interpreters.bzl.
    os_dependent = True,
    arch_dependent = True,
    tag_classes = {
        "configure_environments": tag_class(
            attrs = CREATE_ENVIRONMENTS_ATTRS,
        ),
        "configure_interpreter": tag_class(
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
        "configure_toolchains": tag_class(
            attrs = REGISTER_TOOLCHAINS_ATTRS,
        ),
    },
)
