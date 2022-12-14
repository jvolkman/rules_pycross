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

from absl import app
from absl.flags import argparse_flags
from build import ProjectBuilder
from packaging.utils import parse_wheel_filename
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


def _error(msg: str, code: int = 1) -> NoReturn:  # pragma: no cover
    """
    Print an error message and exit. Will color the output when writing to a TTY.
    :param msg: Error message
    :param code: Error code
    """
    print("{red}ERROR{reset} {}".format(msg, **_STYLES))
    raise SystemExit(code)


def determine_target_path_from_exec(
    exec_python_exe: Path, target_python_exe: Path
) -> List[Path]:
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
        target_sys_path = determine_target_path_from_exec(
            exec_python_exe, target_python_exe
        )

    return find_sysconfig_data(target_sys_path)


def set_or_append(env: Dict[str, Any], key: str, value: str) -> None:
    if key in env:
        env[key] += " " + value
    else:
        env[key] = value


def get_build_env_vars(bin_dir: Path) -> Dict[str, str]:
    env = os.environ.copy()

    # wheel, by default, enables debug symbols in GCC. This incidentally captures the build path in the .so file
    # We can override this behavior by disabling debug symbols entirely.
    # https://github.com/pypa/pip/issues/6505
    set_or_append(env, "CFLAGS", "-g0")
    set_or_append(env, "LDFLAGS", "-Wl,-s")

    # set SOURCE_DATE_EPOCH to 1980 so that we can use python wheels
    # https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/python.section.md#python-setuppy-bdist_wheel-cannot-create-whl
    if "SOURCE_DATE_EPOCH" not in env:
        env["SOURCE_DATE_EPOCH"] = "315532800"

    # Python wheel metadata files can be unstable.
    # See https://bitbucket.org/pypa/wheel/pull-requests/74/make-the-output-of-metadata-files/diff
    if "PYTHONHASHSEED" not in env:
        env["PYTHONHASHSEED"] = "0"

    # Place our bin directory, with possible overridden commands, at the beginning of PATH.
    existing_path = env.get("PATH")
    if existing_path:
        env["PATH"] = os.pathsep.join([str(bin_dir), existing_path])
    else:
        env["PATH"] = str(bin_dir)

    return env


def replace_cwd_tokens(data: Dict[str, Any], cwd: str) -> Dict[str, Any]:
    if cwd.endswith("/"):
        cwd = cwd[:-1]
    result = {}
    for k, v in data.items():
        result[k] = v.replace("$$EXT_BUILD_ROOT$$", cwd)

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


def wrap_cc(
    lang: str, cc_exe: Path, cflags: str, python_exe: Path, bin_dir: Path
) -> Path:
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

    python_exe = os.path.join(os.getcwd(), python_exe)
    with open(wrapper_path, "w") as f:
        f.write(
            textwrap.dedent(
                f"""\
                #!{python_exe}
                import os
                import sys
                os.execv("{cc_exe}", ["{cc_exe}"] + {repr(wrapper_flags)} + sys.argv[1:])
                """
            )
        )

    os.chmod(wrapper_path, 0o755)
    return wrapper_path


def generate_cc_wrappers(
    toolchain_vars: Dict[str, Any], python_exe: Path, bin_dir: Path
) -> Dict[str, str]:
    orig_cc = toolchain_vars["CC"]
    orig_cxx = toolchain_vars["CXX"]
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
) -> Dict[str, Any]:
    sysconfig_vars = toolchain_vars.copy()
    sysconfig_vars.update(wrapper_vars)
    sysconfig_vars.update(get_inherited_vars(target_vars))

    # wheel_build.bzl gives us LDSHAREDFLAGS, but Python wants LDSHARED which is a combination of CC and LDSHAREDFLAGS
    sysconfig_vars["LDSHARED"] = " ".join(
        [sysconfig_vars["CC"], sysconfig_vars["LDSHAREDFLAGS"]]
    )
    del sysconfig_vars["LDSHAREDFLAGS"]

    return sysconfig_vars


