"""Helpers for creating Pycross environments and toolchains"""

load("@rules_python//python:versions.bzl", "MINOR_MAPPING", "PLATFORMS", "TOOL_VERSIONS")
load(":target_environment.bzl", "repo_batch_create_target_environments")

DEFAULT_MACOS_VERSION = "12.0"
DEFAULT_GLIBC_VERSION = "2.25"

# Whether bzlmod is enabled.
BZLMOD = str(Label("//:invalid")).startswith("@@")

def _get_minor_version(version):
    if version in MINOR_MAPPING:
        return MINOR_MAPPING[version]
    elif version in TOOL_VERSIONS:
        return version

    fail("Unknown Python version: {}".format(version))

def _get_version_components(version):
    parts = version.split(".")
    if len(parts) < 2:
        fail("Invalid Python version; must be format X.Y or X.Y.Z: %s" % str(version))

    return int(parts[0]), int(parts[1])

def _get_abi(version):
    major, minor = _get_version_components(version)
    return "cp{}{}".format(major, minor)

def _get_env_platforms(py_platform, glibc_version, macos_version):
    glibc_major, glibc_minor = _get_version_components(glibc_version)
    macos_major, macos_minor = _get_version_components(macos_version)

    if macos_major < 10:
        fail("macos version must be >= 10")
    if (glibc_major, glibc_minor) < (2, 5) or (glibc_major, glibc_minor) >= (3, 0):
        fail("glibc version must be >= 2.5 and < 3.0")

    platform_info = PLATFORMS[py_platform]
    arch = platform_info.arch
    if py_platform.endswith("linux-gnu"):
        return ["linux_{}".format(arch)] + [
            "manylinux_2_{}_{}".format(i, arch)
            for i in range(5, glibc_minor + 1)
        ]
    elif py_platform.endswith("darwin"):
        return ["macosx_{}_{}_{}".format(macos_major, macos_minor, arch)]
    elif py_platform.endswith("windows-msvc"):
        return ["win_amd64"]

    fail("Unknown platform: {}".format(py_platform))

def _compute_environments_and_toolchains(
        repo_name,
        python_toolchains_repo_name,
        is_multi_version_layout,
        python_versions,
        default_version,
        platforms,
        glibc_version,
        macos_version):
    environments = []
    toolchains = []

    if not platforms:
        platforms = sorted(PLATFORMS.keys())

    for version in python_versions:
        minor_version = _get_minor_version(version)
        underscore_version = version.replace(".", "_")

        version_info = TOOL_VERSIONS[minor_version]
        available_version_platforms = version_info["sha256"].keys()
        selected_platforms = [p for p in platforms if p in available_version_platforms]

        for target_platform in selected_platforms:
            env_platforms = _get_env_platforms(target_platform, glibc_version, macos_version)
            target_env_name = "python_{}_{}".format(minor_version, target_platform)
            target_env_json = target_env_name + ".json"

            environment_compatible_with = list(PLATFORMS[target_platform].compatible_with)
            if version == default_version:
                flag_values = {}
            else:
                flag_values = {"@rules_python//python/config_settings:python_version": minor_version}

            config_setting_name = "{}_config".format(target_env_name)
            environments.append(
                dict(
                    name = target_env_name,
                    output = target_env_json,
                    implementation = "cp",
                    config_setting_name = config_setting_name,
                    config_setting_target = "@{}//:{}".format(repo_name, config_setting_name),
                    version = minor_version,
                    python_compatible_with = environment_compatible_with,
                    flag_values = flag_values,
                    abis = [_get_abi(minor_version)],
                    platforms = env_platforms,
                ),
            )

            for exec_platform in selected_platforms:
                tc_provider_name = "python_{}_{}_{}".format(minor_version, exec_platform, target_platform)
                tc_target_config_name = "{}_target_config".format(tc_provider_name)
                tc_name = "{}_tc".format(tc_provider_name)

                exec_compatible_with = list(PLATFORMS[exec_platform].compatible_with)
                target_compatible_with = list(PLATFORMS[target_platform].compatible_with)

                # These conditionals create a `interpreter_repo_pattern` which accepts a
                # platform name (e.g., x86_64-unknown-linux-gnu).

                if BZLMOD:
                    # With bzlmod need to construct the canonical repository names for platform-specific interpreters.
                    # We assume that python_toolchains_repo_name points to the `python_versions` repo
                    # that rules_python generates. From there, we strip of `python_versions` and replace it with
                    # a toolchain repo name. E.g., python_3_12_x86_64-unknown-linux-gnu.
                    if not python_toolchains_repo_name.endswith("python_versions"):
                        fail(
                            "Expected python_toolchains_repo_name to end with 'python_versions', " +
                            "but it does not: " + python_toolchains_repo_name,
                        )
                    repo_name_prefix = python_toolchains_repo_name[:-len("python_versions")]
                    interpreter_repo_pattern = "@@{}python_{}_{{plat}}//:py3_runtime".format(
                        repo_name_prefix,
                        underscore_version,
                    )

                    # These other modes are WORKSPACE and should eventually be dropped.
                elif is_multi_version_layout:
                    interpreter_repo_pattern = "@{}_{}_{{plat}}//:py3_runtime".format(
                        python_toolchains_repo_name,
                        underscore_version,
                    )
                else:
                    interpreter_repo_pattern = "@{}_{{plat}}//:py3_runtime".format(python_toolchains_repo_name)

                exec_interpreter = interpreter_repo_pattern.format(plat = exec_platform)
                target_interpreter = interpreter_repo_pattern.format(plat = target_platform)

                if version == default_version:
                    flag_values = {}
                else:
                    flag_values = {"@rules_python//python/config_settings:python_version": minor_version}

                toolchains.append(
                    dict(
                        name = tc_name,
                        provider_name = tc_provider_name,
                        target_config_name = tc_target_config_name,
                        flag_values = flag_values,
                        exec_interpreter = exec_interpreter,
                        target_interpreter = target_interpreter,
                        exec_compatible_with = exec_compatible_with,
                        target_compatible_with = target_compatible_with,
                    ),
                )

    return dict(
        environments = environments,
        toolchains = toolchains,
    )

