"""Shared attr definitions"""

load(
    "//pycross/private:lock_attrs.bzl",
    _CREATE_ENVIRONMENTS_ATTRS = "CREATE_ENVIRONMENTS_ATTRS",
    _CREATE_REPOS_ATTRS = "CREATE_REPOS_ATTRS",
    _PDM_IMPORT_ATTRS = "PDM_IMPORT_ATTRS",
    _POETRY_IMPORT_ATTRS = "POETRY_IMPORT_ATTRS",
    _REGISTER_TOOLCHAINS_ATTRS = "REGISTER_TOOLCHAINS_ATTRS",
    _UV_IMPORT_ATTRS = "UV_IMPORT_ATTRS",
)

# Attrs common to all tags
COMMON_ATTRS = dict(
    repo = attr.string(
        doc = "The repository name",
        mandatory = True,
    ),
)

# Attrs common to the import_* tags
COMMON_IMPORT_ATTRS = dict(
    default_alias_single_version = attr.bool(
        doc = "Generate aliases for all packages that have a single version in the lock file.",
    ),
    target_environments = attr.label_list(
        # TODO: expand doc
        doc = "A list of target environment descriptors.",
        default = [
            "@pycross_environments//:environments",
        ],
    ),
    local_wheels = attr.label_list(
        doc = "A list of local .whl files to consider when processing lock files.",
    ),
    disallow_builds = attr.bool(
        doc = "If True, only pre-built wheels are allowed.",
    ),
    default_build_dependencies = attr.string_list(
        doc = "A list of package keys (name or name@version) that will be used as default build dependencies.",
    ),
)

# Attrs for the package tag
PACKAGE_ATTRS = dict(
    name = attr.string(
        doc = "The package key (name or name@version).",
        mandatory = True,
    ),
    build_backend = attr.string(
        doc = "An explicit build backend rule name to use for this package (e.g. 'maturin_build'). Overrides pyproject.toml detection.",
    ),
    build_target = attr.label(
        doc = "An optional override build target to use when and if this package needs to be built from source.",
    ),
    always_build = attr.bool(
        doc = "If True, don't use pre-built wheels for this package.",
    ),
    build_dependencies = attr.string_list(
        doc = "A list of additional package keys (name or name@version) to use when building this package from source.",
    ),
    ignore_dependencies = attr.string_list(
        doc = "A list of package keys (name or name@version) to drop from this package's set of declared dependencies.",
    ),
    install_exclude_globs = attr.string_list(
        doc = "A list of globs for files to exclude during installation.",
    ),
    post_install_patches = attr.string_list(
        doc = "A list of patches to apply after wheel installation.",
    ),
    pre_build_patches = attr.string_list(
        doc = "A list of patches to apply to the sdist source tree before building.",
    ),
    backend_attrs = attr.string_dict(
        doc = "Arbitrary backend-specific attributes. Keys are attr names on the backend rule; " +
              "values are JSON-encoded Starlark literals (e.g. '[\"a\", \"b\"]' for a list, " +
              "'{\"k\": \"v\"}' for a dict, '\"hello\"' for a string, 'true' for a bool).",
    ),
)

# Attrs specific to build-system overrides (meson, setuptools, etc.).
# These do not belong on the generic package() tag.
BUILD_SYSTEM_ATTRS = dict(
    copts = attr.string_list(doc = "Extra C++ compiler options."),
    linkopts = attr.string_list(doc = "Extra linker options."),
    native_deps = attr.label_list(doc = "CC dependencies to link against."),
    config_settings = attr.string_list_dict(doc = "Setup configuration arguments."),
    tool_deps = attr.string_dict(doc = "Overrides for built-in dependencies."),
)

CREATE_ENVIRONMENTS_ATTRS = _CREATE_ENVIRONMENTS_ATTRS
CREATE_REPOS_ATTRS = _CREATE_REPOS_ATTRS
PDM_IMPORT_ATTRS = _PDM_IMPORT_ATTRS
UV_IMPORT_ATTRS = _UV_IMPORT_ATTRS
POETRY_IMPORT_ATTRS = _POETRY_IMPORT_ATTRS
REGISTER_TOOLCHAINS_ATTRS = _REGISTER_TOOLCHAINS_ATTRS

CORE_OVERRIDE_ATTRS = dict(
    name = attr.string(
        doc = "The package key (name or name@version).",
        mandatory = True,
    ),
    repo = attr.string(
        doc = "The repository name",
        mandatory = True,
    ),
)

MESON_OVERRIDE_ATTRS = dict(CORE_OVERRIDE_ATTRS, **BUILD_SYSTEM_ATTRS)

SETUPTOOLS_OVERRIDE_ATTRS = dict(CORE_OVERRIDE_ATTRS, **BUILD_SYSTEM_ATTRS)

CMAKE_OVERRIDE_ATTRS = dict(CORE_OVERRIDE_ATTRS, **BUILD_SYSTEM_ATTRS)
