"""
A tool that invokes pypa/build to build the given sdist tarball.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import sysconfig
import tarfile
import zipfile
from typing import Any

import tempfile
from pathlib import Path
from typing import Dict


def set_or_append(env: Dict[str, Any], key: str, value: str) -> None:
    if key in env:
        env[key] += " " + value
    else:
        env[key] = value


def get_build_env(
    args: argparse.Namespace, cwd: str, sysconfig_vars: Dict[str, Any], temp_dir: str
) -> Dict[str, str]:
    env = os.environ.copy()

    path_entries = [os.path.join(cwd, p) for p in args.path or []]
    if "PYTHONPATH" in env:
        path_entries.append(env["PYTHONPATH"])

    if path_entries:
        env["PYTHONPATH"] = os.pathsep.join(path_entries)

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

    add_sysconfig_override(env, temp_dir, sysconfig_vars)

    return env


def replace_cwd_tokens(data: Dict[str, Any], cwd: str) -> Dict[str, Any]:
    if cwd.endswith("/"):
        cwd = cwd[:-1]
    result = {}
    for k, v in data.items():
        result[k] = v.replace("$$EXT_BUILD_ROOT$$", cwd)

    return result


def add_sysconfig_override(
    env: Dict[str, str], temp_dir: str, sysconfig_data: Dict[str, Any]
) -> None:
    # Create a file containing generated sysconfig vars
    sysconfig_data_module_name = "wheel_builder_sysconfigdata"
    sysconfig_data_dir = os.path.join(temp_dir, "__sysconfig")
    os.mkdir(sysconfig_data_dir)
    with open(
        os.path.join(sysconfig_data_dir, f"{sysconfig_data_module_name}.py"), "w"
    ) as f:
        f.write(f"build_time_vars = {sysconfig_data}\n")

    if "PYTHONPATH" in env:
        env["PYTHONPATH"] = env["PYTHONPATH"] + os.pathsep + sysconfig_data_dir
    else:
        env["PYTHONPATH"] = sysconfig_data_dir

    env["_PYTHON_SYSCONFIGDATA_NAME"] = sysconfig_data_module_name


def get_inherited_vars() -> Dict[str, Any]:
    inherit_names = [
        "ABIFLAGS",
        "ANDROID_API_LEVEL",
        "EXE",
        "EXT_SUFFIX",
        "LDVERSION",
        "MACHDEP",
        "MACOSX_DEPLOYMENT_TARGET",
        "Py_DEBUG",
        "Py_ENABLE_SHARED",
        "SHLIB_SUFFIX",
        "VERSION",
    ]

    inherited = {name: sysconfig.get_config_var(name) for name in inherit_names}

    # Not sure whether this is correct.
    inherited["LIBDIR"] = sysconfig.get_config_var("srcdir")

    return inherited


def extract_sdist(sdist_path: str, sdist_dir: Path) -> None:
    if sdist_path.endswith(".tar.gz"):
        with tarfile.open(sdist_path, "r") as f:
            f.extractall(sdist_dir)
    elif sdist_path.endswith(".zip"):
        with zipfile.ZipFile(sdist_path, "r") as f:
            f.extractall(sdist_dir)
    else:
        assert False, f"Unsupported sdist format: {sdist_path}"


def main(temp_dir: Path, is_debug: bool) -> None:
    parser = make_parser()
    args = parser.parse_args()
    cwd = os.getcwd()

    sdist_dir = temp_dir / "sdist"
    wheel_dir = temp_dir / "wheel"
    sdist_dir.mkdir()
    wheel_dir.mkdir()

    extract_sdist(args.sdist, sdist_dir)

    # After extraction, there should be a `packageName-version` directory
    (extracted_dir,) = sdist_dir.glob("*")

    wheel_args = [
        sys.executable,
        "-m",
        "build",
        "--wheel",
        "--no-isolation",
        "--outdir",
        wheel_dir,
        extracted_dir,
    ]

    with open(args.sysconfig_vars, "r") as f:
        sysconfig_vars = json.load(f)

    sysconfig_vars = replace_cwd_tokens(sysconfig_vars, cwd)
    sysconfig_vars.update(get_inherited_vars())

    build_env = get_build_env(args, cwd, sysconfig_vars, str(temp_dir))

    try:
        output = subprocess.check_output(args=wheel_args, env=build_env, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as cpe:
        print("===== BUILD FAILED =====", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise

    if is_debug:
        print(output.decode(), file=sys.stderr)

    # After build, there should be a .whl file.
    (wheel_file,) = wheel_dir.glob("*.whl")
    shutil.move(wheel_file, args.wheel)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate target python information.")

    parser.add_argument(
        "--sdist",
        type=str,
        required=True,
        help="The sdist path.",
    )

    parser.add_argument(
        "--wheel",
        type=str,
        required=True,
        help="The wheel output path.",
    )

    parser.add_argument(
        "--path",
        type=str,
        action="append",
        help="An entry to add to PYTHONPATH",
    )

    parser.add_argument(
        "--sysconfig-vars",
        type=str,
        required=True,
        help="A JSON file containing variable to add to sysconfig.",
    )

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    _is_debug = "RULES_PYCROSS_DEBUG" in os.environ
    _temp_dir = Path(tempfile.mkdtemp(prefix="wheelbuild"))

    try:
        sys.exit(main(_temp_dir, _is_debug))
    finally:
        if not _is_debug:
            shutil.rmtree(_temp_dir, ignore_errors=True)
