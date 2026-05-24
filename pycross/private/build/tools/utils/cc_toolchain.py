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


def wrap_compiler(lang: str, cc_exe: str, cflags: str, python_exe: Path, bin_dir: Path) -> Path:
    """Generate custom compiler wrapper scripts to filter Apple linker compatibility flags."""
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

                filtered_args = []
                for arg in sys.argv[1:]:
                    if arg in (
                        "-Wl,--start-group",
                        "-Wl,--end-group",
                        "-Wl,-start_group",
                        "-Wl,-end_group",
                        "-Wl,--as-needed",
                        "-Wl,--allow-shlib-undefined",
                        "-Wl,-O1"
                    ):
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
    hook_bin_dir = ctx.temp_dir / "cc_hook" / "bin"
    hook_include_dir = ctx.temp_dir / "cc_hook" / "include"
    hook_lib_dir = ctx.temp_dir / "cc_hook" / "lib"
    hook_bin_dir.mkdir(parents=True, exist_ok=True)
    hook_include_dir.mkdir(parents=True, exist_ok=True)
    hook_lib_dir.mkdir(parents=True, exist_ok=True)

    for lib_path_str in cc_config.get("static_libs", []) + cc_config.get("shared_libs", []):
        lib_path = Path(replace_placeholder(ctx.prefix, lib_path_str))
        dest = hook_lib_dir / lib_path.name
        if not dest.exists():
            dest.symlink_to(lib_path.absolute())

    orig_cc = replace_placeholder(ctx.prefix, cc_config["CC"])
    orig_cxx = replace_placeholder(ctx.prefix, cc_config["CXX"])
    cflags = replace_placeholder(ctx.prefix, cc_config["CFLAGS"])

    wrapped_cc = wrap_compiler("cc", orig_cc, cflags, ctx.exec_python, hook_bin_dir)
    wrapped_cxx = wrap_compiler("cxx", orig_cxx, cflags, ctx.exec_python, hook_bin_dir)

    extra_includes = []
    for inc_dir_str in cc_config.get("include_dirs", []):
        inc_dir = Path(replace_placeholder(ctx.prefix, inc_dir_str))
        extra_includes.append(f"-I{inc_dir.absolute()}")
    extra_includes_str = " ".join(extra_includes)

    # Filter out empty standard C++ library stub directories from LDFLAGS and LDSHAREDFLAGS
    def filter_cxx_stub_paths(flags_str: str) -> str:
        parts = flags_str.split()
        filtered = []
        for p in parts:
            if p.startswith("-L") and (
                "libcxx_library_search_directory" in p or "libunwind_library_search_directory" in p
            ):
                continue
            filtered.append(p)
        return " ".join(filtered)

    ldflags = (
        filter_cxx_stub_paths(replace_placeholder(ctx.prefix, cc_config["LDFLAGS"])) + f" -L{hook_lib_dir.absolute()}"
    )
    ldsharedflags = (
        filter_cxx_stub_paths(replace_placeholder(ctx.prefix, cc_config["LDSHAREDFLAGS"]))
        + f" -L{hook_lib_dir.absolute()}"
    )

    ctx.sysconfig_vars.update(
        {
            "CC": str(wrapped_cc.absolute()),
            "CXX": str(wrapped_cxx.absolute()),
            "CFLAGS": cflags
            + f" -I{hook_include_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "CXXFLAGS": replace_placeholder(ctx.prefix, cc_config["CXXFLAGS"])
            + f" -I{hook_include_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "LDFLAGS": ldflags,
            "LDSHAREDFLAGS": ldsharedflags,
            "AR": replace_placeholder(ctx.prefix, cc_config["AR"]),
            "ARFLAGS": replace_placeholder(ctx.prefix, cc_config["ARFLAGS"]),
        }
    )
    # Propagate the compiled CC toolchain flags directly to the shell environment dictionary
    # so that downstream non-python builders (like Meson/Ninja) receive them cleanly!
    for env_key in ["CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "LDSHAREDFLAGS", "AR", "ARFLAGS"]:
        if env_key in ctx.sysconfig_vars:
            ctx.build_env[env_key] = ctx.sysconfig_vars[env_key]

    ctx.sysconfig_vars["LDSHARED"] = " ".join([ctx.sysconfig_vars["CC"], ctx.sysconfig_vars["LDSHAREDFLAGS"]])
    if ctx.sysconfig_vars.get("MACHDEP") == "darwin":
        ctx.sysconfig_vars["LDSHARED"] += " -Wl,-undefined,dynamic_lookup"
    ctx.sysconfig_vars["LDCXXSHARED"] = ctx.sysconfig_vars["LDSHARED"]

    include_paths = [str(hook_include_dir.absolute())] + [
        str(Path(replace_placeholder(ctx.prefix, p)).absolute()) for p in cc_config.get("include_dirs", [])
    ]
    ctx.build_env.update(
        {
            "PATH": f"{hook_bin_dir.absolute()}:{ctx.build_env.get('PATH', '')}",
            "PYCROSS_LIBRARY_PATH": str(hook_lib_dir.absolute()),
            "PYCROSS_INCLUDE_PATH": ":".join(include_paths),
            "CC": ctx.sysconfig_vars["CC"],
            "CXX": ctx.sysconfig_vars["CXX"],
            "CFLAGS": ctx.sysconfig_vars["CFLAGS"],
            "CXXFLAGS": ctx.sysconfig_vars["CXXFLAGS"],
            "LDFLAGS": ctx.sysconfig_vars["LDFLAGS"],
            "LDSHAREDFLAGS": ctx.sysconfig_vars["LDSHAREDFLAGS"],
        }
    )
