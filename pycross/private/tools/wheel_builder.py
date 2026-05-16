"""
A PEP 517 wheel builder that supports (or tries to) cross-platform builds.
"""

import json
import os
import shutil
import subprocess
import sys
import sysconfig
import tarfile
import tempfile
import textwrap
import traceback
import zipfile
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Mapping
from typing import NoReturn
from typing import Optional
from typing import Sequence
from typing import Tuple
from typing import Union

from build import ProjectBuilder
from packaging.utils import parse_wheel_filename
from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.crossenv.utils import find_sysconfig_data
from pycross.private.tools.target_environment import TargetEnv

_COLORS = {
    "red": "\33[91m",
    "green": "\33[92m",
    "yellow": "\33[93m",
    "bold": "\33[1m",
    "dim": "\33[2m",
    "underline": "\33[4m",
    "reset": "\33[0m",
}
_NO_COLORS = {color: "" for color in _COLORS}


def _init_colors() -> Dict[str, str]:
    if "NO_COLOR" in os.environ:
        if "FORCE_COLOR" in os.environ:
            return _NO_COLORS
    elif "FORCE_COLOR" in os.environ or sys.stdout.isatty():
        return _COLORS
    return _NO_COLORS


_STYLES = _init_colors()


def _warn(msg: str) -> None:  # pragma: no cover
    """
    Print a warning message. Will color the output when writing to a TTY.
    :param msg: Warning message
    """
    print("{yellow}WARNING{reset} {}".format(msg, **_STYLES))


def _error(msg: str, code: int = 1) -> NoReturn:  # pragma: no cover
    """
    Print an error message and exit. Will color the output when writing to a TTY.
    :param msg: Error message
    :param code: Error code
    """
    print("{red}ERROR{reset} {}".format(msg, **_STYLES))
    raise SystemExit(code)


def relpath(path: Path, start: Path) -> Path:
    return Path(os.path.relpath(path, start))


def determine_target_path_from_exec(exec_python_exe: Path, target_python_exe: Path) -> List[Path]:
    query_args = (
        exec_python_exe,
        "-c",
        "import json, sys; print(json.dumps(dict(exec=sys.executable, path=sys.path)))",
    )
    try:
        out_json = subprocess.check_output(args=query_args, env={})
        query_result = json.loads(out_json)
    except subprocess.CalledProcessError as cpe:
        print("Failed to query exec_python for target path")
        print(cpe.output.decode(), file=sys.stderr)
        raise

    exec_path = Path(query_result["exec"]).resolve()
    sys_path = [Path(p).resolve() for p in query_result["path"]]
    target_exec_resolved = target_python_exe.resolve()

    result = []
    for p in sys_path:
        try:
            # Get the ancestor common to both sys.executable and this path entry
            common = Path(os.path.commonpath([exec_path, p])).absolute()
            # Get the depth from sys.executable to that common ancestor
            exec_depth = len(exec_path.relative_to(common).parents)
            # Get the path entry relative to that common ancestor
            rel = p.relative_to(common)
            # Construct a path with the target executable + enough ".." entries + the relative path
            up_path = Path(*[".."] * exec_depth)
            path = (target_exec_resolved / up_path / rel).resolve()
            result.append(path)

        except ValueError:
            continue

    return result


def get_target_sysconfig(
    target_sys_path: List[Path],
    exec_python_exe: Path,
    target_python_exe: Path,
) -> Dict[str, Any]:
    if exec_python_exe == target_python_exe:
        # No need to go searching if exec_python and target_python are the same.
        query_args = (
            exec_python_exe,
            "-c",
            textwrap.dedent(
                """\
            import importlib, json, sysconfig
            sysconfigdata_name = sysconfig._get_sysconfigdata_name()
            if sysconfigdata_name:
                vars = importlib.import_module(sysconfigdata_name).build_time_vars
                print(json.dumps(vars))
            else:
                print("{}")
            """
            ),
        )
        try:
            vars_json = subprocess.check_output(args=query_args)
            return json.loads(vars_json)
        except subprocess.CalledProcessError as cpe:
            print("Failed to query exec_python for sysconfig vars")
            print(cpe.output.decode(), file=sys.stderr)
            raise

    # Otherwise, search target_sys_path entries.
    # If target_sys_path is empty, we try to determine it from the exec python's sys path.

    if not target_sys_path:
        target_sys_path = determine_target_path_from_exec(exec_python_exe, target_python_exe)

    return find_sysconfig_data(target_sys_path)


def set_or_append(env: Dict[str, Any], key: str, value: str) -> None:
    if key in ("PATH", "LD_LIBRARY_PATH"):
        sep = os.pathsep
    else:
        sep = " "
    if key in env:
        env[key] += sep + value
    else:
        env[key] = value


def get_default_build_env_vars(path_dirs: List[Path]) -> Dict[str, str]:
    env = os.environ.copy()

    # Pop off environment variables that might affect our build venv or
    # leak implementation details from the rules_python stub/launcher.
    for var in (
        "PYTHONHOME",
        "PYTHONPATH",
        "PYTHONSAFEPATH",
        "RUNFILES_DIR",
        "RUNFILES_MANIFEST_FILE",
        "RUNFILES_MANIFEST_ONLY",
        "PYTHON_RUNFILES",
    ):
        env.pop(var, None)

    # set SOURCE_DATE_EPOCH to 1980 so that we can use python wheels
    # https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/python.section.md#python-setuppy-bdist_wheel-cannot-create-whl
    if "SOURCE_DATE_EPOCH" not in env:
        env["SOURCE_DATE_EPOCH"] = "315532800"

    # Python wheel metadata files can be unstable.
    # See https://bitbucket.org/pypa/wheel/pull-requests/74/make-the-output-of-metadata-files/diff
    if "PYTHONHASHSEED" not in env:
        env["PYTHONHASHSEED"] = "0"

    # Python 3.11+ supports PYTHONSAFEPATH which, when set, prevents adding unsafe entries to sys.path.
    # Ideally we would use isolated mode which is present in < 3.11, but that prevents us from specifying
    # PYTHON* variables like PYTHONHASHSEED.
    #
    # https://docs.python.org/3/using/cmdline.html#envvar-PYTHONSAFEPATH

    # Place our own directories, with possible overridden commands, at the beginning of PATH.
    path_entries = [str(pd) for pd in path_dirs]
    existing_path = env.get("PATH")
    if existing_path:
        path_entries.append(existing_path)
    env["PATH"] = os.pathsep.join(path_entries)

    return env


