"""Custom configuration transitions for pycross.

The key problem: when building an sdist, pycross uses a paired (exec, target)
Python setup. The exec Python (same version as target, but for the host platform)
actually runs setup.py/meson-python inside a crossenv. Build dependencies like
setuptools, cython, etc. are imported by this exec Python.

So build deps need to be resolved for:
  - The TARGET Python version (e.g., 3.14.2)
  - The EXEC/HOST platform (e.g., linux x86_64)

Neither of Bazel's built-in configurations gives us this:
  - cfg = "target" → correct Python version, wrong platform (target platform)
  - cfg = "exec"   → correct platform, wrong Python version (exec Python)

This module provides a transition that switches --platforms to the host platform
while preserving all other settings (including the Python version flag).
"""

load("@rules_pycross_internal_config//:defaults.bzl", "glibc_version", "macos_version", "musl_version")
load(
    "//pycross/private:pep508_marker_values.bzl",
    "DEFAULT_PEP508_IMPLEMENTATION_NAME",
    "DEFAULT_PEP508_PLATFORM_PYTHON_IMPLEMENTATION",
    "DEFAULT_PEP508_PLATFORM_RELEASE",
    "DEFAULT_PEP508_PLATFORM_VERSION",
)

# Target-environment settings that must be reset to their defaults for
# exec-side build tools and dependencies.
_EXEC_TARGET_SETTINGS = {
    "//pycross/settings:glibc_version": glibc_version,
    "//pycross/settings:macos_version": macos_version,
    "//pycross/settings:musl_version": musl_version,
    "//pycross/settings:pep508_implementation_name": DEFAULT_PEP508_IMPLEMENTATION_NAME,
    "//pycross/settings:pep508_platform_python_implementation": DEFAULT_PEP508_PLATFORM_PYTHON_IMPLEMENTATION,
    "//pycross/settings:pep508_platform_release": DEFAULT_PEP508_PLATFORM_RELEASE,
    "//pycross/settings:pep508_platform_version": DEFAULT_PEP508_PLATFORM_VERSION,
    # The exec platform is a glibc host; don't let a musl target's
    # py_linux_libc select a musl interpreter for exec-side tools.
    "@rules_python//python/config_settings:py_linux_libc": "glibc",
}

# Target-specific C/C++ compiler and feature flags that are reset to their
# host_* counterparts when transitioning from a non-host target platform.
_CROSS_HOST_OPTION_MAP = {
    "//command_line_option:copt": "//command_line_option:host_copt",
    "//command_line_option:conlyopt": "//command_line_option:host_conlyopt",
    "//command_line_option:cxxopt": "//command_line_option:host_cxxopt",
    "//command_line_option:linkopt": "//command_line_option:host_linkopt",
    "//command_line_option:features": "//command_line_option:host_features",
}

def _pycross_exec_platform_transition_impl(settings, _attr):
    is_cross = settings["//command_line_option:platforms"] != [settings["//command_line_option:host_platform"]]
    if not is_cross and all([settings[k] == v for k, v in _EXEC_TARGET_SETTINGS.items()]):
        return {}

    return {
        "//command_line_option:platforms": [settings["//command_line_option:host_platform"]],
    } | _EXEC_TARGET_SETTINGS | {
        target_opt: settings[host_opt if is_cross else target_opt]
        for target_opt, host_opt in _CROSS_HOST_OPTION_MAP.items()
    }

pycross_exec_platform_transition = transition(
    implementation = _pycross_exec_platform_transition_impl,
    inputs = [
        "//command_line_option:platforms",
        "//command_line_option:host_platform",
    ] + _EXEC_TARGET_SETTINGS.keys() + _CROSS_HOST_OPTION_MAP.keys() + _CROSS_HOST_OPTION_MAP.values(),
    outputs = [
        "//command_line_option:platforms",
    ] + _EXEC_TARGET_SETTINGS.keys() + _CROSS_HOST_OPTION_MAP.keys(),
)
