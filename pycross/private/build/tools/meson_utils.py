"""Meson-specific utilities and cross.ini generation for rules_pycross PEP 517 builds."""

import shlex
import shutil
import textwrap
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

from pycross.private.build.tools.builder_utils import BuildContext


def format_meson_list(items: List[str]) -> str:
    return "[" + ", ".join(f"'{item}'" for item in items) + "]"


def generate_cross_ini(ctx: BuildContext, cc_config: Optional[Dict[str, Any]] = None) -> None:
    """Generates the Meson cross.ini file dynamically from BuildContext and mixin configuration."""

    def get_var(name: str, default_fallback: str = "") -> str:
        val = ctx.sysconfig_vars.get(name)
        if val is not None:
            return val
        if cc_config and name in cc_config:
            return cc_config[name].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))
        return default_fallback

    cc = get_var("CC", "gcc")
    cxx = get_var("CXX", "g++")
    cflags = get_var("CFLAGS", "")
    cxxflags = get_var("CXXFLAGS", "")
    ldsharedflags = get_var("LDSHAREDFLAGS", "")

    # Parse arguments for Meson cross file
    c_args = shlex.split(cflags) if cflags else []
    cxx_args = shlex.split(cxxflags) if cxxflags else []
    c_link_args = shlex.split(ldsharedflags) if ldsharedflags else []

    # Locate target Python library directory and add it to linker search path
    target_python_lib_dir = ctx.target_python.parent.parent / "lib"
    if target_python_lib_dir.exists():
        c_link_args.append(f"-L{target_python_lib_dir.absolute()}")

    # Ensure critical linker options are carried over
    for i, flag in enumerate(cxx_args):
        if flag.startswith("--sysroot=") or flag.startswith("-target=") or flag.startswith("--target="):
            if flag not in c_link_args:
                c_link_args.append(flag)
        elif flag in ("--sysroot", "-target", "--target") and i + 1 < len(cxx_args):
            if flag not in c_link_args:
                c_link_args.extend([flag, cxx_args[i + 1]])

    # Determine target operating system and CPU family from cc_config or fallbacks
    target_system = None
    target_cpu = None

    if cc_config:
        target_system = cc_config.get("target_os")
        target_cpu = cc_config.get("target_cpu")

    # Fallback 1: Parse compiler flags if CC mixin metadata is absent
    if not target_system or not target_cpu:
        resolved_from_flags = False
        for i, flag in enumerate(cxx_args):
            if flag in ("-target", "--target") and i + 1 < len(cxx_args):
                triple = cxx_args[i + 1]
                if "darwin" in triple:
                    target_system = "darwin"
                elif "linux" in triple:
                    target_system = "linux"
                if "aarch64" in triple or "arm64" in triple:
                    target_cpu = "aarch64"
                elif "x86_64" in triple:
                    target_cpu = "x86_64"
                resolved_from_flags = True

        # Fallback 2: Parse target sysconfig variables (crucial when host == build natively)
        if not resolved_from_flags:
            machdep = ctx.sysconfig_vars.get("MACHDEP")
            if machdep:
                if "darwin" in machdep:
                    target_system = "darwin"
                elif "linux" in machdep:
                    target_system = "linux"

            host_gnu_type = ctx.sysconfig_vars.get("HOST_GNU_TYPE", "")
            multiarch = ctx.sysconfig_vars.get("MULTIARCH", "")
            combined = (host_gnu_type + "_" + multiarch).lower()
            if "aarch64" in combined or "arm64" in combined:
                target_cpu = "aarch64"
            elif "x86_64" in combined:
                target_cpu = "x86_64"

    # Hardcoded fallbacks as a last resort
    if not target_system:
        target_system = "linux"
    if not target_cpu:
        target_cpu = "x86_64"

    # If compiling for Darwin (macOS), C extensions must not link libpython
    # directly and instead rely on runtime dynamic lookup of Python symbols.
    if ctx.sysconfig_vars.get("MACHDEP") == "darwin" or target_system == "darwin":
        c_link_args.append("-Wl,-undefined,dynamic_lookup")

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
        dest_pc.write_text(content.replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix)))

    abs_pkgconfig_dir = pkgconfig_dir.resolve()

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

    cross_ini = f"""\
[binaries]
c = {format_meson_list(cc_list)}
cpp = {format_meson_list(cxx_list)}
cython = 'cython'
pkgconfig = 'pkg-config'
python = '{ctx.env_dir}/bin/python'

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

[host_machine]
system = '{target_system}'
cpu_family = '{target_cpu}'
cpu = '{target_cpu}'
endian = 'little'
"""

    # Write the cross file into our cc_hook directory
    cross_ini_path = ctx.temp_dir / "cc_hook" / "cross.ini"
    cross_ini_path.parent.mkdir(parents=True, exist_ok=True)
    with open(cross_ini_path, "w") as f:
        f.write(textwrap.dedent(cross_ini))

    # Always use --cross-file so native and cross follow the same path.
    setup_args = ctx.config_settings.get("setup-args", [])
    setup_args.append(f"--cross-file={cross_ini_path.absolute()}")
    ctx.config_settings["setup-args"] = setup_args
    ctx.config_settings["build-dir"] = "build"
