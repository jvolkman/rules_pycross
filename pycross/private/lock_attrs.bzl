"""Common attr handling for things that generate lock files."""

DEFAULT_MACOS_VERSION = "15.0"

# Use https://github.com/mayeut/pep600_compliance to keep this reasonable.
DEFAULT_GLIBC_VERSION = "2.28"

DEFAULT_MUSL_VERSION = "1.2"

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
            "The target's glibc version, for Bazel platforms that match the " +
            "@platforms//os:linux constraint; wheels tagged up to it are accepted. Must be in " +
            "the format '2.X', and greater than 2.5. For example, if this value is set to 2.15, " +
            "wheels tagged manylinux_2_5, manylinux_2_6, ..., manylinux_2_15 will be accepted. " +
            "Sets the default of `@rules_pycross//pycross/settings:glibc_version`."
        ),
    ),
    musl_version = attr.string(
        default = DEFAULT_MUSL_VERSION,
        doc = (
            "The target's musl version, for Bazel platforms that match the " +
            "@platforms//os:linux constraint when @rules_python//python/config_settings:py_linux_libc " +
            "is set to 'musl'; wheels tagged up to it are accepted. " +
            "Sets the default of `@rules_pycross//pycross/settings:musl_version`."
        ),
    ),
    macos_version = attr.string(
        default = DEFAULT_MACOS_VERSION,
        doc = (
            "The target's macOS version, for Bazel platforms that match the " +
            "@platforms//os:osx constraint; wheels tagged up to it are accepted. Must be in the " +
            "format 'X.Y' with X >= 10. For example, if this value is set to 12.0, wheels tagged " +
            "macosx_10_4, macosx_10_5, ..., macosx_11_0, macosx_12_0 will be accepted. " +
            "Sets the default of `@rules_pycross//pycross/settings:macos_version`."
        ),
    ),
    register_toolchains = attr.bool(
        doc = "Register toolchains for all rules_python-registered interpreters.",
        default = True,
    ),
)

# Attrs specific to build-system overrides (meson, setuptools, etc.).
# These do not belong on the generic package() tag.
BUILD_SYSTEM_ATTRS = dict(
    config_settings = attr.string_list_dict(doc = "Setup configuration arguments."),
    tool_deps = attr.string_keyed_label_dict(
        doc = (
            "Overrides for the backend's tool packages, keyed by tool package name (e.g. " +
            "`{\"cmake\": \"@other//cmake:pkg\"}`). Each entry replaces the auto-detected " +
            "default for that tool, or adds it if the tool is not in the lock. Keys must be one " +
            "of the backend's tool packages (or `repairwheel`), and each value must be a pycross " +
            "package target for that package."
        ),
    ),
    build_env = attr.string_dict(doc = "Extra environment variables passed to the sdist build."),
    data = attr.label_list(doc = "Additional data and dependencies used by the build."),
    pre_build_hooks = attr.label_list(doc = "Executables to run before building the wheel."),
    post_build_hooks = attr.label_list(doc = "Executables to run after the wheel is built."),
    repair_exclude_globs = attr.string_list(doc = "Shared library globs to exclude from wheel repair; assumed provided at runtime."),
)

# Attrs for build backends that compile native (C/C++) code.
CC_BUILD_SYSTEM_ATTRS = dict(
    copts = attr.string_list(doc = "Extra C++ compiler options."),
    linkopts = attr.string_list(doc = "Extra linker options."),
    native_deps = attr.label_list(doc = "CC dependencies to link against."),
    path_tools = attr.label_list(
        doc = "A list of binary targets placed on PATH during the build, under their basename. " +
              "Wrap a target in `pycross_path_tool` to give it a different name on PATH.",
    ),
)

CORE_OVERRIDE_ATTRS = dict(
    name = attr.string(
        doc = "The package name, `name@version`, or '*' to apply to all packages built with this backend. " +
              "For a package `name@version`, matching entries are layered from least to most specific " +
              "(`*`, then `name`, then `name@version`); each field set by a more specific entry replaces " +
              "the less specific value. The version must match a locked version exactly.",
        mandatory = True,
    ),
    workspace = attr.string(
        doc = "The workspace whose packages this override applies to.",
        mandatory = True,
    ),
)

MESON_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

SETUPTOOLS_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

CMAKE_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS
