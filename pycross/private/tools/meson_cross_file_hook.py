"""Pycross pre-build hook for Meson packages.

Generates a Meson cross-file from the compiler wrappers and flags
already set up by the pycross build environment, then registers it
in the PEP-517 config settings so meson-python picks it up.

For native (same-architecture) builds, this hook is a no-op — Meson
picks up CC/CXX/CFLAGS/LDFLAGS from the environment directly.

Hook protocol (environment variables):
  PYCROSS_CONFIG_SETTINGS_FILE  – JSON file with PEP-517 config settings (r/w)
  PYCROSS_ENV_VARS_FILE         – JSON file with build env vars (r/w)
  PYCROSS_RECIPE_DATA_DIR       – Directory with recipe data files (read-only)
  CC, CXX, AR                   – Compiler / archiver wrapper paths
  CFLAGS, CXXFLAGS              – Compile flags (optimization, warnings, etc.)
  LDFLAGS                       – Extra linker flags (-L paths for native deps)
  PYCROSS_TARGET_SYSTEM         – Target OS   (e.g. "linux", "darwin")
  PYCROSS_TARGET_CPU            – Target CPU  (e.g. "x86_64", "aarch64")

Recipe data files (optional, read from PYCROSS_RECIPE_DATA_DIR):
  meson/cross_properties.json   – JSON dict of extra [properties] to inject
                                  into the cross-file. Overrides auto-detected
                                  defaults (e.g., longdouble_format).

Note: The CC/CXX wrappers already have all toolchain-level flags baked in
(--sysroot, -fuse-ld, -B, -L for glibc/libcxx, -target, etc.).  The
cross-file only needs to carry build-level flags from CFLAGS and LDFLAGS,
not toolchain flags.
"""

import json
import os
import platform
import shutil
from pathlib import Path
from typing import Dict


def _normalize_cpu(cpu: str) -> str:
    cpu = cpu.lower()
    if cpu == "arm64":
        return "aarch64"
    if cpu == "amd64":
        return "x86_64"
    return cpu


def _longdouble_format(system: str, cpu: str) -> str:
    """Determine the long double format for a target platform.

    This is a convenience default for packages like NumPy and SciPy that
    check the cross-file 'longdouble_format' property. Values can be
    overridden via recipe data (meson/cross_properties.json).
    """
    if cpu == "x86_64":
        # x87 80-bit extended precision, stored in 16 bytes on x86_64
        return "INTEL_EXTENDED_16_BYTES_LE"
    if cpu in ("i686", "i386"):
        # x87 80-bit extended precision, stored in 12 bytes on 32-bit x86
        return "INTEL_EXTENDED_12_BYTES_LE"
    if cpu == "aarch64":
        if system == "darwin":
            # macOS aarch64: long double == double (8 bytes)
            return "IEEE_DOUBLE_LE"
        # Linux aarch64: IEEE 754 quad precision (16 bytes)
        return "IEEE_QUAD_LE"
    if cpu == "riscv64":
        return "IEEE_QUAD_LE"
    if cpu == "s390x":
        return "IEEE_QUAD_BE"
    if cpu == "ppc64le":
        # Modern glibc (>= 2.32) defaults to IEEE quad; older uses IBM
        # double-double. Default to the modern format.
        return "IEEE_QUAD_LE"
    if cpu == "ppc64":
        return "IEEE_QUAD_BE"
    # Safe default for unknown architectures
    return "IEEE_DOUBLE_LE"


def _load_cross_properties() -> Dict[str, str]:
    """Load cross_properties from recipe data if available."""
    data_dir = os.environ.get("PYCROSS_RECIPE_DATA_DIR")
    if not data_dir:
        return {}

    props_file = Path(data_dir) / "meson" / "cross_properties.json"
    if not props_file.exists():
        return {}

    with open(props_file, "r") as f:
        return json.load(f)