def replace_path_placeholders(
    data: Dict[str, Union[str, List[str]]], placeholder: str, replacement: Path
) -> Dict[str, Any]:
    replacement_str = str(replacement)
    if replacement_str.endswith("/"):
        replacement_str = replacement_str[:-1]
    result = {}
    for k, v in data.items():
        if isinstance(v, list):
            result[k] = [vi.replace(placeholder, replacement_str) for vi in v]
        else:
            result[k] = v.replace(placeholder, replacement_str)

    return result


def get_inherited_vars(target_sysconfig: Dict[str, Any]) -> Dict[str, Any]:
    inherit_names = [
        "ABIFLAGS",
        "ANDROID_API_LEVEL",
        "EXE",
        "EXT_SUFFIX",
        "LDVERSION",
        "MACHDEP",
        "MACOSX_DEPLOYMENT_TARGET",
        "Py_DEBUG",
        "SHLIB_SUFFIX",
        "VERSION",
        "HOST_GNU_TYPE",
        "MULTIARCH",
    ]

    inherited = {name: target_sysconfig.get(name) for name in inherit_names}

    # Omitting Py_ENABLE_SHARED and LIBDIR. I'm not sure why these are needed or why we'd need to link
    # to any Python shared libs.

    return inherited


def wrap_cc(
    lang: str,
    cc_exe: Path,
    wrapper_flags: List[str],
    python_exe: Path,
    bin_dir: Path,
    target_is_darwin: bool = False,
) -> Path:
    """Generate a wrapper script for a C/C++ compiler.

    Args:
        lang: "cc" or "cxx"
        cc_exe: Path to the real compiler executable
        wrapper_flags: Pre-classified flags to bake into the wrapper (from Starlark classify_flags)
        python_exe: Path to Python interpreter for the wrapper shebang
        bin_dir: Directory to write the wrapper script into
        target_is_darwin: Whether we are targeting macOS
    """
    assert lang in ("cc", "cxx")
    version_str = subprocess.check_output([cc_exe, "--version"]).decode("utf-8")
    first_line = version_str.splitlines()[0]

    needs_wrap = True
    if "clang" in first_line or "zig" in first_line:
        wrapper_name = {
            "cc": "clang",
            "cxx": "clang++",
        }[lang]
    elif "gcc" in first_line:
        wrapper_name = {
            "cc": "gcc",
            "cxx": "g++",
        }[lang]
    else:
        needs_wrap = False
        wrapper_name = os.path.basename(cc_exe)

    # Make a mutable copy so we can append without modifying the caller's list
    wrapper_flags = list(wrapper_flags)
    if "clang" in first_line or "zig" in first_line:
        wrapper_flags.append("-Qunused-arguments")
    if not needs_wrap and not wrapper_flags:
        # No reason to generate a wrapper; just return the given cc location.
        return cc_exe

    wrapper_path = bin_dir / wrapper_name

    with open(wrapper_path, "w") as f:
        f.write(
            textwrap.dedent(
                f"""\
                #!{python_exe.absolute()}
                import os
                import sys

                here = os.path.dirname(sys.argv[0])
                cc_exe = os.path.join(here, "{cc_exe}")

                args = sys.argv[1:]
                if {target_is_darwin}:
                    _GNU_LINKER_FLAGS = {{
                        "-Wl,--start-group",
                        "-Wl,--end-group",
                        "-Wl,--allow-shlib-undefined",
                        "-Wl,--fatal-warnings",
                        "-Wl,--as-needed",
                        "-Wl,--no-as-needed",
                        "--start-group",
                        "--end-group",
                        "--allow-shlib-undefined",
                        "--fatal-warnings",
                        "--as-needed",
                        "--no-as-needed",
                    }}
                    args = [a for a in args if a not in _GNU_LINKER_FLAGS]

                os.execv(cc_exe, [cc_exe] + {repr(wrapper_flags)} + args)
                """
            )
        )

    os.chmod(wrapper_path, 0o755)
    return wrapper_path


def generate_cc_wrappers(
    toolchain_vars: Dict[str, Any],
    python_exe: Path,
    bin_dir: Path,
    target_is_darwin: bool = False,
    extra_flags: Optional[List[str]] = None,
) -> Dict[str, str]:
    orig_cc = toolchain_vars["CC"]
    orig_cxx = toolchain_vars["CXX"]

    # Read pre-classified wrapper flags from the Starlark layer.
    # These are already proper lists — no string parsing needed.
    cc_wrapper_flags = list(toolchain_vars.get("CC_WRAPPER_FLAGS", []))
    cxx_wrapper_flags = list(toolchain_vars.get("CXX_WRAPPER_FLAGS", []))
    ld_wrapper_flags = list(toolchain_vars.get("LD_WRAPPER_FLAGS", []))

    if target_is_darwin:
        extra = ["-mmacosx-version-min=11.0"]
        cc_wrapper_flags.extend(extra)
        cxx_wrapper_flags.extend(extra)

    # Merge linker wrapper flags into both wrappers. Meson's compiler sanity
    # check compiles AND links a test program, so the wrapper needs linker
    # flags like -fuse-ld=, -B (CRT objects), -resource-dir, etc.
    # However, filter out C++-only flags from the C wrapper.
    _CXX_ONLY_FLAGS = {"-nostdlib++"}
    cc_ld_flags = [f for f in ld_wrapper_flags if f not in _CXX_ONLY_FLAGS]
    cc_wrapper_flags.extend(cc_ld_flags)
    cxx_wrapper_flags.extend(ld_wrapper_flags)

    if extra_flags:
        cc_wrapper_flags.extend(extra_flags)
        cxx_wrapper_flags.extend(extra_flags)

    wrapped_cc = wrap_cc("cc", orig_cc, cc_wrapper_flags, python_exe, bin_dir, target_is_darwin=target_is_darwin)
    wrapped_cxx = wrap_cc("cxx", orig_cxx, cxx_wrapper_flags, python_exe, bin_dir, target_is_darwin=target_is_darwin)
    return {
        "CC": str(wrapped_cc),
        "CXX": str(wrapped_cxx),
    }



