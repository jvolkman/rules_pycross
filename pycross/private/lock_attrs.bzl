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
    default_alias_single_version = attr.bool(
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
    default_build_dependencies = attr.string_list(
        doc = "A list of package keys (name or name@version) that will be used as default build dependencies.",
    ),
)

CREATE_REPOS_ATTRS = dict(
    pypi_index = attr.string(
        doc = "The PyPI-compatible index to use (must support the JSON API).",
    ),
)

_IMPORT_ATTRS = dict(
    lock_file = attr.label(
        doc = "The lock file.",
        allow_single_file = True,
        mandatory = True,
    ),
    project_file = attr.label(
        doc = "The pyproject.toml file. If not specified, defaults to pyproject.toml next to the lock file.",
        allow_single_file = True,
    ),
    default_group = attr.bool(
        doc = "Whether to install dependencies from the default group.",
        default = True,
    ),
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install.",
    ),
    all_optional_groups = attr.bool(
        doc = "Install all optional dependencies.",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install.",
    ),
    all_development_groups = attr.bool(
        doc = "Install all dev dependencies.",
    ),
    require_static_urls = attr.bool(
        doc = "Require that the lock file is created with --static-urls.",
        default = True,
    ),
)

POETRY_IMPORT_ATTRS = dict(
    lock_file = attr.label(
        doc = "The poetry.lock file.",
        allow_single_file = True,
        mandatory = True,
    ),
    project_file = attr.label(
        doc = "The pyproject.toml file. If not specified, defaults to pyproject.toml next to the lock file.",
        allow_single_file = True,
    ),
    default_group = attr.bool(
        doc = "Whether to install dependencies from the default group.",
        default = True,
    ),
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install.",
    ),
    all_optional_groups = attr.bool(
        doc = "Install all optional dependencies.",
    ),
)

def handle_resolve_attrs(attrs, local_wheel_names_and_labels):
    """
    Parse resolve attrs and return a list of arguments.

    Args:
      attrs: ctx.attr or repository_ctx.attr
      local_wheel_names_and_labels: a list of 2-tuples, each containing an
        wheel name and its corresponding label.

    Returns:
      a list of arguments.
    """
    args = []

    for remote_wheel_url, sha256 in attrs.remote_wheels.items():
        args.extend(["--remote-wheel", remote_wheel_url, sha256])

    if attrs.default_alias_single_version:
        args.append("--default-alias-single-version")

    if attrs.disallow_builds:
        args.append("--disallow-builds")

    if attrs.always_include_sdist:
        args.append("--always-include-sdist")

    for wheel_name, wheel_label in local_wheel_names_and_labels:
        args.extend(["--local-wheel", wheel_name, wheel_label])

    # for dep in attrs.default_build_dependencies:
    if attrs.default_build_dependencies:
        args.append("--default-build-dependencies")
        args.extend(attrs.default_build_dependencies)

    return args

PDM_IMPORT_ATTRS = _IMPORT_ATTRS
UV_IMPORT_ATTRS = _IMPORT_ATTRS

# Group-selection attrs for all_members tags (group-wide defaults).
# Boolean flags (all_optional_groups, all_development_groups) live only here;
# per-member overrides disable them implicitly by specifying explicit lists.
_WORKSPACE_GROUP_ATTRS = dict(
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install.",
    ),
    all_optional_groups = attr.bool(
        doc = "Install all optional dependencies.",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install.",
    ),
    all_development_groups = attr.bool(
        doc = "Install all dev dependencies.",
    ),
)

# Group-selection attrs for member override tags.
# default_group lives only here (not on members) since disabling default deps
# is a per-member decision. List attrs override the members-level defaults
# when non-empty.
_WORKSPACE_GROUP_OVERRIDE_ATTRS = dict(
    default_group = attr.bool(
        doc = "Whether to install dependencies from the default group.",
        default = True,
    ),
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install (overrides all_members setting).",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install (overrides all_members setting).",
    ),
)

UV_WORKSPACE_ATTRS = dict(
    lock_file = attr.label(
        doc = "The shared uv.lock file for the workspace.",
        allow_single_file = True,
        mandatory = True,
    ),
    require_static_urls = attr.bool(
        doc = "Require that the lock file is created with --static-urls.",
        default = True,
    ),
)

UV_ALL_MEMBERS_ATTRS = dict(
    repo_pattern = attr.string(
        doc = "Pattern for auto-generated repo names. Use '{member}' as a placeholder " +
              "for the normalized project name. For example, 'ws_{member}' produces " +
              "'ws_lib_a' for a project named 'lib-a'. Default is '{member}'.",
        default = "{member}",
    ),
    excluded_projects = attr.string_list(
        doc = "Project names to skip during auto-discovery.",
    ),
) | _WORKSPACE_GROUP_ATTRS

