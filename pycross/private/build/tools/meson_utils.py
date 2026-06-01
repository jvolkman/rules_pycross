"""Meson-specific utilities and cross.ini generation for rules_pycross PEP 517 builds."""

import shlex
import shutil
import textwrap
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder


def format_meson_list(items: List[str]) -> str:
    return "[" + ", ".join(f"'{item}'" for item in items) + "]"


def generate_cross_ini(ctx: BuildContext, cc_config: Optional[Dict[str, Any]] = None) -> None:
    """Generates the Meson cross.ini file dynamically from BuildContext and env configuration."""

    def get_var(name: str, default_fallback: str = "") -> str:
        val = ctx.sysconfig_vars.get(name)
        if val is not None:
            return val
        if cc_config and name in cc_config:
            return replace_placeholder(ctx.prefix, cc_config[name])
        return default_fallback

    cc = get_var("CC")
    cxx = get_var("CXX")
    if not cc or not cxx:
        raise ValueError(
            "CC and CXX must be provided by the Bazel CC toolchain. Ensure a cc_layer is configured for this build."
        )
    cflags = get_var("CFLAGS", "")
    cxxflags = get_var("CXXFLAGS", "")

    # Parse arguments for Meson cross file
    c_args = shlex.split(cflags) if cflags else []
    cxx_args = shlex.split(cxxflags) if cxxflags else []

    # Use LDFLAGS (not LDSHAREDFLAGS) for Meson's c_link_args.
    #
    # LDSHAREDFLAGS comes from Bazel's cpp_link_dynamic_library action with
    # is_linking_dynamic_library=True, which includes -shared. On macOS,
    # clang maps -shared to -dynamiclib (MH_DYLIB). But Meson builds Python
    # extensions as shared_module targets using -bundle (MH_BUNDLE) — which
    # is the correct Mach-O type (verified against official PyPI wheels).
    # Passing both -shared and -bundle to clang is a fatal error.
    #
    # LDFLAGS comes from cpp_link_executable with is_linking_dynamic_library=
    # False. It contains all the same toolchain configuration flags (sysroot,
    # -fuse-ld=lld, -rtlib=compiler-rt, framework flags, library paths) but
    # without -shared. This lets Meson add its own link-type flag as needed.
    #
    # We can't remove -shared from LDSHAREDFLAGS itself because setuptools
    # uses LDSHARED (CC + LDSHAREDFLAGS) directly and needs it.
    ldflags = get_var("LDFLAGS", "")
    c_link_args = shlex.split(ldflags) if ldflags else []

    # Add C++ static runtime libraries by full path, replicating Bazel's
    # static_link_cpp_runtimes behavior.
    if cc_config:
        for lib_path_str in cc_config.get("runtime_libs", []):
            lib_path = replace_placeholder(ctx.prefix, lib_path_str)
            c_link_args.append(lib_path)

    # Dynamically append all sandboxed C/C++ includes to c_args and cpp_args inside cross.ini
    if cc_config and "include_dirs" in cc_config:
        for inc_dir_str in cc_config["include_dirs"]:
            inc_dir = replace_placeholder(ctx.prefix, inc_dir_str)
            # Add as standard -isystem includes
            c_args.append(f"-isystem{inc_dir}")
            cxx_args.append(f"-isystem{inc_dir}")

    # Locate target Python library directory and add it to linker search path
    target_python_lib_dir = ctx.target_python.parent.parent / "lib"
    if target_python_lib_dir.exists():
        c_link_args.append(f"-L{target_python_lib_dir.absolute()}")

    # Determine target operating system and CPU family strictly from cc_config.
    if not cc_config or not cc_config.get("target_os"):
        raise ValueError(
            "target_os is missing from cc_config. Ensure the CC env provides target_os in its configuration."
        )
    if not cc_config.get("target_cpu"):
        raise ValueError(
            "target_cpu is missing from cc_config. Ensure the CC env provides target_cpu in its configuration."
        )

    target_system = cc_config["target_os"]
    target_cpu = cc_config["target_cpu"]

    # Locate or create pkgconfig directory inside the build environment
    pkgconfig_dir = ctx.sdist_dir / "pkgconfig"
    pkgconfig_dir.mkdir(exist_ok=True)

    # Copy all declared pkg-config files into the sdist pkgconfig directory
    for pc_file in ctx.pkg_config_files:
        dest_pc = pkgconfig_dir / pc_file.name
        shutil.copy2(pc_file.absolute(), dest_pc)
        dest_pc.chmod(0o644)

        # Replace $$EXT_BUILD_ROOT$$ with prefix inside the .pc file content
        content = dest_pc.read_text()
        dest_pc.write_text(replace_placeholder(ctx.prefix, content))

    abs_pkgconfig_dir = pkgconfig_dir.resolve().as_posix()

    is_cross = ctx.exec_python != ctx.target_python

    # Compute longdouble_format from target platform. Meson auto-detection
    # can't work in cross builds, so we always set this explicitly to keep
    # native and cross paths identical.
    if target_system == "darwin":
        longdouble_format = "IEEE_DOUBLE_LE"
    elif target_cpu == "aarch64":
        longdouble_format = "IEEE_QUAD_LE"
    else:
        # x86_64 Linux: 80-bit extended stored in 16 bytes
        longdouble_format = "INTEL_EXTENDED_16_BYTES_LE"

    cc_list = shlex.split(cc) if cc else []
    cxx_list = shlex.split(cxx) if cxx else []

    # Build the [binaries] section dynamically to maintain hermeticity.
    # Only reference tools that exist inside the build virtualenv, using
    # their full absolute paths. Bare names like 'cython' or 'pkg-config'
    # would resolve via the system PATH, breaking sandbox isolation.
    binaries_lines = [
        f"c = {format_meson_list(cc_list)}",
        f"cpp = {format_meson_list(cxx_list)}",
    ]

    # Cython: only inject if present in the build virtualenv.
    # Meson does NOT inherently require Cython; it is only needed for
    # packages that contain .pyx sources.
    cython_path = ctx.tools_dir / "cython"
    if cython_path.exists():
        binaries_lines.append(f"cython = '{cython_path.as_posix()}'")

    # pkg-config: use the tools_dir copy if available. If not present,
    # omit it and let Meson fall back to its built-in dependency lookup.
    pkgconfig_path = ctx.tools_dir / "pkg-config"
    if pkgconfig_path.exists():
        binaries_lines.append(f"pkgconfig = '{pkgconfig_path.as_posix()}'")

    pybind11_config_path = ctx.tools_dir / "pybind11-config"
    if pybind11_config_path.exists():
        binaries_lines.append(f"pybind11-config = '{pybind11_config_path.as_posix()}'")

    binaries_lines.append(f"python = '{(ctx.env_dir / 'bin' / 'python').as_posix()}'")

    binaries_section = "\n".join(binaries_lines)

    # Build additional [properties] lines from meson_properties
    extra_properties_lines = []
    if cc_config:
        for key, value in cc_config.get("meson_properties", {}).items():
            if "$$EXT_BUILD_ROOT$$" in value:
                resolved = Path(replace_placeholder(ctx.prefix, value)).absolute().as_posix()
            else:
                resolved = value
            extra_properties_lines.append(f"{key} = '{resolved}'")
    extra_properties_str = "\n".join(extra_properties_lines)

    cross_ini = f"""\
[binaries]
{binaries_section}

[built-in options]
c_args = {format_meson_list(c_args)}
c_link_args = {format_meson_list(c_link_args)}
cpp_args = {format_meson_list(cxx_args)}
cpp_link_args = {format_meson_list(c_link_args)}
pkg_config_path = '{abs_pkgconfig_dir}'

[properties]
needs_exe_wrapper = {str(is_cross).lower()}
skip_sanity_check = {str(is_cross).lower()}
longdouble_format = '{longdouble_format}'
pkg_config_libdir = '{abs_pkgconfig_dir}'
{extra_properties_str}

[host_machine]
system = '{target_system}'
cpu_family = '{target_cpu}'
cpu = '{target_cpu}'
endian = 'little'
"""

    # Write the cross file into the cc_layer directory
    cross_ini_path = ctx.temp_dir / "cc_layer" / "cross.ini"
    cross_ini_path.parent.mkdir(parents=True, exist_ok=True)
    with open(cross_ini_path, "w") as f:
        f.write(textwrap.dedent(cross_ini))

    # Always use --cross-file so native and cross follow the same path.
    setup_args = ctx.config_settings.get("setup-args", [])
    setup_args.append(f"--cross-file={cross_ini_path.as_posix()}")
    ctx.config_settings["setup-args"] = setup_args
    ctx.config_settings["build-dir"] = "build"