def generate_cross_sysconfig_vars(
    toolchain_vars: Dict[str, Any],
    target_vars: Dict[str, Any],
    wrapper_vars: Dict[str, Any],
    lib_dir: Path,
    include_paths: List[Path],
    target_python_lib_dir: Optional[Path] = None,
) -> Dict[str, Any]:
    sysconfig_vars = toolchain_vars.copy()
    sysconfig_vars.update(wrapper_vars)
    sysconfig_vars.update(get_inherited_vars(target_vars))

    # wheel_build.bzl gives us LDSHAREDFLAGS, but Python wants LDSHARED which is a combination of CC and LDSHAREDFLAGS
    sysconfig_vars["LDSHARED"] = " ".join([sysconfig_vars["CC"], sysconfig_vars["LDSHAREDFLAGS"]])
    del sysconfig_vars["LDSHAREDFLAGS"]

    # On macOS, Python C extension shared libraries reference Python API symbols (e.g. PyDict_New)
    # that are resolved at load time by the interpreter. Tell the linker to allow these undefined
    # symbols rather than erroring at link time.
    if sysconfig_vars.get("MACHDEP") == "darwin":
        sysconfig_vars["LDSHARED"] += " -Wl,-undefined,dynamic_lookup"
        # Strip GNU-style double-dash linker flags (-Wl,--*) which are unsupported by macOS ld64
        ldshared_parts = sysconfig_vars["LDSHARED"].split()
        ldshared_parts = [p for p in ldshared_parts if not p.startswith("-Wl,--")]
        sysconfig_vars["LDSHARED"] = " ".join(ldshared_parts)

    # Always strip -lpython from LDSHARED and clear LIBPYTHON. Python C extensions
    # on both Linux and macOS must not be hardlinked against libpython at compile-time,
    # as symbols are resolved dynamically by the loading Python interpreter.
    # Linking against libpython is forbidden for manylinux wheels and causes auditwheel repair failures.
    ldshared_parts = sysconfig_vars["LDSHARED"].split()
    ldshared_parts = [p for p in ldshared_parts if not p.startswith("-lpython")]
    sysconfig_vars["LDSHARED"] = " ".join(ldshared_parts)
    sysconfig_vars["LIBPYTHON"] = ""

    # https://github.com/pypa/distutils/issues/283
    sysconfig_vars["LDCXXSHARED"] = sysconfig_vars["LDSHARED"]

    # Note: Python's distutils uses CFLAGS for both C and C++ compilation.
    # Extra C++ flags (e.g., libcxx include paths) are baked into the CXX
    # compiler wrapper instead, since adding C++ headers to CFLAGS would
    # break C compilation.

    # Strip linker-only flags from CFLAGS/CXXFLAGS. Bazel's C++ toolchain
    # may include -Wl,* flags (e.g., -Wl,-s for stripping) in compiler flags,
    # but distutils passes CFLAGS to compile-only invocations where these
    # cause -Werror,-Wunused-command-line-argument errors.
    for flag_var in ("CFLAGS", "CXXFLAGS"):
        if flag_var in sysconfig_vars:
            sysconfig_vars[flag_var] = " ".join(
                f for f in sysconfig_vars[flag_var].split() if not f.startswith("-Wl,")
            )

    # Add search paths for listed native deps
    for include_path in include_paths:
        sysconfig_vars["CFLAGS"] += f" -I{include_path}"
        if "CXXFLAGS" in sysconfig_vars:
            sysconfig_vars["CXXFLAGS"] += f" -I{include_path}"
    sysconfig_vars["CFLAGS"] += f" -L{lib_dir}"
    if "CXXFLAGS" in sysconfig_vars:
        sysconfig_vars["CXXFLAGS"] += f" -L{lib_dir}"
    sysconfig_vars["LDSHARED"] += f" -L{lib_dir}"

    if target_python_lib_dir:
        sysconfig_vars["CFLAGS"] += f" -L{target_python_lib_dir}"
        if "CXXFLAGS" in sysconfig_vars:
            sysconfig_vars["CXXFLAGS"] += f" -L{target_python_lib_dir}"
        sysconfig_vars["LDSHARED"] += f" -L{target_python_lib_dir}"

    return sysconfig_vars






def generate_bin_tools(bin_dir: Path, toolchain_vars: Dict[str, str]) -> None:
    # The bazel CC toolchains don't provide ranlib (as far as I can tell), and
    # we don't want to use the host ranlib. So we place a no-op in PATH.
    ranlib = bin_dir / "ranlib"
    ranlib.symlink_to("/bin/true")

    # Some packages execute ar from the path rather than looking at the AR var, so we add our AR to the path
    # if it exists.
    ar_path = toolchain_vars.get("AR")
    if ar_path:
        ar = bin_dir / "ar"
        ar.symlink_to(ar_path)

    # Symlink python and python3 to the executing host Python interpreter.
    # This ensures that any subprocesses spawned during the build (like repair_wheel_hook)
    # that utilize #!/usr/bin/env python3 can successfully find a valid, hermetic Python
    # interpreter on PATH.
    python_symlink = bin_dir / "python"
    python3_symlink = bin_dir / "python3"
    python_symlink.symlink_to(sys.executable)
    python3_symlink.symlink_to(sys.executable)


def link_path_tools(tools_dir: Path, path_tools: List[Tuple[Path, Path]]) -> None:
    for path_tool_name, relative_path_tool_path in path_tools:
        if len(path_tool_name.parts) > 1:
            _error("path_tool name must not contain path separators")
        path_tool_in_bin = tools_dir / path_tool_name
        path_tool_in_bin.symlink_to(relative_path_tool_path)


def link_native_headers(include_dir: Path, headers: List[Path]) -> None:
    for header in headers:
        path_in_include = include_dir / header.name
        if path_in_include.exists():
            _warn(f"Not linking {header} into include directory because {header.name} already exists.")
            continue
        path_in_include.symlink_to(relpath(header, include_dir))


def link_native_libraries(lib_dir: Path, libraries: List[Path]) -> None:
    for library in libraries:
        path_in_lib = lib_dir / library.name
        if path_in_lib.exists():
            _warn(f"Not linking {library} into lib directory because {library.name} already exists.")
            continue
        path_in_lib.symlink_to(relpath(library, lib_dir))


