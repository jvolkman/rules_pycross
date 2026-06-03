"""Pycross internal deps."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@toml.bzl//toml:toml.bzl", "decode")
load("//pycross/private:internal_repo.bzl", "create_internal_repo")
load(":backend_registry_repo.bzl", "backend_registry_repo")
load(":tag_attrs.bzl", "CREATE_ENVIRONMENTS_ATTRS", "REGISTER_TOOLCHAINS_ATTRS")

_CORE_PACKAGES = ["dacite", "installer", "packaging", "pip", "poetry-core"]

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _pycross_impl(module_ctx):
    environments_tag = None
    interpreter_tag = None
    toolchains_tag = None

    # Collect backend registrations across all modules.
    # Root module wins for duplicate pyproject_backends entries and default.
    backend_to_rule = {}  # pyproject backend name -> rule name
    backend_configs = {}  # rule name -> JSON config string
    default_backend = None
    default_backend_module = None

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

        for tag in module.tags.register_backend:
            name = tag.name

            # Duplicate rule name: root module wins, otherwise first-registered wins.
            if name in backend_configs:
                if module.is_root:
                    # Root module overrides.
                    pass
                else:
                    _print_warn("Ignoring duplicate backend registration '{}' from module '{}'".format(name, module.name))
                    continue

            config = {
                "rule_bzl": tag.rule_bzl,
                "tool_packages": tag.tool_packages,
            }
            backend_configs[name] = json.encode(config)

            for pyproject_backend in tag.pyproject_backends:
                if pyproject_backend in backend_to_rule and not module.is_root:
                    _print_warn(
                        "Ignoring duplicate pyproject backend '{}' -> '{}' from module '{}' (already mapped to '{}')".format(
                            pyproject_backend,
                            name,
                            module.name,
                            backend_to_rule[pyproject_backend],
                        ),
                    )
                else:
                    backend_to_rule[pyproject_backend] = name

            if tag.default:
                if default_backend and not module.is_root:
                    _print_warn(
                        "Ignoring default backend '{}' from module '{}' (already set to '{}' by module '{}')".format(
                            name,
                            module.name,
                            default_backend,
                            default_backend_module,
                        ),
                    )
                else:
                    default_backend = name
                    default_backend_module = module.name

    if not default_backend:
        fail("No default build backend registered. Set `default = True` on one `register_backend` tag.")

    # Create the backend registry repo.
    backend_registry_repo(
        name = "pycross_backends",
        backend_to_rule = backend_to_rule,
        default_backend = default_backend,
        backend_configs = backend_configs,
    )

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
        "register_backend": tag_class(
            doc = "Register a build backend for pycross sdist builds.",
            attrs = {
                "name": attr.string(
                    mandatory = True,
                    doc = "Pycross rule name (e.g. 'meson_build').",
                ),
                "rule_bzl": attr.string(
                    mandatory = True,
                    doc = "Label of the .bzl file containing the rule, e.g. " +
                          "'@rules_pycross//pycross/private/build/rules:meson_build.bzl'.",
                ),
                "pyproject_backends": attr.string_list(
                    doc = "pyproject.toml build-system.build-backend values that map " +
                          "to this backend (e.g. ['mesonpy', 'mesonbuild']).",
                ),
                "tool_packages": attr.string_list(
                    doc = "PEP 503 normalized PyPI package names of tools this backend " +
                          "needs at build time (e.g. ['meson', 'ninja', 'meson-python']).",
                ),
                "default": attr.bool(
                    doc = "If True, this backend is used when no pyproject_backends entry " +
                          "matches. Only one backend may be the default. Root module wins " +
                          "if multiple are set.",
                ),
            },
        ),
    },
)
