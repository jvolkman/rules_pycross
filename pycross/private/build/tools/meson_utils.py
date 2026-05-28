"""Meson-specific utilities and cross.ini generation for rules_pycross PEP 517 builds."""

import shlex
import shutil
import textwrap
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

from pathlib import Path
from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder


def format_meson_list(items: List[str]) -> str:
    return "[" + ", ".join(f"'{item}'" for item in items) + "]"


def generate_cross_ini(ctx: BuildContext, cc_config: Optional[Dict[str, Any]] = None) -> None:
    """Generates the Meson cross.ini file dynamically from BuildContext and mixin configuration."""

    def get_var(name: str, default_fallback: str = "") -> str:
        val = ctx.sysconfig_vars.get(name)
        if val is not None:
            return val
        if cc_config and name in cc_config:
            return replace_placeholder(ctx.prefix, cc_config[name])
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

    # Add C++ static runtime libraries directly by full path, replicating
    # Bazel's static_link_cpp_runtimes behavior. The toolchain provides these
    # .a files (e.g., libc++, libc++abi, libunwind) when the feature is
    # enabled, and Bazel passes them as positional linker inputs — not via
    # -l flags. We do the same here.
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

    # Ensure critical linker options are carried over
    for i, flag in enumerate(cxx_args):
        if flag.startswith("--sysroot=") or flag.startswith("-target=") or flag.startswith("--target="):
            if flag not in c_link_args:
                c_link_args.append(flag)
        elif flag in ("--sysroot", "-target", "--target") and i + 1 < len(cxx_args):
            if flag not in c_link_args:
                c_link_args.extend([flag, cxx_args[i + 1]])

    # Determine target operating system and CPU family strictly from cc_config.
    if not cc_config or not cc_config.get("target_os"):
        raise ValueError(
            "target_os is missing from cc_config. Ensure the CC mixin provides target_os in its configuration."
        )
    if not cc_config.get("target_cpu"):
        raise ValueError(
            "target_cpu is missing from cc_config. Ensure the CC mixin provides target_cpu in its configuration."
        )

    target_system = cc_config["target_os"]
    target_cpu = cc_config["target_cpu"]

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
        dest_pc.write_text(replace_placeholder(ctx.prefix, content))

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
    cython_path = ctx.env_dir / "bin" / "cython"
    if cython_path.exists():
        binaries_lines.append(f"cython = '{cython_path}'")

    # pkg-config: use the virtualenv copy if available. If not present,
    # omit it and let Meson fall back to its built-in dependency lookup.
    pkgconfig_path = ctx.env_dir / "bin" / "pkg-config"
    if pkgconfig_path.exists():
        binaries_lines.append(f"pkgconfig = '{pkgconfig_path}'")

    binaries_lines.append(f"python = '{ctx.env_dir}/bin/python'")

    binaries_section = "\n".join(binaries_lines)

    numpy_include_dir = None
    if cc_config:
        for inc_dir in cc_config.get("include_dirs", []):
            if "numpy/_core/include" in inc_dir or "numpy/core/include" in inc_dir:
                numpy_include_dir = Path(replace_placeholder(ctx.prefix, inc_dir)).absolute()
                break

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
{f"numpy-include-dir = '{numpy_include_dir}'" if numpy_include_dir else ""}

[host_machine]
system = '{target_system}'
cpu_family = '{target_cpu}'
cpu = '{target_cpu}'
endian = 'little'
"""

    # Write the cross file into the cc_mixin directory
    cross_ini_path = ctx.temp_dir / "cc_mixin" / "cross.ini"
    cross_ini_path.parent.mkdir(parents=True, exist_ok=True)
    with open(cross_ini_path, "w") as f:
        f.write(textwrap.dedent(cross_ini))

    # Always use --cross-file so native and cross follow the same path.
    setup_args = ctx.config_settings.get("setup-args", [])
    setup_args.append(f"--cross-file={cross_ini_path.absolute()}")
    ctx.config_settings["setup-args"] = setup_args
    ctx.config_settings["build-dir"] = "build"
