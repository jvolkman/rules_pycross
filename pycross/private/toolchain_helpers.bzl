"""Helpers for creating Pycross environments and toolchains"""

load("@rules_python//python:versions.bzl", "MINOR_MAPPING", "PLATFORMS", "TOOL_VERSIONS")
load(":lock_attrs.bzl", "DEFAULT_GLIBC_VERSION", "DEFAULT_MACOS_VERSION", "DEFAULT_MUSL_VERSION")
load(":target_environment.bzl", "repo_batch_create_target_environments")
load(":util.bzl", "BZLMOD")

def _repo_label(repo_name, label):
    if BZLMOD:
        return "@@{}{}".format(repo_name, label)
    else:
        return "@{}{}".format(repo_name, label)

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
    if py_platform.endswith("linux-gnu"):
        return ["linux_{}".format(arch)] + [
            "manylinux_2_{}_{}".format(i, arch)
            for i in range(5, glibc_micro + 1)
        ]
    elif py_platform.endswith("linux-musl"):
        return [
            "musllinux_{}_{}_{}".format(musl_major, micro, arch)
            for micro in range(musl_micro, -1, -1)
        ]
    elif py_platform.endswith("darwin"):
        if arch == "aarch64":
            arch = "arm64"
        return ["macosx_{}_{}_{}".format(macos_major, macos_micro, arch)]
    elif py_platform.endswith("windows-msvc"):
        return ["win_amd64"]

    fail("Unknown platform: {}".format(py_platform))

def _dedupe_versions(versions):
    """Returns a list of versions deduped by resolved minor version."""

    # E.g., if '3.10' and '3.10.6' are both passed, we only want '3.10.6'. Otherwise we'll run into
    # ambiguous select() criteria.
    unique_versions = {}
    for version in sorted(versions):
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
        macos_version):
    environments = []

    if not platforms:
        platforms = sorted(PLATFORMS.keys())

    for version in _dedupe_versions(python_versions):
        micro_version = _get_micro_version(version)

        version_info = TOOL_VERSIONS[micro_version]
        available_version_platforms = version_info["sha256"].keys()
        selected_platforms = [p for p in platforms if p in available_version_platforms]

        for target_platform in selected_platforms:
            env_platforms = _get_env_platforms(target_platform, glibc_version, musl_version, macos_version)
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
                    version = micro_version,
                    abis = [_get_abi(micro_version)],
                    platforms = env_platforms,
                ),
            )

    return environments

def _compute_toolchains(
        python_toolchains_repo_name,
        is_multi_version_layout,
        python_versions):
    toolchains = []

    for version in _dedupe_versions(python_versions):
        micro_version = _get_micro_version(version)
        underscore_version = version.replace(".", "_")

        tc_provider_name = "python_{}".format(version)
        tc_target_config_name = "{}_target_config".format(tc_provider_name)
        tc_name = "{}_tc".format(tc_provider_name)

        if BZLMOD:
            # With bzlmod we need to construct the canonical repository names for version interpreters.
            runtime = "@@{}python_{}//:py3_runtime".format(
                _canonical_prefix(python_toolchains_repo_name),
                underscore_version,
            )
        elif is_multi_version_layout:
            # These other modes are WORKSPACE and should eventually be dropped.
            runtime = "@{}_{}//:py3_runtime".format(
                python_toolchains_repo_name,
                underscore_version,
            )
        else:
            runtime = "@{}//:py3_runtime".format(python_toolchains_repo_name)

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

def _get_default_python_version_bzlmod(rctx, pythons_hub_repo):
    # Check if Python hub repo has versions.bzl file. versions.bzl was introduced in rules_python 0.37.0.
    pythons_hub_build_file = pythons_hub_repo.relative("//:BUILD.bazel")
    pythons_hub_repo_dir = rctx.path(pythons_hub_build_file).dirname
    if pythons_hub_repo_dir.get_child("versions.bzl").exists:
        # Use versions.bzl for rules_python 0.37.0+.
        versions_bzl_file = Label("@@{}//:versions.bzl".format(pythons_hub_repo.workspace_name))
        content = rctx.read(versions_bzl_file)
    else:
        # Fall back to interpreters.bzl as versions.bzl does not exists for rules_python < 0.37.0.
        # DEFAULT_PYTHON_VERSION was removed from interpreters.bzl in rules_python 1.0.0.
        interpreters_bzl_file = Label("@@{}//:interpreters.bzl".format(pythons_hub_repo.workspace_name))
        content = rctx.read(interpreters_bzl_file)
    for line in content.splitlines():
        if line.startswith("DEFAULT_PYTHON_VERSION"):
            _, val = line.split("=")
            val = val.strip(" \"'")
            return val

    fail("Unable to determine default version for python hub repo '{}'".format(pythons_hub_repo))

