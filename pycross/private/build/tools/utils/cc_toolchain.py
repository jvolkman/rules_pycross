import shlex
import textwrap
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder


def get_wrapper_flags(cflags: str) -> List[str]:
    """Extract target and sysroot flags to forward to compiler wrappers."""
    possible_flags = ["-target", "--target", "--sysroot", "-isysroot"]
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
    lang: str, cc_exe: str, cflags: str, python_exe: Path, bin_dir: Path
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
    wrapper_path = bin_dir / wrapper_name

    with open(wrapper_path, "w") as f:
        f.write(
            textwrap.dedent(
                f"""\
                #!{python_exe.absolute()} -S
                import os
                import sys

                cc_exe = "{cc_exe}"

                skip_flags = {{
                    "-Wl,--start-group",
                    "-Wl,--end-group",
                    "-Wl,-start_group",
                    "-Wl,-end_group",
                    "-Wl,--as-needed",
                    "-Wl,--allow-shlib-undefined",
                    "-Wl,-O1",
                }}

                filtered_args = []
                for arg in sys.argv[1:]:
                    if arg in skip_flags:
                        continue
                    filtered_args.append(arg)

                os.execv(cc_exe, [cc_exe] + {repr(wrapper_flags)} + filtered_args)
                """
            )
        )

    wrapper_path.chmod(0o755)
    return wrapper_path


def setup_cc_mixin(ctx: BuildContext, cc_config: Dict[str, Any]) -> None:
    """Populate environment parameters and wrappers for Bazel CC Toolchains."""
    mixin_bin_dir = ctx.temp_dir / "cc_mixin" / "bin"
    mixin_include_dir = ctx.temp_dir / "cc_mixin" / "include"
    mixin_lib_dir = ctx.temp_dir / "cc_mixin" / "lib"
    mixin_bin_dir.mkdir(parents=True, exist_ok=True)
    mixin_include_dir.mkdir(parents=True, exist_ok=True)
    mixin_lib_dir.mkdir(parents=True, exist_ok=True)

    for lib_path_str in cc_config.get("static_libs", []) + cc_config.get("shared_libs", []):
        lib_path = Path(replace_placeholder(ctx.prefix, lib_path_str))
        dest = mixin_lib_dir / lib_path.name
        if not dest.exists():
            dest.symlink_to(lib_path.absolute())

    orig_cc = replace_placeholder(ctx.prefix, cc_config["CC"])
    orig_cxx = replace_placeholder(ctx.prefix, cc_config["CXX"])
    cflags = replace_placeholder(ctx.prefix, cc_config["CFLAGS"])

    wrapped_cc = wrap_compiler("cc", orig_cc, cflags, ctx.exec_python, mixin_bin_dir)
    wrapped_cxx = wrap_compiler("cxx", orig_cxx, cflags, ctx.exec_python, mixin_bin_dir)

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
        if toolchain_provides_cxx_headers and (
            "libcxx" in str(inc_dir) or "libcxxabi" in str(inc_dir)
        ):
            continue
        extra_includes.append(f"-I{inc_dir.absolute()}")
    extra_includes_str = " ".join(extra_includes)

    ldflags = (
        replace_placeholder(ctx.prefix, cc_config["LDFLAGS"]) + f" -L{mixin_lib_dir.absolute()}"
    )
    ldsharedflags = (
        replace_placeholder(ctx.prefix, cc_config["LDSHAREDFLAGS"])
        + f" -L{mixin_lib_dir.absolute()}"
    )

    # Append C++ static runtime libraries directly by full path to LDFLAGS and
    # LDSHAREDFLAGS. This replicates Bazel's static_link_cpp_runtimes behavior
    # and ensures all builders (Meson, Maturin, setuptools) can link the C++
    # runtime without needing -l flags or specific library naming conventions.
    runtime_libs = cc_config.get("runtime_libs", [])
    if runtime_libs:
        runtime_lib_flags = " ".join(
            str(Path(replace_placeholder(ctx.prefix, lib)).absolute())
            for lib in runtime_libs
        )
        ldflags += f" {runtime_lib_flags}"
        ldsharedflags += f" {runtime_lib_flags}"

    ctx.sysconfig_vars.update(
        {
            "CC": str(wrapped_cc.absolute()),
            "CXX": str(wrapped_cxx.absolute()),
            "CFLAGS": cflags
            + f" -I{mixin_include_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "CXXFLAGS": replace_placeholder(ctx.prefix, cc_config["CXXFLAGS"])
            + f" -I{mixin_include_dir.absolute()}"
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

    ctx.sysconfig_vars["LDSHARED"] = " ".join([ctx.sysconfig_vars["CC"], ctx.sysconfig_vars["LDSHAREDFLAGS"]])
    if ctx.sysconfig_vars.get("MACHDEP") == "darwin":
        ctx.sysconfig_vars["LDSHARED"] += " -Wl,-undefined,dynamic_lookup"
    ctx.sysconfig_vars["LDCXXSHARED"] = ctx.sysconfig_vars["LDSHARED"]

    include_paths = [str(mixin_include_dir.absolute())] + [
        str(Path(replace_placeholder(ctx.prefix, p)).absolute()) for p in cc_config.get("include_dirs", [])
    ]
    ctx.build_env.update(
        {
            "PATH": f"{mixin_bin_dir.absolute()}:{ctx.build_env.get('PATH', '')}",
            "PYCROSS_LIBRARY_PATH": str(mixin_lib_dir.absolute()),
            "PYCROSS_INCLUDE_PATH": ":".join(include_paths),
            "CC": ctx.sysconfig_vars["CC"],
            "CXX": ctx.sysconfig_vars["CXX"],
            "CFLAGS": ctx.sysconfig_vars["CFLAGS"],
            "CXXFLAGS": ctx.sysconfig_vars["CXXFLAGS"],
            "LDFLAGS": ctx.sysconfig_vars["LDFLAGS"],
            "LDSHAREDFLAGS": ctx.sysconfig_vars["LDSHAREDFLAGS"],
        }
    )
