import shlex
import shutil
import textwrap
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Tuple

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder


# NOTE: A simplified copy of the ranlib-guessing logic lives in
# modules/backend_maturin/private/tools/rust_common.py (guess_ranlib_path)
# to avoid a cross-module import. Keep both copies in sync.
def parse_ar_and_guess_ranlib(ar: str | None) -> Tuple[List[str], Path | None]:
    """Parse AR path and flags, and guess ranlib path.

    Returns:
        A tuple of (ar_list, ranlib_path). If the AR path was a bare name
        resolved via $PATH, ar_list[0] is updated to the absolute path.
    """
    if not ar:
        return [], None
    ar_list = shlex.split(ar)
    if not ar_list:
        return [], None

    ar_path = Path(ar_list[0])
    if not ar_path.is_absolute():
        resolved_ar = shutil.which(str(ar_path))
        if resolved_ar:
            ar_path = Path(resolved_ar)
            ar_list[0] = resolved_ar

    stem = ar_path.stem
    if stem == "ar" or stem.endswith(("-ar", "_ar")):
        ranlib_stem = stem[:-2] + "ranlib"
        ranlib_name = ranlib_stem + ar_path.suffix

        if ar_path.is_absolute():
            guessed_ranlib_path = ar_path.parent / ranlib_name
            if guessed_ranlib_path.exists():
                return ar_list, guessed_ranlib_path
        else:
            resolved_ranlib = shutil.which(ranlib_name)
            if resolved_ranlib:
                return ar_list, Path(resolved_ranlib)

    return ar_list, None


_FILTERED_LINKER_ARGS = (
    "-Wl,--start-group",
    "-Wl,--end-group",
    "-Wl,-start_group",
    "-Wl,-end_group",
    "-Wl,--as-needed",
    "-Wl,--allow-shlib-undefined",
    "-Wl,-O1",
)

# Compiler driver modes that stop before linking, plus relocatable partial
# links (-r, which conflicts with LDFLAGS like --gc-sections / -l*).
_NON_LINK_ARGS = (
    "-c",
    "-E",
    "-S",
    "-M",
    "-MM",
    "-fsyntax-only",
    "-r",
)

# Driver flags that make a link produce a shared object/bundle instead of an
# executable. These links get the toolchain's shared-link flags.
_SHARED_LINK_ARGS = (
    "-shared",
    "-bundle",
    "-dynamiclib",
)

# Executable-only link flags that can't be combined with a shared link
# (e.g. the @llvm musl toolchain's -static-pie).
_EXE_ONLY_LINK_ARGS = (
    "-pie",
    "-static-pie",
)


def get_wrapper_flags(cflags: str) -> List[str]:
    """Extract target and sysroot flags to forward to compiler wrappers."""
    possible_flags = ["-target", "--target", "--sysroot", "-isysroot", "-mmacosx-version-min"]
    result = []
    split_cflags = shlex.split(cflags)
    for i, flag in enumerate(split_cflags):
        for possible_flag in possible_flags:
            if not (flag.startswith(possible_flag)):
                continue
            if "=" in flag:
                flag, value = flag.split("=", 1)
                additions = [f"{flag}={value}"]
            else:
                flag, value = flag, split_cflags[i + 1]
                additions = [flag, value]

            if not flag == possible_flag:
                continue
            result.extend(additions)
    return result


