"""Implementation of pycross_package_annotation"""

def pycross_package_annotation(
        always_build = False,
        build_dependencies = [],
        build_target_override = None,
        ignore_dependencies = [],
        install_exclude_globs = []):
    """Annotations to apply to individual packages.

    Args:
        always_build (bool, optional): If True, don't use pre-build wheels for this package.
        build_dependencies (list, optional): A list of additional package keys (name or name@version) to use when building this package from source.
        build_target_override (str, optional): An optional override build target to use when and if this package needs to be built from source.
        ignore_dependencies (list, optional): A list of package keys (name or name@version) to drop from this package's set of declared dependencies.
        install_exclude_globs (list, optional): A list of globs for files to exclude during installation.

    Returns:
        str: A json encoded strong of the provided content.
    """
    return json.encode(struct(
        always_build = always_build,
        build_dependencies = build_dependencies,
        build_target_override = build_target_override,
        ignore_dependencies = ignore_dependencies,
        install_exclude_globs = install_exclude_globs,
    ))
