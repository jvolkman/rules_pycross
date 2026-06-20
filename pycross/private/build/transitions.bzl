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

def _pycross_exec_platform_transition_impl(settings, _attr):
    if settings["//command_line_option:platforms"] == [settings["//command_line_option:host_platform"]]:
        return {}

    return {
        "//command_line_option:platforms": [settings["//command_line_option:host_platform"]],
        "//command_line_option:cpu": settings["//command_line_option:host_cpu"],
        "//command_line_option:compiler": settings["//command_line_option:host_compiler"],
        "//command_line_option:compilation_mode": settings["//command_line_option:host_compilation_mode"],
        "//command_line_option:copt": settings["//command_line_option:host_copt"],
        "//command_line_option:cxxopt": settings["//command_line_option:host_cxxopt"],
        "//command_line_option:linkopt": settings["//command_line_option:host_linkopt"],
        "//command_line_option:action_env": settings["//command_line_option:host_action_env"],
        "//command_line_option:features": settings["//command_line_option:host_features"],
        "//command_line_option:strip": "always",
    }

pycross_exec_platform_transition = transition(
    implementation = _pycross_exec_platform_transition_impl,
    inputs = [
        "//command_line_option:platforms",
        "//command_line_option:host_platform",
        "//command_line_option:host_cpu",
        "//command_line_option:host_compiler",
        "//command_line_option:host_compilation_mode",
        "//command_line_option:host_copt",
        "//command_line_option:host_cxxopt",
        "//command_line_option:host_linkopt",
        "//command_line_option:host_action_env",
        "//command_line_option:host_features",
    ],
    outputs = [
        "//command_line_option:platforms",
        "//command_line_option:cpu",
        "//command_line_option:compiler",
        "//command_line_option:compilation_mode",
        "//command_line_option:copt",
        "//command_line_option:cxxopt",
        "//command_line_option:linkopt",
        "//command_line_option:action_env",
        "//command_line_option:features",
        "//command_line_option:strip",
    ],
)
