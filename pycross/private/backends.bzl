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

def _backends_impl(module_ctx):
    backend_to_rule = {}  # pyproject backend name -> rule name
    backend_configs = {}  # rule name -> JSON config string
    sdist_hook_bzl = {}  # rule name -> custom sdist hook .bzl file
    sdist_hook_fn = {}  # rule name -> custom sdist hook function name
    default_backend = None
    default_backend_module = None
    override_files = []

    for module in module_ctx.modules:
        for tag in module.tags.register:
            name = tag.name

            if tag.override_json:
                override_files.append(str(tag.override_json))

            # Duplicate rule name: root module wins, otherwise first-registered wins.
            if name in backend_configs:
                if module.is_root:
                    # Root module overrides.
                    pass
                else:
                    _print_warn("Ignoring duplicate backend registration '{}' from module '{}'".format(name, module.name))
                    continue

            config = {
                "rule_bzl": str(tag.rule_bzl),
                "tool_packages": tag.tool_packages,
            }
            backend_configs[name] = json.encode(config)

            if tag.sdist_hook_bzl:
                sdist_hook_bzl[name] = str(tag.sdist_hook_bzl)
            if tag.sdist_hook_fn:
                sdist_hook_fn[name] = tag.sdist_hook_fn

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
        fail("No default build backend registered. Set `default = True` on one `backends.register` tag.")

    backend_registry_repo(
        name = "pycross_backends",
        backend_to_rule = backend_to_rule,
        default_backend = default_backend,
        backend_configs = backend_configs,
        sdist_hook_bzl = sdist_hook_bzl,
        sdist_hook_fn = sdist_hook_fn,
        override_files = override_files,
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
                    doc = "Label of the .bzl file containing the rule, e.g. " +
                          "'@rules_pycross//pycross/private/build/rules:meson_build.bzl'.",
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
                "override_json": attr.label(
                    doc = "Optional label of a generated JSON file containing overrides for this backend.",
                ),
            },
        ),
    },
)