UV_MEMBER_ATTRS = dict(
    project = attr.string(
        doc = "The project name as it appears in uv.lock. Optional if the workspace has only one member.",
    ),
    repo = attr.string(
        doc = "Override the repo name (default: {prefix}{normalized_project_name}).",
    ),
    project_file = attr.label(
        doc = "Override auto-discovered pyproject.toml path.",
        allow_single_file = True,
    ),
) | _WORKSPACE_GROUP_OVERRIDE_ATTRS

PDM_WORKSPACE_ATTRS = dict(
    lock_file = attr.label(
        doc = "The shared pdm.lock file for the workspace.",
        allow_single_file = True,
        mandatory = True,
    ),
)

PDM_ALL_MEMBERS_ATTRS = dict(
    repo_pattern = attr.string(
        doc = "Pattern for auto-generated repo names. Use '{member}' as a placeholder " +
              "for the normalized project name. For example, 'ws_{member}' produces " +
              "'ws_lib_a' for a project named 'lib-a'. Default is '{member}'.",
        default = "{member}",
    ),
    excluded_projects = attr.string_list(
        doc = "Project names to skip during auto-discovery.",
    ),
) | _WORKSPACE_GROUP_ATTRS

PDM_MEMBER_ATTRS = dict(
    project = attr.string(
        doc = "The project name as it appears in pdm.lock. Optional if the workspace has only one member.",
    ),
    repo = attr.string(
        doc = "Override the repo name (default: {prefix}{normalized_project_name}).",
    ),
    project_file = attr.label(
        doc = "Override auto-discovered pyproject.toml path.",
        allow_single_file = True,
    ),
) | _WORKSPACE_GROUP_OVERRIDE_ATTRS

PYLOCK_IMPORT_ATTRS = dict(
    lock_file = attr.label(
        doc = "The pylock.toml file.",
        allow_single_file = True,
        mandatory = True,
    ),
    project_file = attr.label(
        doc = "Optional pyproject.toml file.",
        allow_single_file = True,
    ),
    default_group = attr.bool(
        doc = "Whether to install dependencies from the default group.",
        default = True,
    ),
    optional_groups = attr.string_list(
        doc = "List of optional dependency groups to install.",
    ),
    all_optional_groups = attr.bool(
        doc = "Install all optional dependencies.",
    ),
    development_groups = attr.string_list(
        doc = "List of development dependency groups to install.",
    ),
    all_development_groups = attr.bool(
        doc = "Install all dev dependencies.",
    ),
)

_SINGLE_PROJECT_MEMBER_ATTRS = dict(
    project = attr.string(
        doc = "Optional project name.",
    ),
    repo = attr.string(
        doc = "Override the repo name.",
    ),
    project_file = attr.label(
        doc = "Override auto-discovered pyproject.toml path.",
        allow_single_file = True,
    ),
) | _WORKSPACE_GROUP_OVERRIDE_ATTRS

POETRY_MEMBER_ATTRS = _SINGLE_PROJECT_MEMBER_ATTRS
PYLOCK_MEMBER_ATTRS = _SINGLE_PROJECT_MEMBER_ATTRS

# Attrs common to lock repos
REPO_ATTR = dict(
    repo = attr.string(
        doc = "The repository name",
        mandatory = True,
    ),
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

# Attrs common to the import_* tags
COMMON_IMPORT_ATTRS = dict(
    default_alias_single_version = attr.bool(
        doc = "Generate aliases for all packages that have a single version in the lock file.",
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
    build_repo = attr.string(
        doc = "Optional default repo to use for resolving sdist build dependencies.",
    ),
)

# Attrs common to import_uv_workspace (workspace-level settings inherited by all members).
# Same as COMMON_IMPORT_ATTRS but without 'workspace' (implied by name) and 'repo' (per-member).
WORKSPACE_COMMON_ATTRS = dict(
    name = attr.string(
        doc = "Workspace name. Used to link members to this workspace.",
        mandatory = True,
    ),
    default_alias_single_version = attr.bool(
        doc = "Generate aliases for all packages that have a single version in the lock file.",
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
    build_repo = attr.string(
        doc = "Optional default repo to use for resolving sdist build dependencies.",
    ),
)

# Attrs that link a workspace member or members tag to its parent workspace.
WORKSPACE_MEMBER_COMMON_ATTRS = dict(
    workspace = attr.string(
        doc = "Name of the workspace this member belongs to.",
        mandatory = True,
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
    build_repo = attr.string(
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

CORE_OVERRIDE_ATTRS = dict(
    name = attr.string(
        doc = "The package key (name or name@version).",
        mandatory = True,
    ),
) | OVERRIDE_TARGET_ATTRS

MESON_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

SETUPTOOLS_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

CMAKE_OVERRIDE_ATTRS = CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS
