import os
import re
import shlex
import shutil
import subprocess
import textwrap
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional
from typing import Sequence
from typing import Tuple

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import CcLayerState
from pycross.private.build.tools.utils.context import replace_placeholder
from pycross.private.build.tools.utils.context import resolve_sandbox_path


def parse_ar_and_guess_ranlib(ar: str | None) -> Tuple[List[str], Path | None]:
    """Parse AR path and flags, and guess ranlib path.

    Returns:
        A tuple of (ar_list, ranlib_path). If the AR path was a bare name
        resolved via $PATH, ar_list[0] is updated to the absolute path.
    """
    if not ar:
        return [], None
    ar_list = [ar] if Path(ar).exists() else shlex.split(ar)
    if not ar_list:
        return [], None

    ar_path = Path(ar_list[0])
    if not ar_path.is_absolute():
        resolved_ar = shutil.which(str(ar_path))
        if resolved_ar:
            ar_path = Path(resolved_ar)
            ar_list[0] = resolved_ar

    stem = ar_path.stem
    if not (stem == "ar" or stem.endswith(("-ar", "_ar"))):
        return ar_list, None

    ranlib_stem = stem[:-2] + "ranlib"
    ranlib_name = ranlib_stem + ar_path.suffix

    if ar_path.is_absolute():
        guessed_ranlib_path = ar_path.parent / ranlib_name
        return ar_list, guessed_ranlib_path if guessed_ranlib_path.exists() else None
    else:
        resolved_ranlib = shutil.which(ranlib_name)
        return ar_list, Path(resolved_ranlib) if resolved_ranlib else None


_FILTERED_LINKER_ARGS = (
    "-Wl,--start-group",
    "-Wl,--end-group",
    "-Wl,-start_group",
    "-Wl,-end_group",
    "-Wl,--as-needed",
    "-Wl,--allow-shlib-undefined",
    "-Wl,-O1",
)

# Compiler driver modes and probes that stop before linking, plus relocatable
# partial links (-r, which conflicts with LDFLAGS like --gc-sections / -l*).
_NON_LINK_ARGS = (
    "-c",
    "-E",
    "-S",
    "-M",
    "-MM",
    "-fsyntax-only",
    "-r",
    "--version",
    "-dumpmachine",
    "-dumpversion",
    "-dumpfullversion",
    "--help",
)

# Driver flags that make a link produce a shared object/bundle instead of an
# executable. These links get the toolchain's shared-link flags.
_SHARED_LINK_ARGS = (
    "-shared",
    "-bundle",
    "-dynamiclib",
)


def get_wrapper_flags(compile_flags: Sequence[str]) -> List[str]:
    """Extract target and sysroot flags to forward to compiler wrappers."""
    possible_flags = ("-target", "--target", "--sysroot", "-isysroot", "-mmacosx-version-min")
    result = []
    for i, flag in enumerate(compile_flags):
        flag_name, sep, value = flag.partition("=")
        if flag_name not in possible_flags:
            continue
        if sep:
            result.append(f"{flag_name}={value}")
        elif i + 1 < len(compile_flags):
            result.extend([flag_name, compile_flags[i + 1]])
    return result


def _format_exec_cmd(cc_exe: str, prefix_flags: List[str], tail_flags: List[str]) -> str:
    parts = (
        [shlex.quote(cc_exe)] + [shlex.quote(f) for f in prefix_flags] + ['"$@"'] + [shlex.quote(f) for f in tail_flags]
    )
    return "exec " + " ".join(parts)


