"""Helpers for creating Pycross environments and toolchains"""
load("@rules_python//python:versions.bzl", "MINOR_MAPPING", "PLATFORMS", "TOOL_VERSIONS")


DEFAULT_MACOS_VERSION = "12.0"
DEFAULT_GLIBC_VERSION = "2.25"


def _get_minor_version(version):
    if version in MINOR_MAPPING:
        return MINOR_MAPPING[version]
    elif version in TOOL_VERSIONS:
        return version

    fail("Unknown Python version: {}".format(version))


def _get_version_components(version):
    parts = version.split(".")
    if len(parts) < 2:
        fail("Invalid Python version; must be format X.Y or X.Y.Z: {}".format(version))
    
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
            "manylinux_2_{}_{}".format(i, arch) for i in range(5, glibc_minor + 1)
        ]
    elif py_platform.endswith("darwin"):
        return ["macosx_{}_{}_{}".format(macos_major, macos_minor, arch)]
    elif py_platform.endswith("windows-msvc"):
        return ["win_amd64"]

    fail("Unknown platform: {}".format(py_platform))


def _compute_environments_and_toolchains(
    python_toolchain_name,
    python_versions,
    platforms,
    glibc_version,
    macos_version,
):
    environments = []
    toolchains = []

    if platforms == None:
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

            environment_compatible_with = list(PLATFORMS[target_platform].compatible_with)
            environments.append(
                dict(
                    name = target_env_name,
                    python_version = minor_version,
                    python_compatible_with = environment_compatible_with,
                    version = minor_version,
                    abis = [_get_abi(minor_version)],
                    platforms = env_platforms,
                )
            )

            for exec_platform in selected_platforms:
                tc_provider_name = "python_{}_{}_{}".format(minor_version, exec_platform, target_platform)
                tc_target_config_name = "{}_target_config".format(tc_provider_name)
                tc_name = "{}_tc".format(tc_provider_name)

                exec_compatible_with = list(PLATFORMS[exec_platform].compatible_with)
                target_compatible_with = list(PLATFORMS[target_platform].compatible_with)

                exec_interpreter = "@{}_{}_{}//:py3_runtime".format(
                    python_toolchain_name,
                    underscore_version,
                    exec_platform,
                )

                target_interpreter = "@{}_{}_{}//:py3_runtime".format(
                    python_toolchain_name,
                    underscore_version,
                    target_platform,
                )

                toolchains.append(
                    dict(
                        name = tc_name,
                        provider_name = tc_provider_name,
                        target_config_name = tc_target_config_name,
                        exec_interpreter = exec_interpreter,
                        target_interpreter = target_interpreter,
                        target_environment = target_env_name,

                        exec_compatible_with = exec_compatible_with,
                        target_compatible_with = target_compatible_with,
                        python_version = minor_version,
                    )
                )

    return dict(
        environments = environments,
        toolchains = toolchains,
    )

_BUILD_HEADER = """\
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_target_environment")
load("@jvolkman_rules_pycross//pycross:toolchain.bzl", "pycross_hermetic_toolchain")

package(default_visibility = ["//visibility:public"])
"""

_ENVIRONMENT_TEMPLATE = """\
pycross_target_environment(
    name = {name},
    python_compatible_with = {python_compatible_with},
    flag_values = {{"@rules_python//python/config_settings:python_version": {python_version}}},
    version = {version},
    abis = {abis},
    platforms = {platforms},
)
"""

_TOOLCHAIN_TEMPLATE = """\
pycross_hermetic_toolchain(
    name = {provider_name},
    exec_interpreter = {exec_interpreter},
    target_environment = {target_environment},
    target_interpreter = {target_interpreter},
)

config_setting(
    name = {target_config_name},
    constraint_values = {target_compatible_with},
    flag_values = {{"@rules_python//python/config_settings:python_version": {python_version}}},
)

toolchain(
    name = {name},
    exec_compatible_with = {exec_compatible_with},
    target_settings = [{target_config_name}],
    toolchain = {provider_name},
    toolchain_type = "@jvolkman_rules_pycross//pycross:toolchain_type",
)
"""

def _pycross_toolchain_repo_impl(rctx):
    computed = _compute_environments_and_toolchains(
        python_toolchain_name = rctx.attr.python_toolchain_name,
        python_versions = rctx.attr.python_versions,
        platforms = rctx.attr.platforms,
        glibc_version = rctx.attr.glibc_version,
        macos_version = rctx.attr.macos_version,
    )

    build_sections = [_BUILD_HEADER]
    for env in computed["environments"]:
        build_sections.append(_ENVIRONMENT_TEMPLATE.format(**{k: repr(v) for k, v in env.items()}))

    for tc in computed["toolchains"]:
        build_sections.append(_TOOLCHAIN_TEMPLATE.format(**{k: repr(v) for k, v in tc.items()}))

    rctx.file(rctx.path("BUILD.bazel"), "\n".join(build_sections))

    environment_names = ["@{}//:{}".format(rctx.attr.name, env["name"]) for env in computed["environments"]]
    defs_lines = ["environments = ["]
    for environment_name in environment_names:
        defs_lines.append("    {},".format(repr(environment_name)))
    defs_lines.append("]")

    rctx.file(rctx.path("defs.bzl"), "\n".join(defs_lines))


_pycross_toolchain_repo = repository_rule(
    implementation = _pycross_toolchain_repo_impl,
    attrs = {
        "python_toolchain_name": attr.string(mandatory = True),
        "python_versions": attr.string_list(mandatory = True),
        "platforms": attr.string_list(),
        "glibc_version": attr.string(mandatory = True),
        "macos_version": attr.string(mandatory = True),
    },
)

def pycross_register_toolchains(
    name,
    python_toolchain_name,
    python_versions,
    platforms = None,
    glibc_version = DEFAULT_GLIBC_VERSION,
    macos_version = DEFAULT_MACOS_VERSION,
):
    """
    Register target environments and toolchains for a given list of Python versions.

    Args:
        name: the toolchain repo name.
        python_toolchain_name: the repo name of the registered rules_python tolchain repo.
        python_versions: the list of Python versions registered with rules_python.
        platforms: an optional list of platforms to support (e.g., "x86_64-unknown-linux-gnu").
            By default, all platforms supported by rules_python are registered.
        glibc_version: the maximum supported GLIBC version.
        macos_version: the maximum supported macOS version.
    """
    compute_params = dict(
        python_toolchain_name = python_toolchain_name,
        python_versions = python_versions,
        platforms = platforms,
        glibc_version = glibc_version,
        macos_version = macos_version,
    )

    _pycross_toolchain_repo(
        name = name,
        **compute_params,
    )

    computed = _compute_environments_and_toolchains(**compute_params)
    toolchain_names = ["@{}//:{}".format(name, tc["name"]) for tc in computed["toolchains"]]
    native.register_toolchains(*toolchain_names)
