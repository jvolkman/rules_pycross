"""
A PEP 517 wheel builder that supports (or tries to) cross-platform builds.
"""
import json
import os
import shutil
import subprocess
import sys
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
    if key == "PATH":
        sep = os.pathsep
    else:
        sep = " "
    if key in env:
        env[key] += sep + value
    else:
        env[key] = value


def get_default_build_env_vars(path_dirs: List[Path]) -> Dict[str, str]:
    env = os.environ.copy()

    # Pop off some environment variables that might affect our build venv.
    env.pop("PYTHONHOME", None)
    env.pop("PYTHONPATH", None)
    env.pop("RUNFILES_DIR", None)

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
    if "PYTHONSAFEPATH" not in env:
        env["PYTHONSAFEPATH"] = "1"

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


def get_wrapper_flags(cflags: str) -> List[str]:
    """Returns flags that should be added to a cc wrapper."""
    possible_flags = ["-target", "--target"]

    result = []
    split_cflags = cflags.split()
    for i, flag in enumerate(split_cflags):
        for possible_flag in possible_flags:
            if not (flag.startswith(possible_flag)):
                continue
            if "=" in flag:
                flag, value = flag.split("=")
                additions = [f"{flag}={value}"]
            else:
                flag, value = flag, split_cflags[i + 1]
                additions = [flag, value]

            if not flag == possible_flag:
                # This is something else, like --target-cpu
                continue

            result.extend(additions)

    return result


def wrap_cc(lang: str, cc_exe: Path, cflags: str, python_exe: Path, bin_dir: Path) -> Path:
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

    wrapper_flags = get_wrapper_flags(cflags)
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
                os.execv(cc_exe, [cc_exe] + {repr(wrapper_flags)} + sys.argv[1:])
                """
            )
        )

    os.chmod(wrapper_path, 0o755)
    return wrapper_path


def generate_cc_wrappers(toolchain_vars: Dict[str, Any], python_exe: Path, bin_dir: Path) -> Dict[str, str]:
    orig_cc = os.path.abspath(toolchain_vars["CC"])
    orig_cxx = os.path.abspath(toolchain_vars["CXX"])
    cflags = toolchain_vars["CFLAGS"]
    # Possibly generate wrappers around the CC and CXX executables.
    wrapped_cc = wrap_cc("cc", orig_cc, cflags, python_exe, bin_dir)
    wrapped_cxx = wrap_cc("cxx", orig_cxx, cflags, python_exe, bin_dir)
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
) -> Dict[str, Any]:
    sysconfig_vars = toolchain_vars.copy()
    sysconfig_vars.update(wrapper_vars)
    sysconfig_vars.update(get_inherited_vars(target_vars))

    # wheel_build.bzl gives us LDSHAREDFLAGS, but Python wants LDSHARED which is a combination of CC and LDSHAREDFLAGS
    sysconfig_vars["LDSHARED"] = " ".join([sysconfig_vars["CC"], sysconfig_vars["LDSHAREDFLAGS"]])
    del sysconfig_vars["LDSHAREDFLAGS"]

    # Add search paths for listed native deps
    for include_path in include_paths:
        sysconfig_vars["CFLAGS"] += f" -I{include_path}"
    sysconfig_vars["CFLAGS"] += f" -L{lib_dir}"
    sysconfig_vars["LDSHARED"] += f" -L{lib_dir}"

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
        subprocess.check_output(args=crossenv_args, env=os.environ, stderr=subprocess.STDOUT)
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
        f.write('import os; os.environ["_PYTHON_SYSCONFIGDATA_NAME"] = "_pycross_sysconfigdata"\n')


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

    # Add a pth file to override sys.prefix and sys.exec_prefix as paths relative to the sdist root.
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

    # Add a pth file to include all of our build dependencies.
    with open(site_dir / "deps.pth", "w") as f:
        f.write("\n".join(os.path.relpath(p, site_dir) for p in path) + "\n")


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
        # TODO: Verify requirements in environment.

        wheel_file = builder.build(
            distribution="wheel",
            output_directory=wheel_dir,
            config_settings=config_settings,
        )

    except Exception as e:  # pragma: no cover
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
    prefix = execroot_prefix(cwd.name)

    def mktmpdir(name: str) -> Path:
        d = temp_dir / name
        d.mkdir()
        # Return as relative from the sdist directory
        return Path("..") / name

    wheel_dir = mktmpdir("wheel")
    bin_dir = mktmpdir("bin")
    tools_dir = mktmpdir("tools")
    build_env_dir = mktmpdir("env")
    include_dir = mktmpdir("include")
    lib_dir = mktmpdir("lib")

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

    wrapper_sysconfig_vars = generate_cc_wrappers(
        toolchain_vars=toolchain_sysconfig_vars,
        python_exe=args.exec_python_executable,
        bin_dir=bin_dir,
    )
    target_sysconfig_vars = get_target_sysconfig(
        target_sys_path=args.target_sys_path,
        exec_python_exe=args.exec_python_executable,
        target_python_exe=args.target_python_executable,
    )
    sysconfig_vars = generate_cross_sysconfig_vars(
        toolchain_vars=toolchain_sysconfig_vars,
        target_vars=target_sysconfig_vars,
        wrapper_vars=wrapper_sysconfig_vars,
        lib_dir=lib_dir,
        include_paths=include_paths,
    )

    build_venv(
        bazel_root=prefix,
        env_dir=build_env_dir,
        exec_python_exe=args.exec_python_executable,
        target_python_exe=args.target_python_executable,
        sysconfig_vars=sysconfig_vars,
        path=args.python_path,
        target_env=target_environment,
        always_use_crossenv=args.always_use_crossenv,
    )

    generate_bin_tools(bin_dir, toolchain_sysconfig_vars)
    link_path_tools(tools_dir, args.path_tool)
    link_native_headers(include_dir, args.native_header)
    link_native_libraries(lib_dir, args.native_library)

    if is_debug:
        print(f"Build environment: {build_env_dir.absolute()}")

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