def _is_multi_version_layout(rctx, python_toolchain_repo):
    # Ideally we'd just check whether pip.bzl exists, but `path(Label(<non-existent-label>))`
    # unfortunately raises an exception.
    repo_build_file = python_toolchain_repo.relative("//:BUILD.bazel")
    repo_dir = rctx.path(repo_build_file).dirname
    return repo_dir.get_child("pip.bzl").exists

def _get_single_python_version(rctx, python_toolchain_repo):
    defs_bzl_file = python_toolchain_repo.relative("//:defs.bzl")
    content = rctx.read(defs_bzl_file)
    for line in content.splitlines():
        if line.strip().startswith("python_version"):
            # We found a line that is like `python_version = "3.11.6",`
            # Split by the equal sign and get the version.
            _, version_side = line.split("=")
            quoted_version = version_side.strip(" ,")
            version = quoted_version.strip("'\"")  # strip quotes
            return version

    fail("Unable to determine version from " + defs_bzl_file)

def _get_multi_python_versions(rctx, python_toolchain_repo):
    pip_bzl_file = python_toolchain_repo.relative("//:pip.bzl")
    content = rctx.read(pip_bzl_file)

    versions = []
    for line in content.splitlines():
        if line.strip().startswith("python_versions"):
            # We found a line that is like `python_versions = ["3.11.6", "3.12.0"],`
            # Split by the equal sign and parse the array.
            _, version_side = line.split("=")
            version_list = version_side.strip(" ,")
            version_list_contents = version_list.strip("[]")
            quoted_versions = version_list_contents.split(",")
            for version in quoted_versions:
                version = version.strip()  # strip whitespace
                version = version.strip("'\"")  # strip quotes
                versions.append(version)

            break

    if not versions:
        fail("Unable to determine versions from " + pip_bzl_file)

    return versions

def _get_default_python_version(rctx, python_toolchain_repo, versions):
    # Figure out the default version
    default_version = None
    for version in versions:
        underscore_version = version.replace(".", "_")
        toolchain_bzl_file = Label("@{}_{}_toolchains//:BUILD.bazel".format(python_toolchain_repo.workspace_name, underscore_version))
        content = rctx.read(toolchain_bzl_file)

        # Default version toolchains have empty target_settings lists.
        if "target_settings" not in content or "target_settings = []" in content:
            default_version = version
            break

    if not default_version:
        fail("Unable to determine default version for python toolchain repo '{}'".format(python_toolchain_repo))

    return default_version

_ROOT_BUILD_HEADER = """\
load("{}", "pycross_target_environment")

package(default_visibility = ["//visibility:public"])
""".format(Label("//pycross:defs.bzl"))

_TOOLCHAINS_BUILD_HEADER = """\
load("{}", "pycross_hermetic_toolchain")

package(default_visibility = ["//visibility:public"])
""".format(Label("//pycross:toolchain.bzl"))

_ENVIRONMENT_TEMPLATE = """\
config_setting(
    name = {config_setting_name},
    constraint_values = {python_compatible_with},
    flag_values = {flag_values},
)
"""

