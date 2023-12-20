"""Common attr handling for things that generate lock files."""

# Whether bzlmod is enabled.
_BZLMOD = str(Label("//:invalid")).startswith("@@")

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
)

RENDER_ATTRS = dict(
    repo_prefix = attr.string(
        doc = "The prefix to apply to repository targets. Defaults to the lock file target name.",
        default = "",
    ),
    package_prefix = attr.string(
        doc = "An optional prefix to apply to package targets.",
        default = "",
    ),
    build_prefix = attr.string(
        doc = "An optional prefix to apply to package build targets. Defaults to _build",
        default = "_build",
    ),
    environment_prefix = attr.string(
        doc = "An optional prefix to apply to environment targets. Defaults to _env",
        default = "_env",
    ),
    pypi_index = attr.string(
        doc = "The PyPI-compatible index to use (must support the JSON API).",
    ),
    generate_file_map = attr.bool(
        doc = "Generate a FILES dict containing a mapping of filenames to repo labels.",
    ),
)

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

    if attrs.package_prefix:
        args.extend(["--package-prefix", attrs.package_prefix])

    if attrs.build_prefix:
        args.extend(["--build-prefix", attrs.build_prefix])

    if attrs.environment_prefix:
        args.extend(["--environment-prefix", attrs.environment_prefix])

    if attrs.pypi_index:
        args.extend(["--pypi-index", attrs.pypi_index])

    if attrs.generate_file_map:
        args.append("--generate-file-map")

    return args
