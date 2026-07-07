"""Common attr handling for things that generate lock files."""

DEFAULT_MACOS_VERSION = "15.0"

# Use https://github.com/mayeut/pep600_compliance to keep this reasonable.
DEFAULT_GLIBC_VERSION = "2.28"

DEFAULT_MUSL_VERSION = "1.2"

TRANSITION_ATTRS = dict(
    constraint_values = attr.label_list(
        doc = "A list of constraint values to apply to the generated platform.",
    ),
    flags = attr.string_list(
        doc = "A list of flags to apply to the generated platform (e.g., '--@flag=value').",
    ),
    platform = attr.label(
        doc = "An existing platform target to use directly.",
    ),
)

CONFIGURE_TOOLCHAINS_ATTRS = dict(
    python_versions = attr.string_list(
        doc = (
            "The list of Python versions to support in by default in Pycross builds. " +
            "These strings will be X.Y or X.Y.Z depending on how versions were registered " +
            "with rules_python. By default all registered versions are supported."
        ),
    ),
    platforms = attr.string_list(
        doc = (
            "The list of Python platforms to support in by default in Pycross builds. " +
            "See https://github.com/bazelbuild/rules_python/blob/main/python/versions.bzl " +
            "for the list of supported platforms per Python version. By default all supported " +
            "platforms for each registered version are supported."
        ),
    ),
    glibc_version = attr.string(
        default = DEFAULT_GLIBC_VERSION,
        doc = (
            "The maximum glibc version to accept for Bazel platforms that match the " +
            "@platforms//os:linux constraint. Must be in the format '2.X', and greater than 2.5. " +
            "All versions from 2.5 through this version will be supported. For example, if this " +
            "value is set to 2.15, wheels tagged manylinux_2_5, manylinux_2_6, ..., " +
            "manylinux_2_15 will be accepted."
        ),
    ),
    musl_version = attr.string(
        default = DEFAULT_MUSL_VERSION,
        doc = (
            "The musl version to accept for Bazel platforms that match the " +
            "@platforms//os:linux constraint when @rules_python//python/config_settings:py_linux_libc " +
            "is set to 'musl'."
        ),
    ),
    macos_version = attr.string(
        default = DEFAULT_MACOS_VERSION,
        doc = (
            "The maximum macOS version to accept for Bazel platforms that match the " +
            "@platforms//os:osx constraint. Must be in the format 'X.Y' with X >= 10. " +
            "All versions from 10.4 through this version will be supported. For example, if this " +
            "value is set to 12.0, wheels tagged macosx_10_4, macosx_10_5, ..., macosx_11_0, " +
            "macosx_12_0 will be accepted."
        ),
    ),
    register_toolchains = attr.bool(
        doc = "Register toolchains for all rules_python-registered interpreters.",
        default = True,
    ),
)

RESOLVE_ATTRS = dict(
    local_wheels = attr.label_list(
        doc = "A list of wheel files.",
        allow_files = [".whl"],
    ),
    remote_wheels = attr.string_dict(
        doc = "A mapping of remote wheels to their sha256 hashes.",
    ),
    create_transitive_aliases = attr.bool(
        doc = "Generate aliases for all packages that have a single version in the lock file.",
    ),
    annotations = attr.string_dict(
        doc = "Optional annotations to apply to packages.",
    ),
    disallow_builds = attr.bool(
        doc = "Do not allow pycross_wheel_build targets in the final lock file (i.e., require wheels).",
    ),
    always_include_sdist = attr.bool(
        doc = "Always include an entry for a package's sdist if one exists.",
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
    extra_build_tools = attr.string_list(
        doc = "A list of additional package keys (name or name@version) to use when building this package from source.",
    ),
    build_tools_repo = attr.string(
        doc = "Optional repo to use for resolving sdist build dependencies for this package.",
    ),
    ignore_dependencies = attr.string_list(
        doc = "A list of package keys (name or name@version) to drop from this package's set of declared dependencies.",
    ),
    install_exclude_globs = attr.string_list(
        doc = "A list of globs for files to exclude during installation.",
    ),
    post_install_patches = attr.label_list(
        doc = "A list of patches to apply after wheel installation.",
        allow_files = True,
    ),
    pre_build_patches = attr.label_list(
        doc = "A list of patches to apply to the sdist source tree before building.",
        allow_files = True,
    ),
    site_hooks = attr.string_list(
        doc = "A list of Python code snippets to execute on interpreter startup during builds.",
    ),
    site_paths = attr.string_list(
        doc = "Override the auto-detected top-level importable paths (packages, .pth files, standalone modules). " +
              "Use forward slashes for nested namespaces (e.g. 'google/cloud/storage').",
    ),
    bin_paths = attr.string_list(
        doc = "Override the auto-detected bin paths.",
    ),
    data_paths = attr.string_list(
        doc = "Override the auto-detected data paths.",
    ),
    include_paths = attr.string_list(
        doc = "Override the auto-detected include paths.",
    ),
)

# Attrs specific to build-system overrides (meson, setuptools, etc.).
# These do not belong on the generic package() tag.
BUILD_SYSTEM_ATTRS = dict(
    config_settings = attr.string_list_dict(doc = "Setup configuration arguments."),
    tool_deps = attr.string_dict(doc = "Overrides for built-in dependencies."),
    build_env = attr.string_dict(doc = "Extra environment variables passed to the sdist build."),
    data = attr.label_list(doc = "Additional data and dependencies used by the build."),
    pre_build_hooks = attr.label_list(doc = "Executables to run before building the wheel."),
    post_build_hooks = attr.label_list(doc = "Executables to run after the wheel is built."),
)

# Attrs for build backends that compile native (C/C++) code.
CC_BUILD_SYSTEM_ATTRS = dict(
    copts = attr.string_list(doc = "Extra C++ compiler options."),
    linkopts = attr.string_list(doc = "Extra linker options."),
    native_deps = attr.label_list(doc = "CC dependencies to link against."),
    path_tools = attr.label_list(doc = "A list of binary targets placed on PATH during the build."),
)

# Attrs for applying overrides to specific repos or workspaces.
OVERRIDE_TARGET_ATTRS = dict(
    repo = attr.string(
        doc = "The repository name (if applying to a specific lock file).",
    ),
    workspace = attr.string(
        doc = "The workspace name (if applying to all members of a workspace).",
    ),
)

CORE_OVERRIDE_ATTRS = dict(
    name = attr.string(
        doc = "The package key (name or name@version).",
        mandatory = True,
    ),
) | OVERRIDE_TARGET_ATTRS

MESON_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

SETUPTOOLS_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

CMAKE_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS
