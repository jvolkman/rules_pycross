"""Meson-specific utilities and cross.ini generation for rules_pycross PEP 517 builds."""

import shlex
import textwrap
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

from pycross.private.build.tools.utils.cc_toolchain import parse_ar_and_guess_ranlib
from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder
from pycross.private.build.tools.utils.lifecycle import setup_pkg_config
from pycross.private.build.tools.utils.venv_utils import venv_python_path


def _escape_meson_str(value: str) -> str:
    """Escape backslashes and single quotes for Meson single-quoted INI strings."""
    return value.replace("\\", "\\\\").replace("'", "\\'")


def format_meson_list(items: List[str]) -> str:
    return "[" + ", ".join(f"'{_escape_meson_str(item)}'" for item in items) + "]"


def _split_flags(flags: str) -> List[str]:
    """Split a flags string, dropping double quotes inside tokens.

    The cc layer shell-quotes tokens such as -D__DATE__="redacted". Meson
    passes c_args to the compiler verbatim, but projects embed them in
    generated sources (numpy writes them into a raw string in
    numpy/__config__.py), where a literal `"` breaks the file. Strip inner
    double quotes without re-splitting so paths containing spaces stay intact.
    """
    return [tok.replace('"', "") for tok in shlex.split(flags)] if flags else []


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
    c_args = _split_flags(cflags)
    cxx_args = _split_flags(cxxflags)

    # Filter linker flags (-Wl,...) out of c_args/cxx_args into link args.
    #
    # Bazel's CC toolchain sometimes leaks linker flags (e.g. -Wl,-s) into
    # CFLAGS. These are harmless during normal compilation but break Meson's
    # compile-only feature detection, which uses -Werror internally. Clang
    # reports "linker input unused" as an error under -Werror, causing feature
    # checks (like NEON_VFPV4) to fail even when the compiler supports them.
    leaked_link_args = [a for a in c_args if a.startswith("-Wl,")]
    c_args = [a for a in c_args if not a.startswith("-Wl,")]
    cxx_args = [a for a in cxx_args if not a.startswith("-Wl,")]

    # Meson links through the wrapped CC/CXX, which append the toolchain's
    # executable or shared-library link flags per link (shared_module targets
    # use -bundle on macOS, the correct Mach-O type for Python extensions). So
    # c_link_args only needs what pycross exports in LDFLAGS (the cc layer's
    # library dir and the C++ runtime libs).
    ldflags = get_var("LDFLAGS", "")
    c_link_args = _split_flags(ldflags)
    c_link_args.extend(leaked_link_args)

    # setup_cc_layer already adds filtered include_dirs to CFLAGS/CXXFLAGS.
    # Only add any missing non-stdlib include_dirs here (e.g. when called
    # directly without setup_cc_layer), applying the same -nostdlibinc guard
    # so libc++/libc++abi headers never break #include_next chains.
    toolchain_provides_cxx_headers = "-nostdlibinc" in c_args or "-nostdlibinc" in cxx_args
    if cc_config and "include_dirs" in cc_config:
        existing_c = set(c_args)
        existing_cxx = set(cxx_args)
        for inc_dir_str in cc_config["include_dirs"]:
            inc_dir = str(Path(replace_placeholder(ctx.prefix, inc_dir_str)).absolute())
            if toolchain_provides_cxx_headers and ("libcxx" in inc_dir or "libcxxabi" in inc_dir):
                continue
            if f"-I{inc_dir}" not in existing_c and f"-isystem{inc_dir}" not in existing_c:
                c_args.append(f"-I{inc_dir}")
                existing_c.add(f"-I{inc_dir}")
            if f"-I{inc_dir}" not in existing_cxx and f"-isystem{inc_dir}" not in existing_cxx:
                cxx_args.append(f"-I{inc_dir}")
                existing_cxx.add(f"-I{inc_dir}")

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

    # Ensure consistent CPU feature baseline across different host compilers.
    #
    # The macOS-native clang binary (darwin-arm64) may default to a higher
    # ARM feature level than the Linux cross-compiler (linux-amd64) when
    # targeting aarch64-apple-darwin. This causes Meson's compile-only feature
    # detection to produce different results on different build hosts.
    #
    # We default to apple-m1 (the minimum Apple Silicon baseline, supporting
    # all M1/M2/M3/M4 chips). Override via meson_properties _mcpu or by
    # passing -mcpu=<value> in CFLAGS/copts.
    if target_system == "darwin" and target_cpu == "aarch64":
        has_mcpu = any(a.startswith("-mcpu=") or a == "-mcpu" for a in c_args)
        if not has_mcpu:
            mcpu = cc_config.get("meson_properties", {}).get("_mcpu", "apple-m1")
            c_args.append(f"-mcpu={mcpu}")
            cxx_args.append(f"-mcpu={mcpu}")

    # Materialize declared pkg-config files in temp_dir/pkgconfig (shared with
    # lifecycle.setup_pkg_config) so the sdist source tree stays clean.
    pkgconfig_dir = setup_pkg_config(ctx)
    abs_pkgconfig_dir = _escape_meson_str(pkgconfig_dir.resolve().as_posix())

    is_cross = ctx.exec_python != ctx.target_python

    # By default, always tell Meson it needs an exe wrapper and should skip
    # sanity checks. This prevents Meson from running compiled test binaries
    # on the build host, which would make feature detection (e.g., SIMD
    # capabilities) depend on the host rather than the hermetic toolchain.
    # This is critical for reproducible cross-host builds.
    #
    # When allow_native_exec is set (via meson_properties), fall back to the
    # old behavior of allowing native execution when exec == target platform.
    allow_native_exec = cc_config.get("meson_properties", {}).get("_allow_native_exec") == "true"

    if allow_native_exec:
        needs_exe_wrapper = is_cross
        skip_sanity_check = is_cross
    else:
        needs_exe_wrapper = True
        skip_sanity_check = True

    # Compute longdouble_format from target platform. Meson auto-detection
    # can't work in cross builds, so we always set this explicitly to keep
    # native and cross paths identical.
    if target_system == "windows" or target_cpu == "arm" or (target_system == "darwin" and target_cpu == "aarch64"):
        longdouble_format = "IEEE_DOUBLE_LE"
    elif target_cpu == "aarch64":
        longdouble_format = "IEEE_QUAD_LE"
    elif target_cpu == "x86":
        longdouble_format = "INTEL_EXTENDED_12_BYTES_LE"
    else:
        # x86_64 Linux and macOS: 80-bit extended stored in 16 bytes
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

    ar = get_var("AR")
    if ar:
        ar_list, ranlib_path = parse_ar_and_guess_ranlib(ar)
        binaries_lines.append(f"ar = {format_meson_list(ar_list)}")
        if ranlib_path:
            binaries_lines.append(f"ranlib = '{_escape_meson_str(ranlib_path.as_posix())}'")

    # Cython: only inject if present in the build virtualenv.
    # Meson does NOT inherently require Cython; it is only needed for
    # packages that contain .pyx sources.
    cython_path = ctx.tools_dir / "cython"
    if cython_path.exists():
        binaries_lines.append(f"cython = '{_escape_meson_str(cython_path.as_posix())}'")

    # pkg-config: use the tools_dir copy if available. If not present,
    # omit it and let Meson fall back to its built-in dependency lookup.
    pkgconfig_path = ctx.tools_dir / "pkg-config"
    if pkgconfig_path.exists():
        binaries_lines.append(f"pkgconfig = '{_escape_meson_str(pkgconfig_path.as_posix())}'")

    pybind11_config_path = ctx.tools_dir / "pybind11-config"
    if pybind11_config_path.exists():
        binaries_lines.append(f"pybind11-config = '{_escape_meson_str(pybind11_config_path.as_posix())}'")

    binaries_lines.append(f"python = '{_escape_meson_str(venv_python_path(ctx.env_dir).as_posix())}'")

    binaries_section = "\n".join(binaries_lines)

    # Build additional [properties] lines from meson_properties.
    # Filter out internal properties (prefixed with _) that are used for
    # framework configuration and should not appear in the cross.ini.
    extra_properties_lines = []
    for key, value in cc_config.get("meson_properties", {}).items():
        if key.startswith("_"):
            continue
        if "$$EXT_BUILD_ROOT$$" in value:
            resolved = Path(replace_placeholder(ctx.prefix, value)).absolute().as_posix()
        else:
            resolved = value
        extra_properties_lines.append(f"{key} = '{_escape_meson_str(resolved)}'")
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
needs_exe_wrapper = {str(needs_exe_wrapper).lower()}
skip_sanity_check = {str(skip_sanity_check).lower()}
longdouble_format = '{_escape_meson_str(longdouble_format)}'
pkg_config_libdir = '{abs_pkgconfig_dir}'
{extra_properties_str}

[host_machine]
system = '{_escape_meson_str(target_system)}'
cpu_family = '{_escape_meson_str(target_cpu)}'
cpu = '{_escape_meson_str(target_cpu)}'
endian = 'little'
"""

    # Write the cross file into the cc_layer directory
    cross_ini_path = ctx.temp_dir / "cc_layer" / "cross.ini"
    cross_ini_path.parent.mkdir(parents=True, exist_ok=True)
    with open(cross_ini_path, "w") as f:
        f.write(textwrap.dedent(cross_ini))

    # Always use --cross-file so native and cross follow the same path.
    setup_args = list(ctx.config_settings.get("setup-args", []))
    setup_args.append(f"--cross-file={cross_ini_path.as_posix()}")
    ctx.config_settings["setup-args"] = setup_args
    ctx.config_settings.setdefault("build-dir", "build")