def _get_default_python_version_workspace(rctx, python_toolchain_repo, versions):
    # Figure out the default version
    default_version = None
    for version in versions:
        underscore_version = version.replace(".", "_")
        toolchain_bzl_file = Label("@{}_{}_toolchains//:BUILD.bazel".format(python_toolchain_repo.workspace_name, underscore_version))
        content = rctx.read(toolchain_bzl_file)

        if "py_toolchain_suite" in content:
            # Handle rules_python 0.30+
            # Default version toolchains have set_python_version_constraint set to "False".
            for line in content.lower().splitlines():
                if "set_python_version_constraint" in line:
                    if "false" in line:
                        default_version = version
                    break
            if default_version:
                break

        else:
            # Handle rules_python versions prior to 0.30.
            # Default version toolchains have empty target_settings lists.
            if "target_settings" not in content or "target_settings = []" in content:
                default_version = version
                break

    if not default_version:
        fail("Unable to determine default version for python toolchain repo '{}'".format(python_toolchain_repo))

    return default_version

# This requires the user to provide a `default_version` value.
_ENVIRONMENTS_BUILD_HEADER = """\
load("{defs}", "pycross_target_environment")
load("{ver}", "rules_python_interpreter_version")

package(default_visibility = ["//visibility:public"])

rules_python_interpreter_version(
    name = "_interpreter_version",
    default_version = "{{default_version}}",
    visibility = ["//visibility:private"],
)
""".format(
    defs = Label("//pycross:defs.bzl"),
    ver = Label("//pycross/private:interpreter_version.bzl"),
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
    name = {config_setting_name},
    constraint_values = {target_compatible_with},
    flag_values = {{":_interpreter_version": {version}}} | {target_flag_values},
)
"""

# exec_interpreter and target_interpreter below are both set to the same
# target. We rely on `cfg = 'exec'` and `cfg = 'target'` in the
# pycross_hermetic_toolchain label definitions to pick the correct values.

_TOOLCHAIN_TEMPLATE = """\
pycross_hermetic_toolchain(
    name = {provider_name},
    exec_interpreter = {runtime},
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
    is_multi_version_layout = _is_multi_version_layout(rctx, python_repo)
    if is_multi_version_layout:
        registered_python_versions = _get_multi_python_versions(rctx, python_repo)
        python_versions = _get_requested_python_versions(rctx, registered_python_versions)

        if rctx.attr.pythons_hub_repo:
            default_version = _get_default_python_version_bzlmod(rctx, rctx.attr.pythons_hub_repo)
        else:
            default_version = _get_default_python_version_workspace(rctx, python_repo, registered_python_versions)
    else:
        default_version = _get_single_python_version(rctx, python_repo)
        python_versions = [default_version]

    return struct(
        python_versions = python_versions,
        default_version = default_version,
        default_micro_version = _get_micro_version(default_version),
        is_multi_version_layout = is_multi_version_layout,
    )

def _pycross_toolchain_repo_impl(rctx):
    version_info = _get_python_version_info(rctx)
    computed_toolchains = _compute_toolchains(
        python_toolchains_repo_name = rctx.attr.python_toolchains_repo.workspace_name,
        is_multi_version_layout = version_info.is_multi_version_layout,
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
    computed_environments = _compute_environments(
        repo_name = rctx.name,
        python_versions = version_info.python_versions,
        platforms = rctx.attr.platforms,
        glibc_version = rctx.attr.glibc_version or DEFAULT_GLIBC_VERSION,
        musl_version = rctx.attr.musl_version or DEFAULT_MUSL_VERSION,
        macos_version = rctx.attr.macos_version or DEFAULT_MACOS_VERSION,
    )

    repo_batch_create_target_environments(rctx, computed_environments)

    root_build_sections = [_ENVIRONMENTS_BUILD_HEADER.format(default_version = version_info.default_micro_version)]
    for env in computed_environments:
        root_build_sections.append(_ENVIRONMENT_TEMPLATE.format(**{k: repr(v) for k, v in env.items()}))

    root_build_sections.append("filegroup(")
    root_build_sections.append('    name = "environments",')
    root_build_sections.append("    srcs = [")
    for env in computed_environments:
        root_build_sections.append("        {},".format(repr(env["output"])))
    root_build_sections.append("    ]")
    root_build_sections.append(")")

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
    },
)

def pycross_register_for_python_toolchains(
        name,
        python_toolchains_repo,
        *,
        platforms = None,
        glibc_version = None,
        musl_verison = None,
        macos_version = None):
    """
    Register target environments and toolchains for a given list of Python versions.

    Args:
        name: the toolchain repo name.
        python_toolchains_repo: a label to the registered rules_python tolchain repo.
        platforms: an optional list of platforms to support (e.g., "x86_64-unknown-linux-gnu").
            By default, all platforms supported by rules_python are registered.
        glibc_version: the maximum supported GLIBC version.
        musl_verison: the maximum supported musl version.
        macos_version: the maximum supported macOS version.
    """
    toolchain_repo_name = "{}_toolchains".format(name)

    pycross_environments_repo(
        name = name,
        python_toolchains_repo = python_toolchains_repo,
        platforms = platforms,
        glibc_version = glibc_version,
        musl_version = musl_verison,
        macos_version = macos_version,
    )

    pycross_toolchains_repo(
        name = toolchain_repo_name,
        python_toolchains_repo = python_toolchains_repo,
        platforms = platforms,
    )

    native.register_toolchains("@{}_toolchains//...".format(name))