def _build_properties(target_system: str, target_cpu: str) -> Dict[str, str]:
    """Build the [properties] section values.

    Starts with auto-detected defaults, then overlays any recipe-provided
    cross_properties. The special value "auto" for longdouble_format means
    "use the auto-detected value".
    """
    # Auto-detected defaults
    props = {
        "needs_exe_wrapper": "true",
        "longdouble_format": _longdouble_format(target_system, target_cpu),
    }

    # Overlay recipe-provided cross_properties
    recipe_props = _load_cross_properties()
    for key, value in recipe_props.items():
        if value == "auto":
            # Keep the auto-detected default
            continue
        props[key] = value

    return props


def _format_properties(props: Dict[str, str]) -> str:
    """Format properties for the cross-file [properties] section."""
    lines = []
    for key, value in props.items():
        # Booleans and numbers don't get quoted; strings do
        if value in ("true", "false") or value.isdigit():
            lines.append(f"{key} = {value}")
        else:
            lines.append(f"{key} = '{value}'")
    return "\n".join(lines)


def main() -> None:
    cc = os.environ.get("CC", "")
    cxx = os.environ.get("CXX", "")
    ar = os.environ.get("AR", "ar")

    # Build-level compile flags (optimization, warnings, defines).
    # Toolchain flags (--sysroot, -target, -isystem) are in the CC wrapper.
    c_args = os.environ.get("CFLAGS", "").split()
    cpp_args = os.environ.get("CXXFLAGS", "").split()

    # Extra linker flags — just -L paths for native deps and Python.
    # Toolchain link flags (-fuse-ld, -B, -L for glibc) are in the CC wrapper.
    # We intentionally use LDFLAGS (not LDSHARED) because LDSHARED contains
    # -shared and is specific to building Python extensions, while LDFLAGS
    # is the standard variable for additional linker search paths.
    link_args = os.environ.get("LDFLAGS", "").split()

    target_system = os.environ.get("PYCROSS_TARGET_SYSTEM", platform.system().lower())
    target_cpu = _normalize_cpu(os.environ.get("PYCROSS_TARGET_CPU", platform.machine()))

    # Determine cross-compilation
    host_system = platform.system().lower()
    host_cpu = _normalize_cpu(platform.machine())
    is_cross = (target_system != host_system) or (target_cpu != host_cpu)

    # For native (non-cross) builds, skip cross-file generation entirely.
    # In native builds, Meson picks up CC/CXX/CFLAGS/LDFLAGS from environment
    # directly. No cross-file is needed.
    if not is_cross:
        return

    # Discover ninja
    ninja_bin = shutil.which("ninja")

    # Build properties section (auto-detected + recipe overrides)
    properties = _build_properties(target_system, target_cpu)

    # Generate cross-file in CWD (the extracted sdist directory)
    cross_file_path = Path("cross-file.ini").resolve()

    cross_file_content = f"""\
[binaries]
c = '{cc}'
cpp = '{cxx}'
ar = '{ar}'
strip = 'strip'

[built-in options]
c_args = {repr(c_args)}
cpp_args = {repr(cpp_args)}
c_link_args = {repr(link_args)}
cpp_link_args = {repr(link_args)}

[properties]
{_format_properties(properties)}

[host_machine]
system = '{target_system}'
cpu_family = '{target_cpu}'
cpu = '{target_cpu}'
endian = 'little'
"""

    with open(cross_file_path, "w") as f:
        f.write(cross_file_content)

    # Update config settings
    config_file = os.environ.get("PYCROSS_CONFIG_SETTINGS_FILE")
    if config_file:
        with open(config_file, "r") as f:
            config_settings = json.load(f)

        setup_args = config_settings.get("setup-args", [])
        setup_args.append(f"--cross-file={cross_file_path}")
        config_settings["setup-args"] = setup_args
        config_settings["build-dir"] = "build"

        with open(config_file, "w") as f:
            json.dump(config_settings, f)

    # Update env vars (set NINJA if discovered)
    env_file = os.environ.get("PYCROSS_ENV_VARS_FILE")
    if env_file and ninja_bin:
        with open(env_file, "r") as f:
            env_vars = json.load(f)

        if not env_vars.get("NINJA"):
            env_vars["NINJA"] = ninja_bin
            with open(env_file, "w") as f:
                json.dump(env_vars, f)


if __name__ == "__main__":
    main()
