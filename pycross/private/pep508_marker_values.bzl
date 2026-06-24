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
SYS_PLATFORM_VALUES = {
    "@platforms//os:linux": "linux",
    "@platforms//os:osx": "darwin",
    "@platforms//os:windows": "win32",
    "//conditions:default": "",
}

# Maps @platforms//os constraint values to PEP 508 os_name values.
OS_NAME_VALUES = {
    "@platforms//os:linux": "posix",
    "@platforms//os:osx": "posix",
    "@platforms//os:windows": "nt",
    "//conditions:default": "",
}

# Maps @platforms//os constraint values to PEP 508 platform_system values.
PLATFORM_SYSTEM_VALUES = {
    "@platforms//os:linux": "Linux",
    "@platforms//os:osx": "Darwin",
    "@platforms//os:windows": "Windows",
    "//conditions:default": "",
}

# Maps platform constraints to PEP 508 platform_machine values.
#
# The aarch64 CPU reports different platform.machine() values depending
# on the OS: "aarch64" on Linux, "arm64" on macOS, "ARM64" on Windows.
# We use compound config_settings (OS + CPU) from
# //pycross/private:BUILD.bazel to resolve the correct value.
#
# All other architectures have consistent names across OSes.
PLATFORM_MACHINE_VALUES = {
    "@rules_pycross//pycross/private:is_linux_aarch64": "aarch64",
    "@rules_pycross//pycross/private:is_macos_aarch64": "arm64",
    "@rules_pycross//pycross/private:is_windows_aarch64": "ARM64",
    "@platforms//cpu:x86_64": "x86_64",
    "@platforms//cpu:s390x": "s390x",
    "@platforms//cpu:ppc64le": "ppc64le",
    "@platforms//cpu:i386": "i386",
    "//conditions:default": "",
}

PYTHON_TOOLCHAIN_TYPE = Label("@rules_python//python:toolchain_type")

def _flag_value(target):
    """Read a flag value from either FeatureFlagInfo or BuildSettingInfo."""
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
        # Fallback: read python version from rules_python config flags
        # when the toolchain doesn't provide interpreter_version_info.
        "_python_version_flag": attr.label(
            default = "@rules_python//python/config_settings:python_version",
        ),
        "_python_version_major_minor_flag": attr.label(
            default = "@rules_python//python/config_settings:python_version_major_minor",
        ),
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

    # Fall back to rules_python config flags.
    if not python_version and hasattr(ctx.attr, "_python_version_major_minor_flag"):
        python_version = _flag_value(ctx.attr._python_version_major_minor_flag)
    if not python_full_version and hasattr(ctx.attr, "_python_version_flag"):
        python_full_version = _flag_value(ctx.attr._python_version_flag)

    # Defaults (matching rules_python's pep508_env.bzl behavior).
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
        "os_name": ctx.attr.os_name,
        "sys_platform": ctx.attr.sys_platform,
        "platform_machine": ctx.attr.platform_machine,
        "platform_system": ctx.attr.platform_system,
        "platform_release": ctx.attr.platform_release,
        "platform_version": ctx.attr.platform_version,
        "python_version": python_version,
        "python_full_version": python_full_version,
        "implementation_name": implementation_name,
        "implementation_version": implementation_version,
        "platform_python_implementation": platform_python_implementation,
    }