def generate_bin_tools(toolchain_vars: Dict[str, str], bin_dir: Path) -> None:
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


def extract_sdist(sdist_path: Path, sdist_dir: Path) -> Path:
    if sdist_path.name.endswith(".tar.gz"):
        with tarfile.open(sdist_path, "r") as f:
            f.extractall(sdist_dir)
    elif sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path, "r") as f:
            f.extractall(sdist_dir)
    else:
        assert False, f"Unsupported sdist format: {sdist_path}"

    # After extraction, there should be a `packageName-version` directory
    (extracted_dir,) = sdist_dir.glob("*")
    return extracted_dir


def check_filename_against_target(
    wheel_name: str, target_environment: TargetEnv
) -> None:
    _, _, _, tags = parse_wheel_filename(wheel_name)
    tag_names = {str(t) for t in tags}
    assert tag_names.intersection(
        target_environment.compatibility_tags
    ), f"No tags in {wheel_name} match target environment {target_environment.name}"


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
    target_env: TargetEnv,
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

    for tag in target_env.compatibility_tags:
        if "manylinux" in tag:
            crossenv_args.extend(
                [
                    "--manylinux",
                    tag,
                ]
            )

    try:
        subprocess.check_output(
            args=crossenv_args, env=os.environ, stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as cpe:
        print("===== CROSSENV FAILED =====", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise


def build_standard_venv(
    env_dir: Path, exec_python_exe: Path, sysconfig_vars: Dict[str, Any]
) -> None:
    venv_args = [
        exec_python_exe,
        "-m",
        "venv",
        "--symlinks",
        "--without-pip",
        str(env_dir),
    ]

    try:
        subprocess.check_output(
            args=venv_args, env=os.environ, stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as cpe:
        print("===== VENV FAILED =====", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise

    # Setup our customized sysconfig vars
    site_dir = find_site_dir(env_dir)
    with open(site_dir / "_pycross_sysconfigdata.py", "w") as f:
        f.write(f"build_time_vars = {repr(sysconfig_vars)}\n")
    with open(site_dir / "_pycross_sysconfigdata.pth", "w") as f:
        f.write(
            'import os; os.environ["_PYTHON_SYSCONFIGDATA_NAME"] = "_pycross_sysconfigdata"\n'
        )


def build_venv(
    env_dir: Path,
    exec_python_exe: Path,
    target_python_exe: Path,
    sysconfig_vars: Dict[str, Any],
    path: List[str],
    target_env: TargetEnv,
    always_use_crossenv: bool = False,
) -> None:
    if exec_python_exe != target_python_exe or always_use_crossenv:
        build_cross_venv(
            env_dir, exec_python_exe, target_python_exe, sysconfig_vars, target_env
        )
    else:
        build_standard_venv(env_dir, exec_python_exe, sysconfig_vars)

    site = find_site_dir(env_dir)
    with open(site / "deps.pth", "w") as f:
        f.write("\n".join(path) + "\n")


def build_wheel(
    env_dir: Path,
    wheel_dir: Path,
    sdist_dir: Path,
    build_env_vars: Dict[str, str],
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
        env = build_env_vars.copy()

        # Pop off some environment variables that might affect our build venv.
        # We don't run in isolated mode because we want to be able to specify PYTHONHASHSEED.
        env.pop("PYTHONHOME", None)
        env.pop("PYTHONPATH", None)

        if extra_environ:
            env.update(extra_environ)

        if debug:
            try:
                site = subprocess.check_output(
                    [cmd[0], "-m", "site"], cwd=cwd, env=env, stderr=subprocess.STDOUT
                )
                print("===== BUILD SITE =====", file=sys.stdout)
                print(site.decode(), file=sys.stdout)
            except subprocess.CalledProcessError as cpe:
                print("Warning: failed to collect site output", file=sys.stderr)
                print(cpe.output.decode(), file=sys.stderr)

        try:
            output = subprocess.check_output(
                cmd, cwd=cwd, env=env, stderr=subprocess.STDOUT
            )
        except subprocess.CalledProcessError as cpe:
            print("===== BUILD FAILED =====", file=sys.stderr)
            print(cpe.output.decode(), file=sys.stderr)
            raise

        if debug:
            print(output.decode(), file=sys.stdout)

    builder = ProjectBuilder(
        srcdir=sdist_dir,
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


def main(args: Any, temp_dir: Path, is_debug: bool) -> None:
    cwd = os.getcwd()

    if args.target_environment_file:
        with open(args.target_environment_file, "r") as f:
            target_environment = TargetEnv.from_dict(json.load(f))
    else:
        target_environment = None

    with open(args.sysconfig_vars, "r") as f:
        toolchain_sysconfig_vars = json.load(f)

    sdist_dir = temp_dir / "sdist"
    wheel_dir = temp_dir / "wheel"
    bin_dir = temp_dir / "bin"
    build_env_dir = temp_dir / "env"
    sdist_dir.mkdir()
    wheel_dir.mkdir()
    bin_dir.mkdir()
    build_env_dir.mkdir()

    build_env_vars = get_build_env_vars(bin_dir)
    toolchain_sysconfig_vars = replace_cwd_tokens(toolchain_sysconfig_vars, cwd)
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
    )

    absolute_path_entries = (
        [os.path.join(cwd, p) for p in args.path] if args.path else []
    )
    build_venv(
        env_dir=build_env_dir,
        exec_python_exe=args.exec_python_executable,
        target_python_exe=args.target_python_executable,
        sysconfig_vars=sysconfig_vars,
        path=absolute_path_entries,
        target_env=target_environment,
        always_use_crossenv=args.always_use_crossenv,
    )
    generate_bin_tools(toolchain_sysconfig_vars, bin_dir)

    if is_debug:
        print(f"Build environment: {build_env_dir}")

    extracted_dir = extract_sdist(args.sdist, sdist_dir)
    wheel_file = build_wheel(
        env_dir=build_env_dir,
        wheel_dir=wheel_dir,
        sdist_dir=extracted_dir,
        build_env_vars=build_env_vars,
        config_settings={},  # TODO: support config settings
        debug=is_debug,
    )

    if target_environment:
        check_filename_against_target(os.path.basename(wheel_file), target_environment)

    shutil.move(wheel_file, args.wheel_file)
    with open(args.wheel_name_file, "w") as f:
        f.write(os.path.basename(wheel_file))


def parse_flags(argv) -> Any:
    parser = argparse_flags.ArgumentParser(
        description="Generate target python information."
    )

    parser.add_argument(
        "--sdist",
        type=Path,
        required=True,
        help="The sdist path.",
    )

    parser.add_argument(
        "--wheel-file",
        type=Path,
        required=True,
        help="The wheel output path.",
    )

    parser.add_argument(
        "--wheel-name-file",
        type=Path,
        required=True,
        help="The wheel name output path.",
    )

    parser.add_argument(
        "--path",
        type=Path,
        action="append",
        help="An entry to add to PYTHONPATH",
    )

    parser.add_argument(
        "--sysconfig-vars",
        required=True,
        help="A JSON file containing variable to add to sysconfig.",
    )

    parser.add_argument(
        "--target-environment-file",
        type=Path,
        help="A JSON file containing the target Python environment details.",
    )

    parser.add_argument(
        "--exec-python-executable",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--target-sys-path",
        type=Path,
        required=False,
        action="append",
        default=[],
    )

    parser.add_argument(
        "--target-python-executable",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--always-use-crossenv",
        action="store_true",
    )

    return parser.parse_args(argv[1:])


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
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    app.run(main_wrapper, flags_parser=parse_flags)