def extract_sdist(sdist_path: Path, sdist_dir: Path) -> Path:
    if sdist_path.name.endswith(".tar.gz"):
        with tarfile.open(sdist_path, "r") as f:
            if hasattr(tarfile, "data_filter"):
                f.extraction_filter = tarfile.data_filter
            f.extractall(sdist_dir)
    elif sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path, "r") as f:
            f.extractall(sdist_dir)
    else:
        _error(f"Unsupported sdist format: {sdist_path}")

    # After extraction, there should be a `packageName-version` directory
    (extracted_dir,) = sdist_dir.glob("*")
    return extracted_dir


def run_pre_build_hooks(
    hooks: List[Path],
    temp_dir: Path,
    build_env: Dict[str, str],
    config_settings: Dict[str, Any],
) -> Tuple[Dict[str, str], Dict[str, Any]]:
    config_settings_file = temp_dir / "config_settings.json"
    env_file = temp_dir / "build_env.json"
    for hook in hooks:
        hook_env = dict(build_env)
        hook_env["PYCROSS_CONFIG_SETTINGS_FILE"] = str(config_settings_file)
        hook_env["PYCROSS_ENV_VARS_FILE"] = str(env_file)

        # Write the current build env to a file.
        with open(env_file, "w") as f:
            json.dump(build_env, f)

        # Write current config settings to a file.
        with open(config_settings_file, "w") as f:
            json.dump(config_settings, f)

        try:
            subprocess.check_output(
                args=[hook],
                env=hook_env,
                stderr=subprocess.STDOUT,
            )
        except subprocess.CalledProcessError as cpe:
            print("===== PRE-BUILD HOOK FAILED =====", file=sys.stderr)
            print(cpe.output.decode(), file=sys.stderr)
            raise

        # Read post-hook build.env and update our own environment variables.
        with open(env_file, "r") as f:
            build_env = json.load(f)
            for k, v in build_env.items():
                if not (isinstance(k, str) and isinstance(v, str)):
                    _error("pre-build hook build_env.json must contain string keys and values")

        # Read post-hook config_settings.json.
        with open(config_settings_file, "r") as f:
            config_settings = json.load(f)

    return build_env, config_settings


def run_post_build_hooks(
    hooks: List[Path],
    temp_dir: Path,
    build_env: Dict[str, str],
    wheel_file: Path,
) -> Path:
    wheel_in = temp_dir / "post_wheel_in"
    wheel_out = temp_dir / "post_wheel_out"
    wheel_in.mkdir()
    wheel_out.mkdir()

    orig_wheel_file = wheel_file
    wheel_file = wheel_in / wheel_file.name
    shutil.move(orig_wheel_file, wheel_file)

    for hook in hooks:
        hook_env = dict(build_env)
        hook_env["PYCROSS_WHEEL_FILE"] = str(wheel_file)
        hook_env["PYCROSS_WHEEL_OUTPUT_ROOT"] = str(wheel_out)

        try:
            subprocess.check_output(
                args=[hook],
                env=hook_env,
                stderr=subprocess.STDOUT,
            )
        except subprocess.CalledProcessError as cpe:
            print("===== POST-BUILD HOOK FAILED =====", file=sys.stderr)
            print(cpe.output.decode(), file=sys.stderr)
            raise

        output_files = list(wheel_out.glob("*"))
        if len(output_files) > 1:
            _error("post-build hook wrote multiple files in PYCROSS_WHEEL_OUTPUT_ROOT")
        if output_files:
            hook_wheel_file = output_files[0]
            if hook_wheel_file.suffix != ".whl":
                _error(f"post-build hook wrote non-whl file: {hook_wheel_file.name}")

            # We shuffle the newly-written wheel into post_wheel_in/ and clear post_wheel_out/
            shutil.rmtree(wheel_in)
            wheel_in.mkdir()
            wheel_file = wheel_in / hook_wheel_file.name
            shutil.move(hook_wheel_file, wheel_file)
            shutil.rmtree(wheel_out)
            wheel_out.mkdir()

    return wheel_file


def check_filename_against_target(wheel_name: str, target_environment: TargetEnv) -> None:
    _, _, _, tags = parse_wheel_filename(wheel_name)
    tag_names = {str(t) for t in tags}
    if not tag_names.intersection(target_environment.compatibility_tags):
        _error(f"No tags in {wheel_name} match target environment {target_environment.name}")


def find_site_dir(env_dir: Path) -> Path:
    lib_dir = env_dir / "lib"
    try:
        return next(lib_dir.glob("python*/site-packages"))
    except StopIteration:
        raise ValueError(f"Cannot find site-packages under {env_dir}")


