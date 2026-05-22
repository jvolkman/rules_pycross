"""Pycross internal deps."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@toml.bzl//toml:toml.bzl", "decode")
load("//pycross/private:internal_repo.bzl", "create_internal_repo")
load(":tag_attrs.bzl", "CREATE_ENVIRONMENTS_ATTRS", "REGISTER_TOOLCHAINS_ATTRS")

_CORE_PACKAGES = ["dacite", "installer", "packaging", "pip", "poetry-core"]

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

    if interpreter_tag.python_interpreter_target:
        python_interpreter_target = interpreter_tag.python_interpreter_target

    if interpreter_tag.python_defs_file:
        python_defs_file = interpreter_tag.python_defs_file

    if not python_interpreter_target or not python_defs_file:
        fail(
            "Both python_interpreter_target and python_defs_file must be set",
        )

    # 1. Read and parse the TOML lock
    deps_toml_path = module_ctx.path(Label("//pycross/private:pycross_deps.toml"))
    deps_data = decode(module_ctx.read(deps_toml_path))

    # 2. Instantiate http_file repos for all packages dynamically
    for pkg in deps_data["packages"].values():
        http_file(
            name = pkg["repo_name"],
            urls = [pkg["url"]],
            sha256 = pkg["sha256"],
            downloaded_file_path = pkg["filename"],
        )

    # 3. Construct core_files map dynamically for rules_pycross_internal
    core_files = {}
    for pkg in deps_data["packages"].values():
        if pkg["name"] in _CORE_PACKAGES:
            core_files[pkg["filename"]] = pkg["repo_name"]

    environments_attrs = {
        k: getattr(environments_tag, k)
        for k in CREATE_ENVIRONMENTS_ATTRS.keys()
    }
    toolchains_attrs = {
        k: getattr(toolchains_tag, k)
        for k in REGISTER_TOOLCHAINS_ATTRS.keys()
    }

    create_internal_repo(
        python_interpreter_target = python_interpreter_target,
        python_defs_file = python_defs_file,
        wheels = core_files,
        **(environments_attrs | toolchains_attrs)
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

pycross = module_extension(
    doc = "Configure rules_pycross.",
    implementation = _pycross_impl,
    tag_classes = {
        "configure_environments": tag_class(
            attrs = CREATE_ENVIRONMENTS_ATTRS,
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
            attrs = REGISTER_TOOLCHAINS_ATTRS,
        ),
    },
)