_TOOLCHAIN_TEMPLATE = """\
pycross_hermetic_toolchain(
    name = {provider_name},
    exec_interpreter = {exec_interpreter},
    target_interpreter = {target_interpreter},
)

config_setting(
    name = {target_config_name},
    constraint_values = {target_compatible_with},
    flag_values = {flag_values},
)

toolchain(
    name = {name},
    exec_compatible_with = {exec_compatible_with},
    target_settings = [{target_config_name}],
    toolchain = {provider_name},
    toolchain_type = "%s",
)
""" % Label("//pycross:toolchain_type")

def _get_requested_python_versions(rctx, registered_python_versions):
    """
    Returns Python versions filtered to what the user requested.
    """
    if not rctx.attr.requested_python_versions:
        return registered_python_versions

    not_found_python_versions = []
    python_versions = []
    for requested_version in rctx.attr.requested_python_versions:
        if requested_version in registered_python_versions:
            python_versions.append(requested_version)
        else:
            not_found_python_versions.append(requested_version)
    if not_found_python_versions:
        fail("Requested Python versions are not registered: {}".format(not_found_python_versions))

    return python_versions

def _pycross_toolchain_repo_impl(rctx):
    python_repo = rctx.attr.python_toolchains_repo
    is_multi_version_layout = _is_multi_version_layout(rctx, python_repo)
    if is_multi_version_layout:
        registered_python_versions = _get_multi_python_versions(rctx, python_repo)
        python_versions = _get_requested_python_versions(rctx, registered_python_versions)

        if rctx.attr.default_python_version:
            default_version = rctx.attr.default_python_version
        else:
            default_version = _get_default_python_version(rctx, python_repo, registered_python_versions)
    else:
        default_version = _get_single_python_version(rctx, python_repo)
        python_versions = [default_version]

    computed = _compute_environments_and_toolchains(
        repo_name = rctx.attr.name,
        python_toolchains_repo_name = python_repo.workspace_name,
        is_multi_version_layout = is_multi_version_layout,
        python_versions = python_versions,
        default_version = default_version,
        platforms = rctx.attr.platforms,
        glibc_version = rctx.attr.glibc_version,
        macos_version = rctx.attr.macos_version,
    )

    repo_batch_create_target_environments(rctx, computed["environments"])

    root_build_sections = [_ROOT_BUILD_HEADER]
    for env in computed["environments"]:
        root_build_sections.append(_ENVIRONMENT_TEMPLATE.format(**{k: repr(v) for k, v in env.items()}))

    root_build_sections.append("exports_files([")
    for env in computed["environments"]:
        root_build_sections.append("    {},".format(repr(env["output"])))
    root_build_sections.append("])")

    toolchains_build_sections = [_TOOLCHAINS_BUILD_HEADER]
    for tc in computed["toolchains"]:
        toolchains_build_sections.append(_TOOLCHAIN_TEMPLATE.format(**{k: repr(v) for k, v in tc.items()}))

    rctx.file(rctx.path("BUILD.bazel"), "\n".join(root_build_sections))
    rctx.file(rctx.path("toolchains/BUILD.bazel"), "\n".join(toolchains_build_sections))

    environment_names = ["@{}//:{}".format(rctx.attr.name, env["output"]) for env in computed["environments"]]
    defs_lines = ["environments = ["]
    for environment_name in environment_names:
        defs_lines.append("    {},".format(repr(environment_name)))
    defs_lines.append("]")

    rctx.file(rctx.path("defs.bzl"), "\n".join(defs_lines))

pycross_toolchain_repo = repository_rule(
    implementation = _pycross_toolchain_repo_impl,
    attrs = {
        "python_toolchains_repo": attr.label(),
        "requested_python_versions": attr.string_list(),
        "default_python_version": attr.string(),
        "platforms": attr.string_list(),
        "glibc_version": attr.string(mandatory = True),
        "macos_version": attr.string(mandatory = True),
    },
)

def pycross_register_for_python_toolchains(
        name,
        python_toolchains_repo,
        platforms = None,
        glibc_version = DEFAULT_GLIBC_VERSION,
        macos_version = DEFAULT_MACOS_VERSION):
    """
    Register target environments and toolchains for a given list of Python versions.

    Args:
        name: the toolchain repo name.
        python_toolchains_repo: a label to the registered rules_python tolchain repo.
        platforms: an optional list of platforms to support (e.g., "x86_64-unknown-linux-gnu").
            By default, all platforms supported by rules_python are registered.
        glibc_version: the maximum supported GLIBC version.
        macos_version: the maximum supported macOS version.
    """
    pycross_toolchain_repo(
        name = name,
        python_toolchains_repo = python_toolchains_repo,
        platforms = platforms,
        glibc_version = glibc_version,
        macos_version = macos_version,
    )

    native.register_toolchains("@{}//toolchains/...".format(name))
