"""Helpers for creating Pycross environments and toolchains"""

load("@rules_python//python:versions.bzl", "MINOR_MAPPING", "PLATFORMS", "TOOL_VERSIONS")
load(":lock_attrs.bzl", "DEFAULT_GLIBC_VERSION", "DEFAULT_MACOS_VERSION", "DEFAULT_MUSL_VERSION")
load(":target_environment.bzl", "repo_batch_create_target_environments")

def _repo_label(repo_name, label):
    return "@@{}{}".format(repo_name, label)

def _get_micro_version(version):
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
    major, micro = _get_version_components(version)
    return "cp{}{}".format(major, micro)

def _get_env_platforms(py_platform, glibc_version, musl_version, macos_version):
    glibc_major, glibc_micro = _get_version_components(glibc_version)
    musl_major, musl_micro = _get_version_components(musl_version)
    macos_major, macos_micro = _get_version_components(macos_version)

    if macos_major < 10:
        fail("macos version must be >= 10")
    if (glibc_major, glibc_micro) < (2, 5) or (glibc_major, glibc_micro) >= (3, 0):
        fail("glibc version must be >= 2.5 and < 3.0")

    platform_info = PLATFORMS[py_platform]
    arch = platform_info.arch
    if py_platform.endswith("linux-gnu") or py_platform.endswith("linux-gnu-freethreaded"):
        # Emit modern manylinux tags newest-first; the target environment
        # generator will insert legacy aliases (e.g. manylinux2014_x86_64)
        # immediately after their modern equivalents.
        return ["linux_{}".format(arch)] + [
            "manylinux_2_{}_{}".format(i, arch)
            for i in range(glibc_micro, 4, -1)
        ]
    elif py_platform.endswith("linux-musl"):
        return [
            "musllinux_{}_{}_{}".format(musl_major, micro, arch)
            for micro in range(musl_micro, -1, -1)
        ]
    elif py_platform.endswith("darwin") or py_platform.endswith("darwin-freethreaded"):
        if arch == "aarch64":
            arch = "arm64"
        return ["macosx_{}_{}_{}".format(macos_major, macos_micro, arch)]
    elif py_platform.endswith("windows-msvc") or py_platform.endswith("windows-msvc-freethreaded"):
        return ["win_amd64"]

    fail("Unknown platform: {}".format(py_platform))

def _dedupe_versions(versions):
    """Returns a list of versions deduped by resolved minor version."""

    # E.g., if '3.10' and '3.10.6' are both passed, we only want '3.10.6'. Otherwise we'll run into
    # ambiguous select() criteria.
    unique_versions = {}
    for version in sorted(versions):
        # Skip versions not known to this rules_python release (e.g. EOL Python 3.8 was removed
        # from MINOR_MAPPING in rules_python 1.9.0 but still appears in the python_versions hub's
        # pip.bzl because that file lists all historically-supported versions).
        if version not in MINOR_MAPPING and version not in TOOL_VERSIONS:
            continue

        micro_version = _get_micro_version(version)

        # In sorted order, 3.10.6 will override 3.10.
        unique_versions[micro_version] = version

    return sorted(unique_versions.values())

def _canonical_prefix(python_toolchains_repo_name):
    # We assume that python_toolchains_repo_name points to the `python_versions` repo
    # that rules_python generates. From there, we strip of `python_versions` and return
    # the remainder as the prefix.
    if not python_toolchains_repo_name.endswith("python_versions"):
        fail(
            "Expected python_toolchains_repo_name to end with 'python_versions', " +
            "but it does not: " + python_toolchains_repo_name,
        )
    return python_toolchains_repo_name[:-len("python_versions")]

def _compute_environments(
        repo_name,
        python_versions,
        platforms,
        glibc_version,
        musl_version,
        macos_version,
        platform_configs = None):
    """Compute pycross target environments.

    Args:
        repo_name: the repository name.
        python_versions: list of Python versions.
        platforms: list of platform triples (used when platform_configs is None).
        glibc_version: default glibc version.
        musl_version: default musl version.
        macos_version: default macOS version.
        platform_configs: optional list of structs with per-platform overrides.
            Each struct has: target (str), glibc_version (str or None),
            musl_version (str or None), macos_version (str or None).
            When provided, 'platforms' must be empty.

    Returns:
        list of environment dicts.
    """
    environments = []

    # Build the list of (platform_triple, glibc, musl, macos) tuples.
    if platform_configs:
        platform_entries = [
            (
                pc["target"],
                pc.get("glibc_version") or glibc_version,
                pc.get("musl_version") or musl_version,
                pc.get("macos_version") or macos_version,
            )
            for pc in platform_configs
        ]
    else:
        if not platforms:
            platforms = sorted(PLATFORMS.keys())
        platform_entries = [
            (p, glibc_version, musl_version, macos_version)
            for p in platforms
        ]

    for version in _dedupe_versions(python_versions):
        micro_version = _get_micro_version(version)

        version_info = TOOL_VERSIONS[micro_version]
        available_version_platforms = version_info["sha256"].keys()

        for target_platform, plat_glibc, plat_musl, plat_macos in platform_entries:
            if target_platform not in available_version_platforms:
                continue

            env_platforms = _get_env_platforms(target_platform, plat_glibc, plat_musl, plat_macos)
            target_env_name = "python_{}_{}".format(version, target_platform)
            target_env_json = target_env_name + ".json"

            config_setting_name = "{}_config".format(target_env_name)
            environments.append(
                dict(
                    name = target_env_name,
                    output = target_env_json,
                    implementation = "cp",
                    config_setting_name = config_setting_name,
                    config_setting_target = _repo_label(repo_name, "//:{}".format(config_setting_name)),
                    target_compatible_with = list(PLATFORMS[target_platform].compatible_with),
                    target_flag_values = {str(key): val for key, val in PLATFORMS[target_platform].flag_values.items()},
                    target_settings = getattr(PLATFORMS[target_platform], "target_settings", []),
                    version = micro_version,
                    abis = [_get_abi(micro_version)],
                    platforms = env_platforms,
                ),
            )

    return environments

