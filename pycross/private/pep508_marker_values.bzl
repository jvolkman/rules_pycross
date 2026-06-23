"""Constants mapping @platforms constraint values to PEP 508 marker values.

These dicts are intended for use in select() expressions at call sites for
rules that evaluate PEP 508 environment markers (e.g. _pycross_pep508_evaluator,
_pycross_wheel_chooser).
"""

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

def marker_value_attrs():
    """Returns default attr values for PEP 508 marker dimensions.

    Usage in a rule definition:
        _my_rule = rule(
            attrs = {
                "expr": attr.string(),
            } | marker_value_attrs(),
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
    }

def collect_markers(ctx):
    """Collects PEP 508 marker values from rule context attrs.

    Args:
        ctx: The rule context whose attrs include those from marker_value_attrs().

    Returns:
        A dict mapping marker name to its string value.
    """
    return {
        "os_name": ctx.attr.os_name,
        "sys_platform": ctx.attr.sys_platform,
        "platform_machine": ctx.attr.platform_machine,
        "platform_system": ctx.attr.platform_system,
        "platform_release": ctx.attr.platform_release,
        "platform_version": ctx.attr.platform_version,
        "python_version": ctx.attr.python_version,
        "python_full_version": ctx.attr.python_full_version,
        "implementation_name": ctx.attr.implementation_name,
        "implementation_version": ctx.attr.implementation_version,
        "platform_python_implementation": ctx.attr.platform_python_implementation,
    }
