"""Constants mapping @platforms constraint values to PEP 508 marker values.

These dicts are intended for use in select() expressions at call sites for
rules that evaluate PEP 508 environment markers (e.g. _pycross_pep508_evaluator,
_pycross_wheel_chooser).

Python version markers (python_version, python_full_version, implementation_name)
are automatically derived from the rules_python toolchain configuration when
not explicitly provided.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

# Maps @platforms//os constraint values to PEP 508 sys_platform values.
# Synced with rules_python's pep508_env.bzl sys_platform_select_map.
SYS_PLATFORM_VALUES = {
    "@platforms//os:android": "android",
    "@platforms//os:emscripten": "emscripten",
    "@platforms//os:freebsd": "freebsd",
    "@platforms//os:ios": "ios",
    "@platforms//os:linux": "linux",
    "@platforms//os:openbsd": "openbsd",
    "@platforms//os:osx": "darwin",
    "@platforms//os:wasi": "wasi",
    "@platforms//os:windows": "win32",
    "//conditions:default": "",
}

# Maps @platforms//os constraint values to PEP 508 os_name values.
# Synced with rules_python's pep508_env.bzl os_name_select_map.
# Everything non-Windows is "posix" (including the default).
OS_NAME_VALUES = {
    "@platforms//os:windows": "nt",
    "//conditions:default": "posix",
}

# Maps @platforms//os constraint values to PEP 508 platform_system values.
# Synced with rules_python's pep508_env.bzl platform_system_select_map.
PLATFORM_SYSTEM_VALUES = {
    "@platforms//os:android": "Android",
    "@platforms//os:freebsd": "FreeBSD",
    "@platforms//os:ios": "iOS",
    "@platforms//os:linux": "Linux",
    "@platforms//os:netbsd": "NetBSD",
    "@platforms//os:openbsd": "OpenBSD",
    "@platforms//os:osx": "Darwin",
    "@platforms//os:windows": "Windows",
    "//conditions:default": "",
}

# Maps platform constraints to PEP 508 platform_machine values.
# Synced with rules_python's pep508_env.bzl platform_machine_select_map,
# with one important difference: aarch64 handling.
#
# Python's platform.machine() reports different values for aarch64 depending
# on the OS: "aarch64" on Linux/Android, "arm64" on macOS/iOS, "ARM64" on
# Windows. We use compound config_settings (OS + CPU) from
# //pycross/private:BUILD.bazel to resolve the correct value.
# rules_python maps aarch64 uniformly to "aarch64" regardless of OS.
#
# All other architectures have consistent names across OSes.
PLATFORM_MACHINE_VALUES = {
    # OS-specific aarch64 handling (more correct than rules_python).
    "@rules_pycross//pycross/private:is_linux_aarch64": "aarch64",
    "@rules_pycross//pycross/private:is_macos_aarch64": "arm64",
    "@rules_pycross//pycross/private:is_windows_aarch64": "ARM64",
    # All other CPUs.
    "@platforms//cpu:aarch32": "aarch32",
    "@platforms//cpu:armv7": "armv7",
    "@platforms//cpu:i386": "i386",
    "@platforms//cpu:ppc": "ppc",
    "@platforms//cpu:ppc64le": "ppc64le",
    "@platforms//cpu:riscv64": "riscv64",
    "@platforms//cpu:s390x": "s390x",
    "@platforms//cpu:wasm32": "wasm32",
    "@platforms//cpu:wasm64": "wasm64",
    "@platforms//cpu:x86_32": "x86_32",
    "@platforms//cpu:x86_64": "x86_64",
    "//conditions:default": "",
}

# Maps rules_python libc flag to a libc identifier.
# Used by the wheel chooser to distinguish manylinux vs musllinux wheels.
LIBC_VALUES = {
    "@rules_python//python/config_settings:_is_py_linux_libc_glibc": "glibc",
    "@rules_python//python/config_settings:_is_py_linux_libc_musl": "musl",
    "//conditions:default": "",
}

# Maps rules_python freethreaded flag to a boolean-like string.
# Used by the wheel chooser to match cp313t (freethreaded) vs cp313 tags.
FREETHREADED_VALUES = {
    "@rules_python//python/config_settings:_is_py_freethreaded_yes": "yes",
    "@rules_python//python/config_settings:_is_py_freethreaded_no": "no",
    "//conditions:default": "no",
}

PYTHON_TOOLCHAIN_TYPE = Label("@rules_python//python:toolchain_type")

def flag_value(target):
    """Read a flag value from either FeatureFlagInfo or BuildSettingInfo.

    Args:
        target: A target providing FeatureFlagInfo or BuildSettingInfo.

    Returns:
        The string value of the flag, or empty string if neither provider is found.
    """
    if config_common.FeatureFlagInfo in target:
        return target[config_common.FeatureFlagInfo].value
    if BuildSettingInfo in target:
        return target[BuildSettingInfo].value
    return ""

def _format_full_version(version_info):
    """Format a full version string from interpreter_version_info.

    Follows the same logic as rules_python's env_marker_setting.
    """
    kind = version_info.releaselevel
    if kind == "final":
        kind = ""
        serial = ""
    else:
        kind = kind[0] if kind else ""
        serial = str(version_info.serial) if version_info.serial else ""

    return "{major}.{minor}.{micro}{kind}{serial}".format(
        major = version_info.major,
        minor = version_info.minor,
        micro = version_info.micro,
        kind = kind,
        serial = serial,
    )

def marker_value_attrs():
    """Returns default attr values for PEP 508 marker dimensions.

    Rules using these attrs should also declare:
        toolchains = [PYTHON_TOOLCHAIN_TYPE]

    Usage in a rule definition:
        _my_rule = rule(
            attrs = {
                "expr": attr.string(),
            } | marker_value_attrs(),
            toolchains = [PYTHON_TOOLCHAIN_TYPE],
        )
    """
    return {
        "os_name": attr.string(default = ""),
        "sys_platform": attr.string(default = ""),
        "platform_machine": attr.string(default = ""),
        "platform_system": attr.string(default = ""),
        "platform_release": attr.string(default = ""),
        "platform_version": attr.string(default = ""),
        "python_version": attr.string(default = ""),
        "python_full_version": attr.string(default = ""),
        "implementation_name": attr.string(default = ""),
        "implementation_version": attr.string(default = ""),
        "platform_python_implementation": attr.string(default = ""),

        # Hidden fallback targets pointing to standard marker definitions.
        "_os_name_target": attr.label(default = "@rules_pycross//pycross/private/markers:os_name"),
        "_sys_platform_target": attr.label(default = "@rules_pycross//pycross/private/markers:sys_platform"),
        "_platform_machine_target": attr.label(default = "@rules_pycross//pycross/private/markers:platform_machine"),
        "_platform_system_target": attr.label(default = "@rules_pycross//pycross/private/markers:platform_system"),
        "_platform_release_target": attr.label(default = "@rules_pycross//pycross/settings:pep508_platform_release"),
        "_platform_version_target": attr.label(default = "@rules_pycross//pycross/settings:pep508_platform_version"),
        "_python_version_target": attr.label(default = "@rules_pycross//pycross/private/markers:python_version"),
        "_python_full_version_target": attr.label(default = "@rules_pycross//pycross/private/markers:python_full_version"),
        "_implementation_name_target": attr.label(default = "@rules_pycross//pycross/settings:pep508_implementation_name"),
        "_implementation_version_target": attr.label(default = "@rules_pycross//pycross/private/markers:implementation_version"),
        "_platform_python_implementation_target": attr.label(default = "@rules_pycross//pycross/settings:pep508_platform_python_implementation"),
    }

def collect_markers(ctx):
    """Collects PEP 508 marker values from rule context attrs and toolchain.

    Resolution order for python version markers:
      1. Explicit attr values (if non-empty)
      2. PyRuntimeInfo from the Python toolchain (interpreter_version_info)
      3. rules_python config flags (python_version, python_version_major_minor)

    Args:
        ctx: The rule context whose attrs include those from marker_value_attrs()
             and whose rule declares toolchains = [PYTHON_TOOLCHAIN_TYPE].

    Returns:
        A dict mapping marker name to its string value.
    """

    # 1. Platform markers (Direct attr or fallback target)
    os_name = ctx.attr.os_name or flag_value(ctx.attr._os_name_target)
    sys_platform = ctx.attr.sys_platform or flag_value(ctx.attr._sys_platform_target)
    platform_machine = ctx.attr.platform_machine or flag_value(ctx.attr._platform_machine_target)
    platform_system = ctx.attr.platform_system or flag_value(ctx.attr._platform_system_target)
    platform_release = ctx.attr.platform_release or flag_value(ctx.attr._platform_release_target)
    platform_version = ctx.attr.platform_version or flag_value(ctx.attr._platform_version_target)

    # 2. Python version markers (Direct attr, Toolchain, or fallback target)
    python_version = ctx.attr.python_version
    python_full_version = ctx.attr.python_full_version
    implementation_name = ctx.attr.implementation_name
    implementation_version = ctx.attr.implementation_version
    platform_python_implementation = ctx.attr.platform_python_implementation

    # Try PyRuntimeInfo from the toolchain first (most accurate).
    if (not python_version or not python_full_version or not implementation_name):
        runtime = None
        if PYTHON_TOOLCHAIN_TYPE in ctx.toolchains:
            tc = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE]
            if hasattr(tc, "py3_runtime"):
                runtime = tc.py3_runtime

        if runtime:
            if not implementation_name and hasattr(runtime, "implementation_name") and runtime.implementation_name:
                implementation_name = runtime.implementation_name

            if hasattr(runtime, "interpreter_version_info") and runtime.interpreter_version_info:
                vi = runtime.interpreter_version_info
                if not python_version:
                    python_version = "{}.{}".format(vi.major, vi.minor)
                if not python_full_version:
                    python_full_version = _format_full_version(vi)
                if not implementation_version:
                    implementation_version = _format_full_version(vi)

    # Fall back to target flags.
    if not python_version:
        python_version = flag_value(ctx.attr._python_version_target)
    if not python_full_version:
        python_full_version = flag_value(ctx.attr._python_full_version_target)
    if not implementation_name:
        implementation_name = flag_value(ctx.attr._implementation_name_target)
    if not implementation_version:
        implementation_version = flag_value(ctx.attr._implementation_version_target)
    if not platform_python_implementation:
        platform_python_implementation = flag_value(ctx.attr._platform_python_implementation_target)

    # Defaults (matching rules_python's pep508_env.bzl behavior) if still empty.
    if not implementation_name:
        implementation_name = "cpython"
    if not implementation_version and python_full_version:
        implementation_version = python_full_version
    if not platform_python_implementation:
        if implementation_name == "cpython":
            platform_python_implementation = "CPython"
        elif implementation_name == "pypy":
            platform_python_implementation = "PyPy"
        else:
            platform_python_implementation = implementation_name

    return {
        "os_name": os_name,
        "os.name": os_name,
        "sys_platform": sys_platform,
        "sys.platform": sys_platform,
        "platform_machine": platform_machine,
        "platform.machine": platform_machine,
        "platform_system": platform_system,
        "platform_release": platform_release,
        "platform_version": platform_version,
        "platform.version": platform_version,
        "python_version": python_version,
        "python_full_version": python_full_version,
        "implementation_name": implementation_name,
        "implementation_version": implementation_version,
        "platform_python_implementation": platform_python_implementation,
        "platform.python_implementation": platform_python_implementation,
        "python_implementation": platform_python_implementation,
    }

def _marker_value_impl(ctx):
    return [
        config_common.FeatureFlagInfo(value = ctx.attr.value),
    ]

marker_value = rule(
    implementation = _marker_value_impl,
    attrs = {
        "value": attr.string(),
    },
    doc = """Converts a string (possibly configurable via select()) into a FeatureFlagInfo provider.""",
)
