"""Common attr handling for things that generate lock files."""

load(":util.bzl", "BZLMOD")

DEFAULT_MACOS_VERSION = "15.0"

# Use https://github.com/mayeut/pep600_compliance to keep this reasonable.
DEFAULT_GLIBC_VERSION = "2.28"

DEFAULT_MUSL_VERSION = "1.2"

CREATE_ENVIRONMENTS_ATTRS = dict(
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
        doc = (
            "The maximum glibc version to accept for Bazel platforms that match the " +
            "@platforms//os:linux constraint. Must be in the format '2.X', and greater than 2.5. " +
            "All versions from 2.5 through this version will be supported. For example, if this " +
            "value is set to 2.15, wheels tagged manylinux_2_5, manylinux_2_6, ..., " +
            "manylinux_2_15 will be accepted. Defaults to '{}' if unspecified.".format(DEFAULT_GLIBC_VERSION)
        ),
    ),
    musl_version = attr.string(
        doc = (
            "The musl version to accept for Bazel platforms that match the " +
            "@platforms//os:linux constraint when @rules_python//python/config_settings:py_linux_libc " +
            "is set to 'musl'. Defaults to '{}' if unspecified.".format(DEFAULT_MUSL_VERSION)
        ),
    ),
    macos_version = attr.string(
        doc = (
            "The maximum macOS version to accept for Bazel platforms that match the " +
            "@platforms//os:osx constraint. Must be in the format 'X.Y' with X >= 10. " +
            "All versions from 10.4 through this version will be supported. For example, if this " +
            "value is set to 12.0, wheels tagged macosx_10_4, macosx_10_5, ..., macosx_11_0, " +
            "macosx_12_0 will be accepted. Defaults to '{}' if unspecified.".format(DEFAULT_MACOS_VERSION)
        ),
    ),
)

REGISTER_TOOLCHAINS_ATTRS = dict(
    register_toolchains = attr.bool(
        doc = "Register toolchains for all rules_python-registered interpreters.",
        default = True,
    ),
)

RESOLVE_ATTRS = dict(
    target_environments = attr.label_list(
        doc = "A list of pycross_target_environment labels.",
        allow_files = [".json"],
    ),
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

RENDER_ATTRS = dict(
    repo_prefix = attr.string(
        doc = "The prefix to apply to repository targets. Defaults to the lock file target name.",
        default = "",
    ),
    generate_file_map = attr.bool(
        doc = "Generate a FILES dict containing a mapping of filenames to repo labels.",
    ),
) | CREATE_REPOS_ATTRS

_IMPORT_ATTRS = dict(
    lock_file = attr.label(
        doc = "The lock file.",
        allow_single_file = True,
        mandatory = True,
    ),
    project_file = attr.label(
        doc = "The pyproject.toml file.",
        allow_single_file = True,
        mandatory = True,
    ),
    default = attr.bool(
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
        doc = "The pyproject.toml file.",
        allow_single_file = True,
        mandatory = True,
    ),
    default = attr.bool(
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

def handle_resolve_attrs(attrs, environment_files_and_labels, local_wheel_names_and_labels):
    """
    Parse resolve attrs and return a list of arguments.

    Args:
      attrs: ctx.attr or repository_ctx.attr
      environment_files_and_labels: a list of 2-tuples, each containing an
        environment file and its corresponding label.
      local_wheel_names_and_labels: a list of 2-tuples, each containing an
        wheel name and its corresponding label.

    Returns:
      a list of arguments.
    """
    args = []

    for env_file, env_label in environment_files_and_labels:
        args.extend(["--target-environment", env_file, env_label])

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

def handle_render_attrs(attrs):
    """
    Parse render attrs and return a list of arguments.

    Args:
      attrs: ctx.attr or repository_ctx.attr

    Returns:
      a list of arguments.
    """

    # If building locks for pycross itself, we don't want a repo name prefix on labels in the
    # generated .bzl file. We can figure that out by comparing our workspace against the root workspace.
    if Label("@@//:invalid").workspace_name == Label("//:invalid").workspace_name:
        pycross_repo_name = ""
    elif BZLMOD:
        pycross_repo_name = "@@" + Label("//:invalid").workspace_name
    else:
        pycross_repo_name = "@" + Label("//:invalid").workspace_name

    args = ["--pycross-repo-name", pycross_repo_name]

    if attrs.repo_prefix:
        repo_prefix = attrs.repo_prefix
    else:
        repo_prefix = attrs.name.lower().replace("-", "_")

    args.extend(["--repo-prefix", repo_prefix])

    if attrs.generate_file_map:
        args.append("--generate-file-map")

    return args + handle_create_repos_attrs(attrs)

def handle_create_repos_attrs(attrs):
    """
    Parse repository materializing attrs and return a list of arguments.

    Args:
      attrs: ctx.attr or repository_ctx.attr

    Returns:
      a list of arguments.
    """
    args = []

    if attrs.pypi_index:
        args.extend(["--pypi-index", attrs.pypi_index])

    return args

def package_annotation(
        always_build = False,
        build_dependencies = [],
        build_target = None,
        ignore_dependencies = [],
        install_exclude_globs = []):
    """Annotations to apply to individual packages.

    Args:
      always_build (bool, optional): If True, don't use pre-build wheels for this package.
      build_dependencies (list, optional): A list of additional package keys (name or name@version) to use when building this package from source.
      build_target (str, optional): An optional override build target to use when and if this package needs to be built from source.
      ignore_dependencies (list, optional): A list of package keys (name or name@version) to drop from this package's set of declared dependencies.
      install_exclude_globs (list, optional): A list of globs for files to exclude during installation.

    Returns:
      str: A json encoded string of the provided content.
    """
    return json.encode(struct(
        always_build = always_build,
        build_dependencies = build_dependencies,
        build_target = build_target,
        ignore_dependencies = ignore_dependencies,
        install_exclude_globs = install_exclude_globs,
    ))

PDM_IMPORT_ATTRS = _IMPORT_ATTRS
UV_IMPORT_ATTRS = _IMPORT_ATTRS
