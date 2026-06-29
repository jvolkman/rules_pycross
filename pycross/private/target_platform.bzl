"""Supported tags rule and provider."""

load("@pypackaging.bzl", "pypackaging")
load(":pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "flag_value", "marker_value_attrs")

PycrossTargetPlatformInfo = provider(
    doc = "Provides information about the target platform.",
    fields = {
        "name": "The name of the target platform.",
        "implementation": "The Python implementation prefix (e.g., 'cp', 'pp').",
        "version": "The Python version string.",
        "abis": "List of compatible ABIs.",
        "platforms": "List of compatible platforms.",
        "compatibility_tags": "List of compatible PEP 425 tags, ordered by preference.",
        "markers": "Dict of PEP 508 markers.",
    },
)

def _pycross_target_platform_impl(ctx):
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

    platforms = ctx.attr.platforms
    if not platforms:
        platforms = []

        if sys_platform == "linux":
            if ctx.attr.libc == "glibc":
                # Defensive fallback; should not be needed since the string_flag
                # default is populated from configure_toolchains().
                max_glibc = flag_value(ctx.attr._max_glibc_version) or "2.28"
                version = max_glibc.split(".")
                minor = version[1] if len(version) > 1 else "17"
                platforms.append("manylinux_{}_{}_{}".format(version[0], minor, arch))
            elif ctx.attr.libc == "musl":
                # Defensive fallback; see comment above.
                max_musl = flag_value(ctx.attr._max_musl_version) or "1.2"
                version = max_musl.split(".")
                minor = version[1] if len(version) > 1 else "2"
                platforms.append("musllinux_{}_{}_{}".format(version[0], minor, arch))
            else:
                platforms.append("linux_" + arch)
        elif sys_platform == "darwin":
            # Defensive fallback chain; flag default comes from configure_toolchains().
            macos_ver = flag_value(ctx.attr._max_macos_version) or markers["platform_version"] or "15.0"
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

    tags = pypackaging.tags.get_supported(
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
    }

    out_json = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(
        output = out_json,
        content = json.encode(target_env_data),
    )

    return [
        PycrossTargetPlatformInfo(
            name = ctx.label.name,
            implementation = impl_prefix,
            version = python_version,
            abis = abis,
            platforms = platforms,
            compatibility_tags = tags,
            markers = markers,
        ),
        DefaultInfo(files = depset([out_json])),
    ]

_pycross_target_platform = rule(
    implementation = _pycross_target_platform_impl,
    attrs = {
        "platforms": attr.string_list(
            doc = "Explicit list of PEP 425 platform tags. If set, libc and freethreaded are ignored for platform derivation.",
        ),
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
    provides = [PycrossTargetPlatformInfo],
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
)

def pycross_target_platform(name, **kwargs):
    _pycross_target_platform(name = name, **kwargs)