def _compute_toolchains(
        python_toolchains_repo_name,
        python_versions):
    toolchains = []

    for version in _dedupe_versions(python_versions):
        micro_version = _get_micro_version(version)
        underscore_version = version.replace(".", "_")

        tc_provider_name = "python_{}".format(version)
        tc_target_config_name = "{}_target_config".format(tc_provider_name)
        tc_name = "{}_tc".format(tc_provider_name)

        runtime = "@@{}python_{}//:py3_runtime".format(
            _canonical_prefix(python_toolchains_repo_name),
            underscore_version,
        )

        toolchains.append(
            dict(
                name = tc_name,
                provider_name = tc_provider_name,
                target_config_name = tc_target_config_name,
                runtime = runtime,
                version = micro_version,
            ),
        )
    return toolchains

def _get_registered_python_versions(rctx, python_toolchain_repo):
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

def _get_default_python_version(rctx, pythons_hub_repo):
    if not pythons_hub_repo:
        fail("Must provide python_hub_repo.")
    versions_bzl_file = Label("@@{}//:versions.bzl".format(pythons_hub_repo.workspace_name))
    content = rctx.read(versions_bzl_file)
    for line in content.splitlines():
        if line.startswith("DEFAULT_PYTHON_VERSION"):
            _, val = line.split("=")
            val = val.strip(" \"'")
            return val

    fail("Unable to determine default version for python hub repo '{}'".format(pythons_hub_repo))

# This requires the user to provide a `default_version` value.
_ENVIRONMENTS_BUILD_HEADER = """\
load("{defs}", "pycross_target_environment")
load("{ver}", "rules_python_interpreter_version")
load("{skylib_selects}", "selects")

package(default_visibility = ["//visibility:public"])

rules_python_interpreter_version(
    name = "_interpreter_version",
    default_version = "{{default_version}}",
    visibility = ["//visibility:private"],
)
""".format(
    defs = Label("//pycross:defs.bzl"),
    ver = Label("//pycross/private:interpreter_version.bzl"),
    skylib_selects = Label("@bazel_skylib//lib:selects.bzl"),
)

# This requires the user to provide a `default_version` value.
_TOOLCHAINS_BUILD_HEADER = """\
load("{toolchain}", "pycross_hermetic_toolchain")
load("{ver}", "rules_python_interpreter_version")

package(default_visibility = ["//visibility:public"])

rules_python_interpreter_version(
    name = "_interpreter_version",
    default_version = "{{default_version}}",
    visibility = ["//visibility:private"],
)
""".format(
    toolchain = Label("//pycross:toolchain.bzl"),
    ver = Label("//pycross/private:interpreter_version.bzl"),
)

_ENVIRONMENT_TEMPLATE = """\
config_setting(
    name = {config_setting_name} + "_inner",
    constraint_values = {target_compatible_with},
    flag_values = {{":_interpreter_version": {version}}} | {target_flag_values},
)

selects.config_setting_group(
    name = {config_setting_name},
    match_all = [{config_setting_name} + "_inner"] + {target_settings},
)
"""

# exec_interpreter and target_interpreter below are both set to the same
# target. We rely on `cfg = 'exec'` and `cfg = 'target'` in the
# pycross_hermetic_toolchain label definitions to pick the correct values.

