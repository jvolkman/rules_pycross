"""Helpers for creating Pycross environments and toolchains"""

load("@rules_python//python:versions.bzl", "MINOR_MAPPING", "TOOL_VERSIONS")

def _get_micro_version(version):
    if version in MINOR_MAPPING:
        return MINOR_MAPPING[version]
    elif version in TOOL_VERSIONS:
        return version

    fail("Unknown Python version: {}".format(version))

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
