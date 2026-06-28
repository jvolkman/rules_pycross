"""Supported tags rule and provider."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//pycross/private/pypackaging/tags:tags.bzl", "get_supported")
load(":pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "marker_value_attrs")

SupportedTagsInfo = provider(
    doc = "Provides a list of supported PEP 425 tags for the current environment.",
    fields = {
        "tags": "List of tag strings, ordered by preference (most preferred first).",
    },
)

def _flag_value(target):
    """Read a flag value from either FeatureFlagInfo or BuildSettingInfo."""
    if config_common.FeatureFlagInfo in target:
        return target[config_common.FeatureFlagInfo].value
    if BuildSettingInfo in target:
        return target[BuildSettingInfo].value
    return ""

def _pycross_supported_tags_impl(ctx):
    markers = collect_markers(ctx)
    python_version = markers["python_version"]
    if not python_version:
        fail("python_version is required")

    version_nodot = python_version.replace(".", "")

    impl_name = markers["implementation_name"]
    impl_prefix_map = {
        "cpython": "cp",
        "pypy": "pp",
    }
    impl_prefix = impl_prefix_map.get(impl_name, "cp")

    freethreaded = ctx.attr.freethreaded == "yes"

    # Derive ABI
    if impl_prefix == "cp":
        abi = impl_prefix + version_nodot
        if freethreaded:
            abi += "t"
        abis = [abi]
    else:
        abis = ["none"]

    # Synthesize platform
    sys_platform = markers["sys_platform"]
    platform_machine = markers["platform_machine"]

    # Map architecture if needed
    arch = platform_machine
    if sys_platform == "darwin" and arch == "aarch64":
        arch = "arm64"
    elif sys_platform == "linux" and arch == "arm64":
        arch = "aarch64"

    platforms = []

    if sys_platform == "linux":
        if ctx.attr.libc == "glibc":
            max_glibc = _flag_value(ctx.attr._max_glibc_version) or "2.17"
            version = max_glibc.split(".")
            minor = version[1] if len(version) > 1 else "17"
            platforms.append("manylinux_{}_{}_{}".format(version[0], minor, arch))
        elif ctx.attr.libc == "musl":
            max_musl = _flag_value(ctx.attr._max_musl_version) or "1.2"
            version = max_musl.split(".")
            minor = version[1] if len(version) > 1 else "2"
            platforms.append("musllinux_{}_{}_{}".format(version[0], minor, arch))
        else:
            platforms.append("linux_" + arch)
    elif sys_platform == "darwin":
        macos_ver = _flag_value(ctx.attr._max_macos_version) or markers["platform_version"] or "11.0"
        version = macos_ver.split(".")
        major = version[0]
        minor = version[1] if len(version) > 1 else "0"
        platforms.append("macosx_{}_{}_{}".format(major, minor, arch))
    elif sys_platform == "win32":
        if arch in ("x86_64", "amd64"):
            platforms.append("win_amd64")
        elif arch in ("x86", "i386", "i686"):
            platforms.append("win32")
        elif arch == "arm64":
            platforms.append("win_arm64")
        else:
            platforms.append(arch)
    else:
        platforms.append("any")

    tags = get_supported(
        version = version_nodot,
        platforms = platforms,
        impl = impl_prefix,
        abis = abis,
    )

    # Generate JSON for TargetEnv compatibility
    target_env_data = {
        "name": ctx.label.name,
        "implementation": impl_prefix,
        "version": python_version,
        "abis": abis,
        "platforms": platforms,
        "compatibility_tags": tags,
        "markers": markers,
        "python_compatible_with": [],
        "flag_values": {},
    }

    out_json = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(
        output = out_json,
        content = json.encode(target_env_data),
    )

    return [
        SupportedTagsInfo(tags = tags),
        DefaultInfo(files = depset([out_json])),
    ]

_pycross_supported_tags = rule(
    implementation = _pycross_supported_tags_impl,
    attrs = {
        "libc": attr.string(
            default = "",
            doc = "The host libc variant: 'glibc', 'musl', or '' (unknown/non-Linux).",
        ),
        "freethreaded": attr.string(
            default = "no",
            doc = "'yes' if the host Python is freethreaded, 'no' otherwise.",
        ),
        "_max_glibc_version": attr.label(default = "@rules_pycross//pycross/settings:max_glibc_version"),
        "_max_macos_version": attr.label(default = "@rules_pycross//pycross/settings:max_macos_version"),
        "_max_musl_version": attr.label(default = "@rules_pycross//pycross/settings:max_musl_version"),
    } | marker_value_attrs(),
    provides = [SupportedTagsInfo],
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
)

def pycross_supported_tags(name, **kwargs):
    _pycross_supported_tags(name = name, **kwargs)