def wrap_compiler(
    lang: str,
    cc_exe: str,
    cflags: str,
    python_exe: Path,
    bin_dir: Path,
    ldflags: str = "",
    ldsharedflags: str | None = None,
) -> Path:
    """Generate custom compiler wrapper scripts to filter incompatible linker flags."""
    assert lang in ("cc", "cxx")

    cc_path = Path(cc_exe)
    if "clang" in cc_path.name or "zig" in cc_path.name:
        wrapper_name = "clang" if lang == "cc" else "clang++"
    elif "gcc" in cc_path.name:
        wrapper_name = "gcc" if lang == "cc" else "g++"
    else:
        wrapper_name = cc_path.name

    wrapper_flags = get_wrapper_flags(cflags)
    linker_flags = [arg for arg in shlex.split(ldflags) if arg not in _FILTERED_LINKER_ARGS]
    # The caller picks the output type, so drop -shared (clang rejects -shared with -bundle).
    shared_linker_flags = [
        arg
        for arg in shlex.split(ldflags if ldsharedflags is None else ldsharedflags)
        if arg not in _FILTERED_LINKER_ARGS and arg != "-shared"
    ]
    wrapper_path = bin_dir / wrapper_name

    with open(wrapper_path, "w") as f:
        f.write(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                "exec" "{python_exe.absolute()}" "-S" "$0" "$@"
                import os
                import sys

                cc_exe = {repr(cc_exe)}
                wrapper_flags = {repr(wrapper_flags)}
                linker_flags = {repr(linker_flags)}
                shared_linker_flags = {repr(shared_linker_flags)}
                filtered_linker_args = {repr(_FILTERED_LINKER_ARGS)}
                non_link_args = {repr(_NON_LINK_ARGS)}
                shared_link_args = {repr(_SHARED_LINK_ARGS)}
                exe_only_link_args = {repr(_EXE_ONLY_LINK_ARGS)}

                filtered_args = []
                is_link = bool(sys.argv[1:])
                is_shared = False
                for arg in sys.argv[1:]:
                    if arg in non_link_args:
                        is_link = False
                    if arg in shared_link_args:
                        is_shared = True
                    if arg in filtered_linker_args:
                        continue
                    filtered_args.append(arg)

                if filtered_args == ["-v"]:
                    is_link = False

                if is_link and is_shared:
                    # Build systems may pass executable LDFLAGS to shared links too
                    # (distutils appends $LDFLAGS to LDSHARED).
                    filtered_args = [a for a in filtered_args if a not in exe_only_link_args]

                extra_link_flags = []
                if is_link:
                    extra_link_flags = shared_linker_flags if is_shared else linker_flags

                os.execv(cc_exe, [cc_exe] + wrapper_flags + filtered_args + extra_link_flags)
                """
            )
        )

    wrapper_path.chmod(0o755)
    return wrapper_path


def setup_cc_layer(ctx: BuildContext, cc_config: Dict[str, Any]) -> None:
    """Populate environment parameters and wrappers for Bazel CC Toolchains."""
    layer_bin_dir = ctx.temp_dir / "cc_layer" / "bin"
    layer_include_dir = ctx.temp_dir / "cc_layer" / "include"
    layer_lib_dir = ctx.temp_dir / "cc_layer" / "lib"
    layer_bin_dir.mkdir(parents=True, exist_ok=True)
    layer_include_dir.mkdir(parents=True, exist_ok=True)
    layer_lib_dir.mkdir(parents=True, exist_ok=True)

    for lib_path_str in cc_config.get("static_libs", []) + cc_config.get("shared_libs", []):
        lib_path = Path(replace_placeholder(ctx.prefix, lib_path_str))
        dest = layer_lib_dir / lib_path.name
        if not dest.exists():
            dest.symlink_to(lib_path.absolute())

    orig_cc = replace_placeholder(ctx.prefix, cc_config["CC"])
    orig_cxx = replace_placeholder(ctx.prefix, cc_config["CXX"])
    cflags = replace_placeholder(ctx.prefix, cc_config["CFLAGS"])
    raw_ldflags = replace_placeholder(ctx.prefix, cc_config["LDFLAGS"])
    raw_ldsharedflags = replace_placeholder(ctx.prefix, cc_config["LDSHAREDFLAGS"])

    wrapped_cc = wrap_compiler(
        "cc", orig_cc, cflags, ctx.exec_python, layer_bin_dir, ldflags=raw_ldflags, ldsharedflags=raw_ldsharedflags
    )
    wrapped_cxx = wrap_compiler(
        "cxx", orig_cxx, cflags, ctx.exec_python, layer_bin_dir, ldflags=raw_ldflags, ldsharedflags=raw_ldsharedflags
    )

    # When the toolchain already handles C++ header hermeticity (indicated by
    # -nostdlibinc in flags), it provides libc++ headers via -isystem. We must
    # NOT add duplicate libc++ include dirs from native_deps, as the duplicate
    # -I paths break #include_next chains (libc++ wrapper headers can't reach
    # the underlying C headers from glibc). Only add non-C++ stdlib includes
    # (e.g., openblas headers) in this case.
    toolchain_provides_cxx_headers = "-nostdlibinc" in cflags

    extra_includes = []
    for inc_dir_str in cc_config.get("include_dirs", []):
        inc_dir = Path(replace_placeholder(ctx.prefix, inc_dir_str))
        if toolchain_provides_cxx_headers and ("libcxx" in str(inc_dir) or "libcxxabi" in str(inc_dir)):
            continue
        extra_includes.append(f"-I{inc_dir.absolute()}")
    extra_includes_str = " ".join(extra_includes)

    ldflags = replace_placeholder(ctx.prefix, cc_config["LDFLAGS"]) + f" -L{layer_lib_dir.absolute()}"
    ldsharedflags = replace_placeholder(ctx.prefix, cc_config["LDSHAREDFLAGS"]) + f" -L{layer_lib_dir.absolute()}"

    # Append C++ static runtime libraries directly by full path to LDFLAGS and
    # LDSHAREDFLAGS. This replicates Bazel's static_link_cpp_runtimes behavior
    # and ensures all builders (Meson, Maturin, setuptools) can link the C++
    # runtime without needing -l flags or specific library naming conventions.
    runtime_libs = cc_config.get("runtime_libs", [])
    if runtime_libs:
        runtime_lib_flags = " ".join(str(Path(replace_placeholder(ctx.prefix, lib)).absolute()) for lib in runtime_libs)
        ldflags += f" {runtime_lib_flags}"
        ldsharedflags += f" {runtime_lib_flags}"

    ctx.sysconfig_vars.update(
        {
            "CC": str(wrapped_cc.absolute()),
            "CXX": str(wrapped_cxx.absolute()),
            "CFLAGS": cflags
            + f" -I{layer_include_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "CXXFLAGS": replace_placeholder(ctx.prefix, cc_config["CXXFLAGS"])
            + f" -I{layer_include_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "LDFLAGS": ldflags,
            "LDSHAREDFLAGS": ldsharedflags,
            "AR": replace_placeholder(ctx.prefix, cc_config["AR"]),
            "ARFLAGS": replace_placeholder(ctx.prefix, cc_config["ARFLAGS"]),
        }
    )
    # Propagate the compiled CC toolchain flags directly to the shell environment dictionary
    # so that downstream non-python builders (like Meson/Ninja) receive them cleanly.
    for env_key in ["CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "LDSHAREDFLAGS", "AR", "ARFLAGS"]:
        if env_key in ctx.sysconfig_vars:
            ctx.build_env[env_key] = ctx.sysconfig_vars[env_key]

    if ctx.sysconfig_vars.get("MACHDEP") == "darwin":
        # Link extensions as MH_BUNDLE like CPython and the meson builder. LDSHAREDFLAGS
        # carries -shared (MH_DYLIB), so start from LDFLAGS instead.
        ctx.sysconfig_vars["LDSHARED"] = " ".join(
            [ctx.sysconfig_vars["CC"], ctx.sysconfig_vars["LDFLAGS"], "-bundle -undefined dynamic_lookup"]
        )
    else:
        ctx.sysconfig_vars["LDSHARED"] = " ".join([ctx.sysconfig_vars["CC"], ctx.sysconfig_vars["LDSHAREDFLAGS"]])
    ctx.sysconfig_vars["LDCXXSHARED"] = ctx.sysconfig_vars["LDSHARED"]

    include_paths = [str(layer_include_dir.absolute())] + [
        str(Path(replace_placeholder(ctx.prefix, p)).absolute()) for p in cc_config.get("include_dirs", [])
    ]
    ctx.build_env.update(
        {
            "PATH": f"{layer_bin_dir.absolute()}:{ctx.build_env.get('PATH', '')}",
            "PYCROSS_LIBRARY_PATH": str(layer_lib_dir.absolute()),
            "PYCROSS_INCLUDE_PATH": ":".join(include_paths),
            "CC": ctx.sysconfig_vars["CC"],
            "CXX": ctx.sysconfig_vars["CXX"],
            "CFLAGS": ctx.sysconfig_vars["CFLAGS"],
            "CXXFLAGS": ctx.sysconfig_vars["CXXFLAGS"],
            "LDFLAGS": ctx.sysconfig_vars["LDFLAGS"],
            "LDSHAREDFLAGS": ctx.sysconfig_vars["LDSHAREDFLAGS"],
        }
    )