def build_cross_venv(
    env_dir: Path,
    exec_python_exe: Path,
    target_python_exe: Path,
    sysconfig_vars: Dict[str, Any],
    target_env: Optional[TargetEnv],
) -> None:
    sysconfig_json = env_dir / "sysconfig.json"
    with open(sysconfig_json, "w") as f:
        json.dump(sysconfig_vars, f, indent=2)

    crossenv_args = [
        exec_python_exe,
        "-m",
        "pycross.private.tools.crossenv",
        "--env-dir",
        str(env_dir),
        "--sysconfig-json",
        str(sysconfig_json),
        "--target-python",
        target_python_exe,
    ]

    if target_env:
        for tag in target_env.compatibility_tags:
            if "manylinux" in tag:
                crossenv_args.extend(
                    [
                        "--manylinux",
                        tag,
                    ]
                )

    try:
        # The new-style rules_python bootstrap (stage2) sets sys.path in-process
        # but does NOT update os.environ["PYTHONPATH"], so the crossenv subprocess
        # can't find pycross. Propagate non-stdlib sys.path entries as PYTHONPATH.
        #
        # We exclude the current interpreter's stdlib directory (and everything
        # under it, e.g. lib-dynload) because exec_python_exe may be a different
        # Python version; mixing stdlib paths across versions causes C-extension
        # magic-number mismatches (e.g. _sre.MAGIC AssertionError).
        stdlib = sysconfig.get_path("stdlib")
        non_stdlib = [p for p in sys.path if p and not p.startswith(stdlib)]
        crossenv_env = dict(os.environ)
        existing_pythonpath = crossenv_env.get("PYTHONPATH", "")
        non_stdlib_str = os.pathsep.join(non_stdlib)
        crossenv_env["PYTHONPATH"] = non_stdlib_str + (os.pathsep + existing_pythonpath if existing_pythonpath else "")
        subprocess.check_output(args=crossenv_args, env=crossenv_env, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as cpe:
        print("===== CROSSENV FAILED =====", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise


def build_standard_venv(env_dir: Path, exec_python_exe: Path, sysconfig_vars: Dict[str, Any]) -> None:
    venv_args = [
        exec_python_exe,
        "-m",
        "venv",
        "--symlinks",
        "--without-pip",
        str(env_dir),
    ]

    try:
        subprocess.check_output(args=venv_args, env=os.environ, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as cpe:
        print("===== VENV FAILED =====", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise

    # Setup our customized sysconfig vars
    site_dir = find_site_dir(env_dir)
    with open(site_dir / "_pycross_sysconfigdata.py", "w") as f:
        f.write(f"build_time_vars = {repr(sysconfig_vars)}\n")
    with open(site_dir / "_pycross_sysconfigdata.pth", "w") as f:
        f.write('import sysconfig; sysconfig._get_sysconfigdata_name = lambda: "_pycross_sysconfigdata"; sysconfig._CONFIG_VARS = None\n')


def build_venv(
    bazel_root: Path,
    env_dir: Path,
    exec_python_exe: Path,
    target_python_exe: Path,
    sysconfig_vars: Dict[str, Any],
    path: List[Path],
    target_env: Optional[TargetEnv],
    always_use_crossenv: bool = False,
) -> None:
    if exec_python_exe != target_python_exe or always_use_crossenv:
        build_cross_venv(env_dir, exec_python_exe, target_python_exe, sysconfig_vars, target_env)
    else:
        build_standard_venv(env_dir, exec_python_exe, sysconfig_vars)

    site_dir = find_site_dir(env_dir)

    # Add a pth file to override sys.prefix and sys.exec_prefix.
    with open(site_dir / "_pycross_sys_prefix.pth", "w") as f:
        f.write(f'import sys; sys.prefix = sys.exec_prefix = "{env_dir}"\n')

    # If we're using a Bazel-provided python (i.e., not system python), set sys.base_prefix to a path
    # relative to the sdist root in an attempt to keep non-reproducible paths out of binaries.
    if bazel_root in target_python_exe.parents:
        # base_prefix and base_exec_prefix are the grandparent directory of the executable.
        # E.g., if the executable is at python310/bin/python3, python310 is base_prefix.
        # target_python_exe should already be a relative path.
        with open(site_dir / "_pycross_sys_base_prefix.pth", "w") as f:
            f.write(f'import sys; sys.base_prefix = sys.base_exec_prefix = "{target_python_exe.parent.parent}"\n')

    # Add build dependencies as site directories so nested .pth files from those
    # dependencies are processed when Python initializes the build venv.
    with open(site_dir / "deps.pth", "w") as f:
        for dep_path in path:
            rel_dep_path = os.path.relpath(dep_path, site_dir)
            f.write(f"import os, site; site.addsitedir(os.path.join(sitedir, {rel_dep_path!r}))\n")


def validate_required_deps(
    env_dir: Path,
    build_env: Dict[str, str],
    required_deps: List[str],
) -> None:
    """Validate that required dependencies are available in the build venv.

    Each entry in required_deps is a PEP 508 requirement specifier, e.g.:
      "meson-python"
      "setuptools>=68.0"
      "cython>=3.0,<4.0"

    Validation runs inside the build venv's Python so that importlib.metadata
    sees exactly the packages that will be available during the build.
    """
    if not required_deps:
        return

    python_exe = env_dir / "bin" / "python"

    # Build a small validation script that checks each requirement.
    script = textwrap.dedent("""\
        import json
        import sys
        from importlib.metadata import version, PackageNotFoundError
        from packaging.requirements import Requirement

        errors = []
        for spec_str in json.loads(sys.argv[1]):
            req = Requirement(spec_str)
            try:
                installed_version = version(req.name)
            except PackageNotFoundError:
                errors.append(f"Missing required build dependency: {spec_str}")
                continue
            if not req.specifier.contains(installed_version):
                errors.append(
                    f"Build dependency {req.name}=={installed_version} "
                    f"does not satisfy requirement: {spec_str}"
                )
        if errors:
            print("\\n".join(errors), file=sys.stderr)
            sys.exit(1)
    """)

    try:
        subprocess.check_output(
            [str(python_exe), "-c", script, json.dumps(required_deps)],
            env=build_env,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        _error(
            "Required build dependency check failed:\n"
            + e.output.decode().strip()
        )


def build_wheel(
    env_dir: Path,
    wheel_dir: Path,
    sdist_dir: Path,
    build_env: Dict[str, str],
    config_settings: Dict[str, str],
    debug: bool = False,
) -> Path:
    python_exe = env_dir / "bin" / "python"

    def _subprocess_runner(
        cmd: Sequence[str],
        cwd: Optional[str] = None,
        extra_environ: Optional[Mapping[str, str]] = None,
    ):
        """The default method of calling the wrapper subprocess."""
        cmd = list(cmd)
        env = build_env.copy()

        if extra_environ:
            env.update(extra_environ)

        if debug:
            print("===== BUILD ENV =====", file=sys.stdout)
            for k, v in sorted(env.items()):
                print(f"  {k}={v}", file=sys.stdout)
            try:
                site = subprocess.check_output([cmd[0], "-m", "site"], cwd=cwd, env=env, stderr=subprocess.STDOUT)
                print("===== BUILD SITE =====", file=sys.stdout)
                print(site.decode(), file=sys.stdout)
            except subprocess.CalledProcessError as cpe:
                print("Warning: failed to collect site output", file=sys.stderr)
                print(cpe.output.decode(), file=sys.stderr)
        try:
            output = subprocess.check_output(cmd, cwd=cwd, env=env, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as cpe:
            print("===== BUILD FAILED =====", file=sys.stderr)
            print(cpe.output.decode(), file=sys.stderr)
            raise

        if debug:
            print(output.decode(), file=sys.stdout)

    builder = ProjectBuilder(
        source_dir=sdist_dir,
        python_executable=str(python_exe),
        runner=_subprocess_runner,
    )

    try:
        wheel_file = builder.build(
            distribution="wheel",
            output_directory=wheel_dir,
            config_settings=config_settings,
        )

    except Exception as e:  # pragma: no cover
        # Debugging helper: Print meson-log.txt on failure if it exists
        try:
            for log_path in sdist_dir.glob("**/meson-logs/meson-log.txt"):
                if log_path.exists():
                    print(f"\n===== FOUND MESON LOG: {log_path} =====", file=sys.stdout)
                    with open(log_path, "r") as lf:
                        print(lf.read(), file=sys.stdout)
                    print("======================================\n", file=sys.stdout)
        except Exception as log_err:
            print(f"Warning: failed to collect meson-log.txt: {log_err}", file=sys.stderr)

        tb = traceback.format_exc().strip("\n")
        print("\n{dim}{}{reset}\n".format(tb, **_STYLES))
        _error(str(e))
        raise  # Won't happen because _error exits, but it makes static analyzers happy.

    return Path(wheel_file)


def init_build_env_vars(
    args: Any,
    temp_dir: Path,
    path_dirs: List[Path],
    include_dirs: List[Path],
    lib_dirs: List[Path],
    bazel_root: Path,
) -> Dict[str, str]:
    vars = get_default_build_env_vars(path_dirs)
    if args.build_env:
        with open(args.build_env, "r") as f:
            additional_build_env = replace_path_placeholders(
                json.load(f),
                "$$EXT_BUILD_ROOT$$",
                bazel_root,
            )
        for key, val in additional_build_env.items():
            set_or_append(vars, key, val)

    vars["PYCROSS_INCLUDE_PATH"] = os.pathsep.join(map(str, include_dirs))
    vars["PYCROSS_LIBRARY_PATH"] = os.pathsep.join(map(str, lib_dirs))
    vars["PYCROSS_BAZEL_ROOT"] = str(bazel_root)
    vars["PYCROSS_BUILD_ROOT"] = str(temp_dir)

    return vars


def init_config_settings(args: Any, bazel_root: Path) -> Dict[str, Any]:
    if not args.config_settings:
        return {}

    with open(args.config_settings, "r") as f:
        config_settings = replace_path_placeholders(
            json.load(f),
            "$$EXT_BUILD_ROOT$$",
            bazel_root,
        )

    return config_settings


def setup_recipe_data(args: Any, temp_dir: Path, bazel_root: Path) -> Optional[Path]:
    """Stage recipe data files into a known directory.

    Reads the recipe data manifest (logical name -> sandbox path) and copies
    each file into temp_dir/recipe_data/<logical_name>. Returns the recipe
    data directory path, or None if no manifest was provided.
    """
    if not args.recipe_data_manifest:
        return None

    with open(args.recipe_data_manifest, "r") as f:
        manifest = json.load(f)

    if not manifest:
        return None

    data_dir = temp_dir / "recipe_data"
    for name, path in manifest.items():
        dest = data_dir / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        src = bazel_root / path if not Path(path).is_absolute() else Path(path)
        shutil.copy2(src, dest)

    return data_dir


def load_target_environment(args: Any) -> Optional[TargetEnv]:
    if args.target_environment_file:
        with open(args.target_environment_file, "r") as f:
            return TargetEnv.from_dict(json.load(f))


def load_sysconfig_vars(args: Any, bazel_root: Path) -> Dict[str, Any]:
    with open(args.sysconfig_vars, "r") as f:
        vars = json.load(f)
    return replace_path_placeholders(
        vars,
        "$$EXT_BUILD_ROOT$$",
        bazel_root,
    )


def execroot_prefix(workspace_name: str) -> Path:
    return Path("..") / "bazel-execroot" / workspace_name


def _sanitize_wheel(wheel_file: Path, temp_dir: Path, target_python_exe: Path) -> None:
    """Strip non-reproducible absolute paths from text files in the wheel.

    This rewrites the wheel in-place, replacing sandbox-specific paths
    with stable placeholders for reproducibility.
    """
    # Binary file extensions that should never be modified
    _BINARY_EXTENSIONS = frozenset([
        ".so", ".dylib", ".dll", ".pyd",
        ".pyc", ".pyo",
        ".png", ".jpg", ".jpeg", ".gif", ".ico", ".bmp", ".webp",
        ".woff", ".woff2", ".ttf", ".otf", ".eot",
        ".wasm", ".dat", ".bin",
        ".gz", ".bz2", ".xz", ".zip", ".tar",
    ])

    # Compute patterns to replace
    temp_dir_str = os.fspath(temp_dir.resolve())
    target_python_root = os.fspath(target_python_exe.resolve().parent.parent)

    with tempfile.TemporaryDirectory(prefix="sanitize_wheel") as unpack_dir:
        unpack_path = Path(unpack_dir)

        # Preserve original ZIP member info (permissions, etc.)
        member_info = {}
        with zipfile.ZipFile(wheel_file, "r") as z:
            for info in z.infolist():
                member_info[info.filename] = info
            z.extractall(unpack_path)

        modified = False
        for root, dirs, files in os.walk(unpack_path):
            for file in files:
                file_path = Path(root) / file
                if file_path.suffix.lower() in _BINARY_EXTENSIONS:
                    continue
                try:
                    content = file_path.read_bytes()
                    # Quick binary check: if there are null bytes, skip
                    if b"\x00" in content[:8192]:
                        continue
                    text = content.decode("utf-8")
                except (UnicodeDecodeError, OSError):
                    continue

                original = text
                if temp_dir_str in text:
                    text = text.replace(temp_dir_str, "/tmp/rules_pycross_build")
                if target_python_root in text:
                    text = text.replace(target_python_root, "/rules_pycross_target_python")

                if text != original:
                    file_path.write_text(text, encoding="utf-8")
                    modified = True

        if modified:
            # Repack, preserving original ZIP member metadata
            os.remove(wheel_file)
            with zipfile.ZipFile(wheel_file, "w", zipfile.ZIP_DEFLATED) as z:
                for root, dirs, files in os.walk(unpack_path):
                    for file in files:
                        full_path = Path(root) / file
                        rel_path = str(full_path.relative_to(unpack_path))
                        # Reuse original ZipInfo if available to preserve permissions
                        if rel_path in member_info:
                            info = member_info[rel_path]
                            z.writestr(info, full_path.read_bytes())
                        else:
                            z.write(full_path, rel_path)


def main(args: Any, temp_dir: Path, is_debug: bool) -> None:
    # Paths passed into this action will be relative to bazel's execroot.
    # But we need to build the wheel from within the extracted sdist directory.
    # So here's the plan:
    # * Build a temp area. In here we'll have sdist, env (virtual environment) and some
    #   other stuff.
    # * Extract the sdist.
    # * Link the bazel execroot to the temp area as `bazel_execroot`.
    # * Change this process' directory to the sdist directory.
    # * Prefix all input paths with `../bazel_execroot/<workspace_name>`.
    cwd = Path.cwd()

    # Extract the sdist and rename it to 'sdist'
    sdist_dir = temp_dir / "sdist"
    _sdist_extracted_dir = extract_sdist(args.sdist, temp_dir)
    _sdist_extracted_dir.rename(sdist_dir)

    # Change into the new directory
    os.chdir(sdist_dir)
    sdist_dir = Path(".")
    temp_dir = Path("..")

    # Add the execroot symlink into our temp area. We link to the parent of current cwd since
    # current cwd is something like <sandbox>/execroot/<workspace_name>
    (temp_dir / "bazel-execroot").symlink_to(cwd.parent)

    # This is the prefix relative to the sdist directory that we'll prepend to everything
    prefix = execroot_prefix(cwd.name).resolve()

    def mktmpdir(name: str) -> Path:
        d = temp_dir / name
        d.mkdir()
        # Return as relative from the sdist directory
        return Path("..") / name

    wheel_dir = mktmpdir("wheel").resolve()
    bin_dir = mktmpdir("bin").resolve()
    tools_dir = mktmpdir("tools").resolve()
    build_env_dir = mktmpdir("env").resolve()
    include_dir = mktmpdir("include").resolve()
    lib_dir = mktmpdir("lib").resolve()

    config_settings = init_config_settings(args, prefix)
    toolchain_sysconfig_vars = load_sysconfig_vars(args, prefix)
    target_environment = load_target_environment(args)

    include_paths = list(args.native_include_path)
    include_paths.append(include_dir)

    build_env_vars = init_build_env_vars(
        args=args,
        temp_dir=temp_dir,
        path_dirs=[tools_dir, bin_dir],
        include_dirs=include_paths,
        lib_dirs=[lib_dir],
        bazel_root=prefix,
    )

    target_sysconfig_vars = get_target_sysconfig(
        target_sys_path=args.target_sys_path,
        exec_python_exe=args.exec_python_executable,
        target_python_exe=args.target_python_executable,
    )
    target_is_darwin = (target_sysconfig_vars.get("MACHDEP") == "darwin")

    target_python_lib_dir = (args.target_python_executable.parent.parent / "lib").resolve()

    extra_wrapper_flags = [f"-L{lib_dir}"]
    if target_python_lib_dir.exists():
        extra_wrapper_flags.append(f"-L{target_python_lib_dir}")

    wrapper_sysconfig_vars = generate_cc_wrappers(
        toolchain_vars=toolchain_sysconfig_vars,
        python_exe=args.exec_python_executable,
        bin_dir=bin_dir,
        target_is_darwin=target_is_darwin,
        extra_flags=extra_wrapper_flags,
    )
    build_env_vars["CC"] = wrapper_sysconfig_vars["CC"]
    build_env_vars["CXX"] = wrapper_sysconfig_vars["CXX"]
    sysconfig_vars = generate_cross_sysconfig_vars(
        toolchain_vars=toolchain_sysconfig_vars,
        target_vars=target_sysconfig_vars,
        wrapper_vars=wrapper_sysconfig_vars,
        lib_dir=lib_dir,
        include_paths=include_paths,
        target_python_lib_dir=target_python_lib_dir if target_python_lib_dir.exists() else None,
    )
    set_or_append(build_env_vars, "LDFLAGS", f"-L{lib_dir}")
    set_or_append(build_env_vars, "LD_LIBRARY_PATH", str(lib_dir))
    if target_python_lib_dir.exists():
        set_or_append(build_env_vars, "LDFLAGS", f"-L{target_python_lib_dir}")
        set_or_append(build_env_vars, "LD_LIBRARY_PATH", str(target_python_lib_dir))

    # Copy libpython shared library if needed for linking.
    # Derive the library name from the target Python version rather than hardcoding.
    py_version = target_sysconfig_vars.get("VERSION", "")
    if py_version and target_python_lib_dir.exists():
        libpython_name = f"libpython{py_version}.so"
        if not (target_python_lib_dir / libpython_name).exists():
            # Try the versioned .so.1.0 form
            for candidate in target_python_lib_dir.glob(f"libpython{py_version}.so*"):
                dest = lib_dir / libpython_name
                if not dest.exists():
                    shutil.copy(candidate, dest)
                break

    build_env_vars["PYCROSS_TARGET_PYTHON_BIN_DIR"] = str(args.target_python_executable.resolve().parent)

    target_machdep = target_sysconfig_vars.get("MACHDEP", "")
    target_multiarch = " ".join([
        target_sysconfig_vars.get("MULTIARCH") or "",
        target_sysconfig_vars.get("HOST_GNU_TYPE") or "",
    ])
    if "x86_64" in target_multiarch:
        target_cpu = "x86_64"
    elif "aarch64" in target_multiarch or "arm64" in target_multiarch:
        target_cpu = "aarch64"
    else:
        _warn(f"Could not determine target CPU from MULTIARCH={target_sysconfig_vars.get('MULTIARCH')!r}, "
              f"HOST_GNU_TYPE={target_sysconfig_vars.get('HOST_GNU_TYPE')!r}; defaulting to x86_64")
        target_cpu = "x86_64"
    build_env_vars["PYCROSS_TARGET_SYSTEM"] = target_machdep
    build_env_vars["PYCROSS_TARGET_CPU"] = target_cpu

    # Generate path tools and native dependencies
    generate_bin_tools(bin_dir, toolchain_sysconfig_vars)
    link_path_tools(tools_dir, args.path_tool)
    link_native_headers(include_dir, args.native_header)
    link_native_libraries(lib_dir, args.native_library)

    # Expose key sysconfig toolchain vars to build hooks.
    # Hooks (like the meson cross-file generator) need access to compiler flags
    # and linker commands that are derived from sysconfig. We set them in
    # build_env_vars so they're available via PYCROSS_ENV_VARS_FILE and as
    # direct env vars in the hook subprocess.
    for var in ("CFLAGS", "CXXFLAGS", "LDSHARED", "LDFLAGS", "AR"):
        val = sysconfig_vars.get(var)
        if val and var not in build_env_vars:
            build_env_vars[var] = val

    # Use crossenv if the recipe chain requests it, or if always_use_crossenv is set
    use_crossenv = args.always_use_crossenv or args.use_crossenv

    build_venv(
        bazel_root=prefix,
        env_dir=build_env_dir,
        exec_python_exe=args.exec_python_executable,
        target_python_exe=args.target_python_executable,
        sysconfig_vars=sysconfig_vars,
        path=args.python_path,
        target_env=target_environment,
        always_use_crossenv=use_crossenv,
    )

    if is_debug:
        print(f"Build environment: {build_env_dir.absolute()}")

    validate_required_deps(
        env_dir=build_env_dir,
        build_env=build_env_vars,
        required_deps=args.require_dep,
    )

    # Stage recipe data files so hooks can access them
    recipe_data_dir = setup_recipe_data(args, temp_dir, prefix)
    if recipe_data_dir:
        build_env_vars["PYCROSS_RECIPE_DATA_DIR"] = str(recipe_data_dir.resolve())

    build_env_vars, config_settings = run_pre_build_hooks(
        hooks=args.pre_build_hook,
        temp_dir=temp_dir,
        build_env=build_env_vars,
        config_settings=config_settings,
    )

    wheel_file = build_wheel(
        env_dir=build_env_dir,
        wheel_dir=wheel_dir,
        sdist_dir=sdist_dir,
        build_env=build_env_vars,
        config_settings=config_settings,
        debug=is_debug,
    )

    wheel_file = run_post_build_hooks(
        hooks=args.post_build_hook,
        temp_dir=temp_dir,
        build_env=build_env_vars,
        wheel_file=wheel_file,
    )

    if target_environment:
        check_filename_against_target(os.path.basename(wheel_file), target_environment)

    _sanitize_wheel(wheel_file, temp_dir, args.target_python_executable)

    shutil.move(wheel_file, args.wheel_file)
    with open(args.wheel_name_file, "w") as f:
        f.write(os.path.basename(wheel_file))


def parse_flags() -> Any:
    # At the time of flags parsing, we should be within .../execroot/<workspace_name>
    workspace_name = Path.cwd().name
    prefix = execroot_prefix(workspace_name)

    def sdist_rel_path(val):
        return prefix / val

    parser = FlagFileArgumentParser(description="Generate target python information.")

    parser.add_argument(
        "--always-use-crossenv",
        action="store_true",
    )

    parser.add_argument(
        "--use-crossenv",
        action="store_true",
        help="Enable crossenv sysconfig patching (set by recipe chain).",
    )

    parser.add_argument(
        "--build-env",
        type=sdist_rel_path,
        help="A JSON file containing build environment variables.",
    )

    parser.add_argument(
        "--config-settings",
        type=sdist_rel_path,
        help="A JSON file containing PEP 517 build config settings.",
    )

    parser.add_argument(
        "--exec-python-executable",
        type=sdist_rel_path,
        required=True,
    )

    parser.add_argument(
        "--native-header",
        type=sdist_rel_path,
        action="append",
        default=[],
        help="Header file (or directory of files) to link into our include directory.",
    )

    parser.add_argument(
        "--native-include-path",
        type=sdist_rel_path,
        action="append",
        default=[],
        help="Include search path to add to CFLAGS.",
    )

    parser.add_argument(
        "--native-library",
        type=sdist_rel_path,
        action="append",
        default=[],
        help="Library to link into our lib directory.",
    )

    parser.add_argument(
        "--path-tool",
        type=Path,
        nargs=2,
        action="append",
        default=[],
        help="A tool to made available in PATH when building the sdist.",
    )

    parser.add_argument(
        "--post-build-hook",
        type=sdist_rel_path,
        action="append",
        default=[],
        help="A tool to run after building the wheel.",
    )

    parser.add_argument(
        "--pre-build-hook",
        type=sdist_rel_path,
        action="append",
        default=[],
        help="A tool to run before building the sdist.",
    )

    parser.add_argument(
        "--python-path",
        type=sdist_rel_path,
        action="append",
        default=[],
        help="An entry to add to sys.path",
    )

    parser.add_argument(
        "--require-dep",
        action="append",
        default=[],
        help="A PEP 508 requirement specifier that must be satisfied by build deps (e.g. 'meson-python>=0.15').",
    )

    parser.add_argument(
        "--sdist",
        type=Path,
        required=True,
        help="The sdist path.",
    )

    parser.add_argument(
        "--sysconfig-vars",
        type=sdist_rel_path,
        required=True,
        help="A JSON file containing variable to add to sysconfig.",
    )

    parser.add_argument(
        "--target-environment-file",
        type=sdist_rel_path,
        help="A JSON file containing the target Python environment details.",
    )

    parser.add_argument(
        "--target-python-executable",
        type=sdist_rel_path,
        required=True,
    )

    parser.add_argument(
        "--target-sys-path",
        type=sdist_rel_path,
        action="append",
        default=[],
    )

    parser.add_argument(
        "--wheel-file",
        type=sdist_rel_path,
        required=True,
        help="The wheel output path.",
    )

    parser.add_argument(
        "--wheel-name-file",
        type=sdist_rel_path,
        required=True,
        help="The wheel name output path.",
    )

    parser.add_argument(
        "--recipe-data-manifest",
        type=sdist_rel_path,
        required=False,
        help="JSON manifest mapping logical names to file paths for recipe data.",
    )

    args = parser.parse_args()

    # Fix up path_tool; the second entry in each tuple should be sdist_rel_path, but the first should not.
    if args.path_tool:
        args.path_tool = [(p1, sdist_rel_path(p2)) for p1, p2 in args.path_tool]

    return args


def main_wrapper(args: Any) -> None:
    # Some older versions of Python on MacOS leak __PYVENV_LAUNCHER__ through to subprocesses.
    # When this is set, a created virtualenv will link to this value rather than sys.argv[0], which we don't want.
    # So just clear it if it exists.
    os.environ.pop("__PYVENV_LAUNCHER__", None)

    _is_debug = "RULES_PYCROSS_DEBUG" in os.environ
    _temp_dir = Path(tempfile.mkdtemp(prefix="wheelbuild"))

    try:
        main(args, _temp_dir, _is_debug)
    finally:
        if not _is_debug:
            shutil.rmtree(_temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main_wrapper(parse_flags())