_TOOLCHAIN_TEMPLATE = """\
pycross_hermetic_toolchain(
    name = {provider_name},
    exec_interpreter = "@rules_python//python:current_py_toolchain",
    target_interpreter = {runtime},
)

config_setting(
    name = {target_config_name},
    flag_values = {{":_interpreter_version": {version}}},
)

toolchain(
    name = {name},
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
        fail("Requested Python versions are not registered: {} (registered versions: {})".format(not_found_python_versions, registered_python_versions))

    return python_versions

def _get_python_version_info(rctx):
    """
    Returns a struct containing python versions and the default interpreter version.
    """
    python_repo = rctx.attr.python_toolchains_repo
    registered_python_versions = _get_registered_python_versions(rctx, python_repo)
    python_versions = _get_requested_python_versions(rctx, registered_python_versions)

    default_version = _get_default_python_version(rctx, rctx.attr.pythons_hub_repo)

    return struct(
        python_versions = python_versions,
        default_version = default_version,
        default_micro_version = _get_micro_version(default_version),
    )

def _pycross_toolchain_repo_impl(rctx):
    version_info = _get_python_version_info(rctx)
    computed_toolchains = _compute_toolchains(
        python_toolchains_repo_name = rctx.attr.python_toolchains_repo.workspace_name,
        python_versions = version_info.python_versions,
    )

    toolchains_build_sections = [_TOOLCHAINS_BUILD_HEADER.format(default_version = version_info.default_micro_version)]
    for tc in computed_toolchains:
        toolchains_build_sections.append(_TOOLCHAIN_TEMPLATE.format(**{k: repr(v) for k, v in tc.items()}))

    rctx.file(rctx.path("BUILD.bazel"), "\n".join(toolchains_build_sections))

pycross_toolchains_repo = repository_rule(
    implementation = _pycross_toolchain_repo_impl,
    attrs = {
        "python_toolchains_repo": attr.label(),
        "pythons_hub_repo": attr.label(),
        "requested_python_versions": attr.string_list(),
        "platforms": attr.string_list(),
    },
)

def _pycross_environment_repo_impl(rctx):
    version_info = _get_python_version_info(rctx)
    platform_configs = json.decode(rctx.attr.platform_configs) if rctx.attr.platform_configs else None
    computed_environments = _compute_environments(
        repo_name = rctx.name,
        python_versions = version_info.python_versions,
        platforms = rctx.attr.platforms,
        glibc_version = rctx.attr.glibc_version or DEFAULT_GLIBC_VERSION,
        musl_version = rctx.attr.musl_version or DEFAULT_MUSL_VERSION,
        macos_version = rctx.attr.macos_version or DEFAULT_MACOS_VERSION,
        platform_configs = platform_configs,
    )

    repo_batch_create_target_environments(rctx, computed_environments)

    root_build_sections = [_ENVIRONMENTS_BUILD_HEADER.format(default_version = version_info.default_micro_version)]
    for env in computed_environments:
        root_build_sections.append(_ENVIRONMENT_TEMPLATE.format(**{k: repr(v) for k, v in env.items()}))

    root_build_sections.append("# A convenience config_setting_group to allow users to declare compatibility with")
    root_build_sections.append("# any platform with a pycross environment configured.")
    root_build_sections.append("selects.config_setting_group(")
    root_build_sections.append('    name = "any_environment",')
    root_build_sections.append("    match_any = [")
    for env in computed_environments:
        root_build_sections.append("        {},".format(repr(env["config_setting_name"])))
    root_build_sections.append("    ],")
    root_build_sections.append(")")

    root_build_sections.append("filegroup(")
    root_build_sections.append('    name = "environments",')
    root_build_sections.append("    srcs = [")
    for env in computed_environments:
        root_build_sections.append("        {},".format(repr(env["output"])))
    root_build_sections.append("    ]")
    root_build_sections.append(")")

    root_build_sections.append("# Automatically resolves to the target environment JSON based on target config.")
    root_build_sections.append("filegroup(")
    root_build_sections.append('    name = "current",')
    root_build_sections.append("    srcs = select({")
    for env in computed_environments:
        root_build_sections.append("        {}: [{}],".format(repr(":" + env["config_setting_name"]), repr(":" + env["output"])))
    root_build_sections.append('        "//conditions:default": [],')
    root_build_sections.append("    }),")
    root_build_sections.append("    visibility = [\"//visibility:public\"],")
    root_build_sections.append(")")
    root_build_sections.append("exports_files(glob([\"*.json\"]))")

    rctx.file(rctx.path("BUILD.bazel"), "\n".join(root_build_sections))

    defs_lines = ["environments = ["]
    for env in computed_environments:
        defs_lines.append('    Label("//:{}"),'.format(env["output"]))
    defs_lines.append("]")

    rctx.file(rctx.path("defs.bzl"), "\n".join(defs_lines))

    index_struct = {
        "environments": [
            "//:{}".format(env["output"])
            for env in computed_environments
        ],
    }
    rctx.file(rctx.path("environments"), json.encode_indent(index_struct, indent = "  ") + "\n")

pycross_environments_repo = repository_rule(
    implementation = _pycross_environment_repo_impl,
    attrs = {
        "python_toolchains_repo": attr.label(),
        "pythons_hub_repo": attr.label(),
        "requested_python_versions": attr.string_list(),
        "platforms": attr.string_list(),
        "glibc_version": attr.string(),
        "musl_version": attr.string(),
        "macos_version": attr.string(),
        "platform_configs": attr.string(
            doc = "JSON-encoded list of per-platform version overrides.",
        ),
    },
)
