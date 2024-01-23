"""Common attr handling for things that generate lock files."""

# Whether bzlmod is enabled.
_BZLMOD = str(Label("//:invalid")).startswith("@@")

DEFAULT_MACOS_VERSION = "12.0"
DEFAULT_GLIBC_VERSION = "2.25"

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
    build_target_overrides = attr.string_dict(
        doc = "A mapping of package keys (name or name@version) to existing pycross_wheel_build build targets.",
    ),
    always_build_packages = attr.string_list(
        doc = "A list of package keys (name or name@version) to always build from source.",
    ),
    package_build_dependencies = attr.string_list_dict(
        doc = "A dict of package keys (name or name@version) to a list of that packages build dependency keys.",
    ),
    package_ignore_dependencies = attr.string_list_dict(
        doc = "A dict of package keys (name or name@version) to a list of that packages dependency keys to ignore.",
    ),
    disallow_builds = attr.bool(
        doc = "Do not allow pycross_wheel_build targets in the final lock file (i.e., require wheels).",
    ),
    always_include_sdist = attr.bool(
        doc = "Always include an entry for a package's sdist if one exists.",
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

PDM_IMPORT_ATTRS = dict(
    lock_file = attr.label(
        doc = "The pdm.lock file.",
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

    for k, t in attrs.build_target_overrides.items():
        args.extend(["--build-target-override", k, t])

    for k in attrs.always_build_packages:
        args.extend(["--always-build-package", k])

    for k, d in attrs.package_build_dependencies.items():
        for dep in d:
            args.extend(["--build-dependency", k, dep])

    for k, d in attrs.package_ignore_dependencies.items():
        for dep in d:
            args.extend(["--ignore-dependency", k, dep])

    if attrs.disallow_builds:
        args.append("--disallow-builds")

    if attrs.always_include_sdist:
        args.append("--always-include-sdist")

    for wheel_name, wheel_label in local_wheel_names_and_labels:
        args.extend(["--local-wheel", wheel_name, wheel_label])

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
    elif _BZLMOD:
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
