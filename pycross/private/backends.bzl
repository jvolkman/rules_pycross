"""Build backend registration extension.

Any module can register build backends (e.g. maturin, meson) by calling
`backends.register()` in its MODULE.bazel.  The extension collects all
registrations and creates the `@pycross_backends` repository with the
generated registry and sdist dispatch tables.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load(":backend_registry_repo.bzl", "backend_registry_repo")

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _collect_registrations(modules, warn = _print_warn):
    """Merge `register` tags from all modules (root module first) into one registry."""
    backend_to_rule = {}  # pyproject backend name -> rule name
    backend_configs = {}  # rule name -> JSON config string
    sdist_hook_bzl = {}  # rule name -> custom sdist hook .bzl file
    sdist_hook_fn = {}  # rule name -> custom sdist hook function name
    package_repo_hook_bzl = {}  # rule name -> custom package repo hook .bzl file
    package_repo_hook_fn = {}  # rule name -> custom package repo hook function name
    package_repo_hook_subdir = {}  # rule name -> thin repo alias subdir (e.g. "_cargo")
    default_backend = None
    default_backend_module = None
    backend_order = []
    override_file_by_name = {}  # rule name -> override_json label string

    # Registrations made by the root module. The root module comes first in
    # module_ctx.modules, so later registrations it overrides are dropped silently.
    root_names = {}
    root_pyproject_backends = {}
    root_default = False

    for module in modules:
        for tag in module.tags.register:
            name = tag.name

            # Duplicate rule name: root module wins, otherwise first-registered wins.
            if name in backend_configs and not module.is_root:
                if name not in root_names:
                    warn("Ignoring duplicate backend registration '{}' from module '{}'".format(name, module.name))
                elif tag.override_json and name not in override_file_by_name:
                    # Root re-registered a backend without specifying override_json;
                    # inherit the overridden registration's override file so existing
                    # `<backend>.override(...)` tags remain active.
                    override_file_by_name[name] = str(tag.override_json)
                continue
            if module.is_root:
                if name in backend_configs:
                    # Root re-registering the same backend replaces its prior
                    # pyproject_backends mappings and default flag cleanly.
                    for py_be in [k for k, v in backend_to_rule.items() if v == name]:
                        backend_to_rule.pop(py_be)
                        root_pyproject_backends.pop(py_be, None)
                    if default_backend == name and not tag.default:
                        default_backend = None
                        default_backend_module = None
                        root_default = False
                root_names[name] = True

            if name not in backend_order:
                backend_order.append(name)

            if tag.override_json:
                override_file_by_name[name] = str(tag.override_json)
            else:
                override_file_by_name.pop(name, None)

            config = {
                "rule_bzl": str(tag.rule_bzl),
                "tool_packages": tag.tool_packages,
            }
            backend_configs[name] = json.encode(config)

            if tag.sdist_hook_bzl:
                sdist_hook_bzl[name] = str(tag.sdist_hook_bzl)
            else:
                sdist_hook_bzl.pop(name, None)
            if tag.sdist_hook_fn:
                sdist_hook_fn[name] = tag.sdist_hook_fn
            else:
                sdist_hook_fn.pop(name, None)
            if tag.package_repo_hook_bzl:
                package_repo_hook_bzl[name] = str(tag.package_repo_hook_bzl)
            else:
                package_repo_hook_bzl.pop(name, None)
            if tag.package_repo_hook_fn:
                package_repo_hook_fn[name] = tag.package_repo_hook_fn
            else:
                package_repo_hook_fn.pop(name, None)
            if tag.package_repo_hook_subdir:
                package_repo_hook_subdir[name] = tag.package_repo_hook_subdir
            else:
                package_repo_hook_subdir.pop(name, None)

            for pyproject_backend in tag.pyproject_backends:
                if pyproject_backend in backend_to_rule and not module.is_root:
                    if pyproject_backend not in root_pyproject_backends:
                        warn(
                            "Ignoring duplicate pyproject backend '{}' -> '{}' from module '{}' (already mapped to '{}')".format(
                                pyproject_backend,
                                name,
                                module.name,
                                backend_to_rule[pyproject_backend],
                            ),
                        )
                    continue
                backend_to_rule[pyproject_backend] = name
                if module.is_root:
                    root_pyproject_backends[pyproject_backend] = True

            if not tag.default:
                continue
            if default_backend and not module.is_root:
                if not root_default:
                    warn(
                        "Ignoring default backend '{}' from module '{}' (already set to '{}' by module '{}')".format(
                            name,
                            module.name,
                            default_backend,
                            default_backend_module,
                        ),
                    )
                continue
            default_backend = name
            default_backend_module = module.name
            root_default = module.is_root

    if not default_backend:
        fail("No default build backend registered. Set `default = True` on one `backends.register` tag.")

    override_files = []
    seen_override_files = {}
    for name in backend_order:
        f = override_file_by_name.get(name)
        if f and f not in seen_override_files:
            seen_override_files[f] = True
            override_files.append(f)

    return struct(
        backend_to_rule = backend_to_rule,
        default_backend = default_backend,
        backend_configs = backend_configs,
        sdist_hook_bzl = sdist_hook_bzl,
        sdist_hook_fn = sdist_hook_fn,
        package_repo_hook_bzl = package_repo_hook_bzl,
        package_repo_hook_fn = package_repo_hook_fn,
        package_repo_hook_subdir = package_repo_hook_subdir,
        override_files = override_files,
    )

def _backends_impl(module_ctx):
    registry = _collect_registrations(module_ctx.modules)
    backend_registry_repo(
        name = "pycross_backends",
        backend_to_rule = registry.backend_to_rule,
        default_backend = registry.default_backend,
        backend_configs = registry.backend_configs,
        sdist_hook_bzl = registry.sdist_hook_bzl,
        sdist_hook_fn = registry.sdist_hook_fn,
        package_repo_hook_bzl = registry.package_repo_hook_bzl,
        package_repo_hook_fn = registry.package_repo_hook_fn,
        package_repo_hook_subdir = registry.package_repo_hook_subdir,
        override_files = registry.override_files,
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

backends = module_extension(
    doc = "Register build backends for pycross sdist builds.",
    implementation = _backends_impl,
    tag_classes = {
        "register": tag_class(
            doc = "Register a build backend for pycross sdist builds.",
            attrs = {
                "name": attr.string(
                    mandatory = True,
                    doc = "Pycross rule name (e.g. 'meson_build').",
                ),
                "rule_bzl": attr.label(
                    mandatory = True,
                    doc = "Label of the .bzl file exporting the rule, e.g. " +
                          "'@rules_pycross//pycross/backends:meson.bzl'.",
                ),
                "pyproject_backends": attr.string_list(
                    doc = "pyproject.toml build-system.build-backend values that map " +
                          "to this backend. Entries may include a bracketed list of " +
                          "required build-system.requires package names, e.g. " +
                          "'setuptools.build_meta[setuptools-rust]'. When multiple " +
                          "backends match the same build-backend value, the one with " +
                          "the most satisfied build_requires wins.",
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
                "sdist_hook_bzl": attr.label(
                    doc = "Optional label of a .bzl file providing a hook for " +
                          "sdist repo execution.",
                ),
                "sdist_hook_fn": attr.string(
                    doc = "Optional function name in sdist_hook_bzl. Defaults to " +
                          "'<name>_sdist_hook' (replacing '_build' suffix).",
                ),
                "package_repo_hook_bzl": attr.label(
                    doc = "Optional label of a .bzl file providing a hook for " +
                          "thin repo generation.",
                ),
                "package_repo_hook_fn": attr.string(
                    doc = "Optional function name in package_repo_hook_bzl. Defaults to " +
                          "'<name>_package_repo_hook' (replacing '_build' suffix).",
                ),
                "package_repo_hook_subdir": attr.string(
                    doc = "Optional subpackage directory (e.g. '_cargo') whose targets emitted by " +
                          "package_repo_hook_bzl in the workspace repo should be aliased in thin repos.",
                ),
                "override_json": attr.label(
                    doc = "Optional label of a generated JSON file containing overrides for this backend.",
                ),
            },
        ),
    },
)

# Visible for testing
collect_registrations_for_testing = _collect_registrations