def wrap_compiler(
    lang: str,
    cc_exe: str,
    compile_flags: Sequence[str],
    bin_dir: Path,
    ldflags: Sequence[str] = (),
    ldsharedflags: Optional[Sequence[str]] = None,
) -> Path:
    """Generate POSIX /bin/sh compiler wrapper scripts to filter incompatible linker flags."""
    assert lang in ("cc", "cxx")

    cc_path = Path(cc_exe)
    if "clang" in cc_path.name or "zig" in cc_path.name:
        wrapper_name = "clang" if lang == "cc" else "clang++"
    elif "gcc" in cc_path.name:
        wrapper_name = "gcc" if lang == "cc" else "g++"
    else:
        wrapper_name = cc_path.name

    wrapper_flags = get_wrapper_flags(compile_flags)
    linker_flags = [arg for arg in ldflags if arg not in _FILTERED_LINKER_ARGS]
    # The caller picks the output type, so drop -shared (clang rejects -shared with -bundle).
    shared_source = ldflags if ldsharedflags is None else ldsharedflags
    shared_linker_flags = [arg for arg in shared_source if arg not in _FILTERED_LINKER_ARGS and arg != "-shared"]
    wrapper_path = bin_dir / wrapper_name

    non_link_pattern = "|".join(_NON_LINK_ARGS) + "|-print-*|--print-*|--help=*"
    shared_link_pattern = "|".join(_SHARED_LINK_ARGS)
    filtered_pattern = "|".join(_FILTERED_LINKER_ARGS)

    exec_shared = _format_exec_cmd(cc_exe, wrapper_flags, shared_linker_flags)
    exec_link = _format_exec_cmd(cc_exe, wrapper_flags, linker_flags)
    exec_non_link = _format_exec_cmd(cc_exe, wrapper_flags, [])

    with open(wrapper_path, "w") as f:
        f.write(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                set -f
                is_link=1
                is_shared=0
                needs_filter=0
                if [ "$#" -eq 0 ]; then
                    is_link=0
                fi
                for arg in "$@"; do
                    case "$arg" in
                        {non_link_pattern})
                            is_link=0
                            ;;
                        {shared_link_pattern})
                            is_shared=1
                            ;;
                        {filtered_pattern})
                            needs_filter=1
                            ;;
                    esac
                done
                if [ "$needs_filter" -eq 1 ]; then
                    argc=$#
                    i=0
                    while [ "$i" -lt "$argc" ]; do
                        arg=$1
                        shift
                        i=$((i + 1))
                        case "$arg" in
                            {filtered_pattern})
                                continue
                                ;;
                        esac
                        set -- "$@" "$arg"
                    done
                fi
                if [ "$#" -eq 1 ] && [ "$1" = "-v" ]; then
                    is_link=0
                fi
                if [ "$is_link" -eq 1 ]; then
                    if [ "$is_shared" -eq 1 ]; then
                        {exec_shared}
                    else
                        {exec_link}
                    fi
                else
                    {exec_non_link}
                fi
                """
            )
        )

    wrapper_path.chmod(0o755)
    return wrapper_path


_VERSIONED_DYLIB_RE = re.compile(r"^(lib.+?)\.\d[\d.]*\.dylib$")


def unversioned_library_name(filename: str) -> Optional[str]:
    """Return the name `-l` looks for (`libfoo.so` for `libfoo.so.1`), or None if unversioned."""
    if ".so." in filename:
        return filename.split(".so.", 1)[0] + ".so"
    m = _VERSIONED_DYLIB_RE.match(filename)
    if m:
        return m.group(1) + ".dylib"
    return None


def _resolve_msvc_environment(ctx: BuildContext, environment: Dict[str, str], inherited_path: str) -> Dict[str, str]:
    """Resolve directories in MSVC's PATH, INCLUDE, and LIB before building.

    Make relative paths absolute under the Bazel execroot and replace
    $$EXT_BUILD_ROOT$$ placeholders with that root. Normalize resolved SDK paths
    and append the existing build PATH after SDK PATH entries. This keeps paths
    valid when the build runs from the sdist without normalizing inherited PATH.
    """
    result = {}
    for key, value in environment.items():
        entries = []
        source_entries = value.split(os.pathsep) if value else []
        # Resolve SDK paths from the execroot and normalize nonempty entries.
        # Keep empty entries unchanged instead of normalizing them to ".".
        for entry in source_entries:
            resolved = resolve_sandbox_path(ctx.prefix, entry)
            entries.append(os.path.normpath(resolved) if resolved else "")
        # Keep existing build tools available after SDK tools so the selected
        # MSVC compiler takes priority.
        if key == "PATH" and inherited_path:
            entries.append(inherited_path)
        result[key] = os.pathsep.join(entries)
    return result


CC_ENV_KEYS = ("CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "AR", "ARFLAGS")


def join_flags(tokens: Sequence[str], *, posix: Optional[bool] = None) -> str:
    """Join compiler/linker flag tokens using platform-appropriate quoting.

    Uses ``subprocess.list2cmdline`` on Windows so paths with backslashes are not
    wrapped in POSIX single quotes, and ``shlex.join`` on POSIX.
    """
    if not tokens:
        return ""
    use_posix = (os.name != "nt") if posix is None else posix
    if not use_posix:
        return subprocess.list2cmdline(tokens)
    return shlex.join(tokens)


def _resolve_flags(prefix: Path, raw: Sequence[str]) -> List[str]:
    if isinstance(raw, str):
        raise TypeError(f"Expected a sequence of flag strings, got str: {raw!r}")
    return [replace_placeholder(prefix, flag) for flag in raw]


def setup_cc_layer(ctx: BuildContext, cc_config: Dict[str, Any]) -> CcLayerState:
    """Populate environment parameters, compiler wrappers, and ``ctx.cc_layer``."""
    native_msvc = os.name == "nt" and "msvc_env" in cc_config
    layer_bin_dir = (ctx.temp_dir / "cc_layer" / "bin").absolute()
    layer_lib_dir = (ctx.temp_dir / "cc_layer" / "lib").absolute()
    layer_bin_dir.mkdir(parents=True, exist_ok=True)
    layer_lib_dir.mkdir(parents=True, exist_ok=True)

    for lib_path_str in cc_config.get("static_libs", []):
        lib_path = Path(replace_placeholder(ctx.prefix, lib_path_str))
        dest = layer_lib_dir / lib_path.name
        if not os.path.lexists(dest):
            dest.symlink_to(lib_path.absolute())
        # Linkers look for `libfoo.a` when given `-lfoo`, so alias `libfoo.pic.a`.
        if lib_path.name.endswith(".pic.a"):
            unpic_dest = layer_lib_dir / (lib_path.name[: -len(".pic.a")] + ".a")
            if not os.path.lexists(unpic_dest):
                unpic_dest.symlink_to(lib_path.absolute())

    # `-lfoo` only finds `libfoo.so` or `libfoo.dylib`. Wheels can't contain symlinks, so a
    # library from a wheel is often only the versioned file (`libcudart.so.12`). Add the
    # unversioned name; the linker still records the library's SONAME or install name.
    for lib_path_str in cc_config.get("shared_libs", []):
        lib_path = Path(replace_placeholder(ctx.prefix, lib_path_str))
        dest = layer_lib_dir / lib_path.name
        if not os.path.lexists(dest):
            dest.symlink_to(lib_path.absolute())
        linker_name = unversioned_library_name(lib_path.name)
        if linker_name and not os.path.lexists(layer_lib_dir / linker_name):
            (layer_lib_dir / linker_name).symlink_to(lib_path.absolute())

    raw_cflags = _resolve_flags(ctx.prefix, cc_config.get("CFLAGS", []))
    raw_cxxflags = _resolve_flags(ctx.prefix, cc_config.get("CXXFLAGS", []))
    raw_ldflags = _resolve_flags(ctx.prefix, cc_config.get("LDFLAGS", []))
    raw_ldsharedflags = _resolve_flags(ctx.prefix, cc_config.get("LDSHAREDFLAGS", []))
    arflags = _resolve_flags(ctx.prefix, cc_config.get("ARFLAGS", []))

    if native_msvc:
        # Resolve native executables against the execroot; builds run from the sdist.
        cc_path = Path(resolve_sandbox_path(ctx.prefix, cc_config["CC"])).absolute()
        cxx_path = Path(resolve_sandbox_path(ctx.prefix, cc_config["CXX"])).absolute()
    else:
        # Keep the original compiler paths for the POSIX wrappers to invoke.
        # cc_path and cxx_path point to those generated wrappers.
        orig_cc = replace_placeholder(ctx.prefix, cc_config["CC"])
        orig_cxx = replace_placeholder(ctx.prefix, cc_config["CXX"])
        cc_path = wrap_compiler(
            "cc",
            orig_cc,
            raw_cflags,
            layer_bin_dir,
            ldflags=raw_ldflags,
            ldsharedflags=raw_ldsharedflags,
        ).absolute()
        cxx_path = wrap_compiler(
            "cxx",
            orig_cxx,
            raw_cxxflags,
            layer_bin_dir,
            ldflags=raw_ldflags,
            ldsharedflags=raw_ldsharedflags,
        ).absolute()

    # When the toolchain already handles C++ header hermeticity (indicated by
    # -nostdlibinc in flags), it provides libc++ headers via -isystem. We must
    # NOT add duplicate libc++ include dirs from native_deps, as the duplicate
    # -I paths break #include_next chains (libc++ wrapper headers can't reach
    # the underlying C headers from glibc). Only add non-C++ stdlib includes
    # (e.g., openblas headers) in this case.
    toolchain_provides_cxx_headers = "-nostdlibinc" in raw_cflags or "-nostdlibinc" in raw_cxxflags

    include_dirs: List[Path] = []
    seen_includes = set()
    for inc_dir_str in cc_config.get("include_dirs", []):
        inc_dir = Path(replace_placeholder(ctx.prefix, inc_dir_str)).absolute()
        if toolchain_provides_cxx_headers and ("libcxx" in str(inc_dir) or "libcxxabi" in str(inc_dir)):
            continue
        if inc_dir not in seen_includes:
            seen_includes.add(inc_dir)
            include_dirs.append(inc_dir)

    existing_c = set(raw_cflags)
    existing_cxx = set(raw_cxxflags)
    cflags = list(raw_cflags)
    cxxflags = list(raw_cxxflags)
    for inc_dir in include_dirs:
        inc_flag = f"-I{inc_dir}"
        isystem_flag = f"-isystem{inc_dir}"
        if inc_flag not in existing_c and isystem_flag not in existing_c:
            cflags.append(inc_flag)
            existing_c.add(inc_flag)
        if inc_flag not in existing_cxx and isystem_flag not in existing_cxx:
            cxxflags.append(inc_flag)
            existing_cxx.add(inc_flag)

    # POSIX wrappers add different toolchain options for executable and shared-library links.
    # Build systems pass LDFLAGS to every link, so keep those options in wrappers to
    # avoid applying them twice or to the wrong output. LDFLAGS starts with pycross's
    # library directory; runtime libraries are added below.
    runtime_libs = [Path(replace_placeholder(ctx.prefix, lib)).absolute() for lib in cc_config.get("runtime_libs", [])]
    ldflags = [f"-L{layer_lib_dir}", *(str(lib) for lib in runtime_libs)]

    ar = replace_placeholder(ctx.prefix, cc_config.get("AR", ""))
    ar_list, ranlib_path = parse_ar_and_guess_ranlib(ar)

    cc_layer = CcLayerState(
        cc_path=cc_path,
        cxx_path=cxx_path,
        cflags=cflags,
        cxxflags=cxxflags,
        ldflags=ldflags,
        ldsharedflags=raw_ldsharedflags,
        ar_list=ar_list,
        arflags=arflags,
        ranlib_path=ranlib_path,
        include_dirs=include_dirs,
        layer_lib_dir=layer_lib_dir,
        runtime_libs=runtime_libs,
    )
    ctx.cc_layer = cc_layer

    ctx.sysconfig_vars.update(
        {
            "CC": str(cc_path),
            "CXX": str(cxx_path),
            "CFLAGS": join_flags(cflags),
            "CXXFLAGS": join_flags(cxxflags),
            "LDFLAGS": join_flags(ldflags),
            "AR": ar,
            "ARFLAGS": join_flags(arflags),
        }
    )
    for env_key in CC_ENV_KEYS:
        if env_key in ctx.sysconfig_vars:
            ctx.build_env[env_key] = ctx.sysconfig_vars[env_key]

    if ctx.sysconfig_vars.get("MACHDEP") == "darwin":
        # Link extensions as MH_BUNDLE like CPython and the meson builder, not
        # -shared (MH_DYLIB).
        ctx.sysconfig_vars["LDSHARED"] = shlex.join([str(cc_path), *ldflags, "-bundle", "-undefined", "dynamic_lookup"])
        ctx.sysconfig_vars["LDCXXSHARED"] = shlex.join(
            [str(cxx_path), *ldflags, "-bundle", "-undefined", "dynamic_lookup"]
        )
    elif not native_msvc:
        # POSIX wrappers append the toolchain's shared-library link flags when
        # `-shared` is present, so only pass `-shared` here.
        ctx.sysconfig_vars["LDSHARED"] = shlex.join([str(cc_path), "-shared"])
        ctx.sysconfig_vars["LDCXXSHARED"] = shlex.join([str(cxx_path), "-shared"])

    # Set library search paths and the compiler environment for build subprocesses.
    inherited_path = ctx.build_env.get("PATH", "")
    build_env_update = {
        "PYCROSS_LIBRARY_PATH": str(layer_lib_dir),
        "PYCROSS_INCLUDE_PATH": os.pathsep.join(str(p) for p in include_dirs),
    }
    if native_msvc:
        raw_msvc_env = cc_config["msvc_env"]
        msvc_env = _resolve_msvc_environment(ctx, raw_msvc_env, inherited_path)
        # Custom toolchains can omit SDK variables. Tell setuptools to use the
        # prepared SDK only when the full environment is available; inherited
        # PATH alone does not establish that the toolchain supplied an SDK PATH.
        if raw_msvc_env.get("PATH") and all(msvc_env.get(key) for key in ("PATH", "INCLUDE", "LIB")):
            msvc_env["DISTUTILS_USE_SDK"] = "1"
        build_env_update.update(msvc_env)
    else:
        build_env_update["PATH"] = os.pathsep.join((str(layer_bin_dir), inherited_path))

    ctx.build_env.update(build_env_update)
    return cc_layer
