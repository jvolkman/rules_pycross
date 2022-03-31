"""
A tool that invokes pypa/build to build the given sdist tarball.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Dict


def get_build_env(args: argparse.Namespace) -> Dict[str, str]:
    env = os.environ.copy()
    cwd = os.getcwd()

    path_entries = [os.path.join(cwd, p) for p in args.path or []]
    if "PYTHONPATH" in env:
        path_entries.append(env["PYTHONPATH"])

    if path_entries:
        env["PYTHONPATH"] = os.pathsep.join(path_entries)

    # wheel, by default, enables debug symbols in GCC. This incidentally captures the build path in the .so file
    # We can override this behavior by disabling debug symbols entirely.
    # https://github.com/pypa/pip/issues/6505
    if "CFLAGS" in env:
        env["CFLAGS"] += " -g0"
    else:
        env["CFLAGS"] = "-g0"

    # set SOURCE_DATE_EPOCH to 1980 so that we can use python wheels
    # https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/python.section.md#python-setuppy-bdist_wheel-cannot-create-whl
    if "SOURCE_DATE_EPOCH" not in env:
        env["SOURCE_DATE_EPOCH"] = "315532800"

    # Python wheel metadata files can be unstable.
    # See https://bitbucket.org/pypa/wheel/pull-requests/74/make-the-output-of-metadata-files/diff
    if "PYTHONHASHSEED" not in env:
        env["PYTHONHASHSEED"] = "0"

    return env


def main():
    parser = make_parser()
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_dir = Path(temp_dir)
        sdist_dir = temp_dir / "sdist"
        wheel_dir = temp_dir / "wheel"
        sdist_dir.mkdir()
        wheel_dir.mkdir()

        with tarfile.open(args.sdist, "r") as f:
            f.extractall(sdist_dir)

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

        # TODO: setup toolchains
        build_env = get_build_env(args)

        try:
            subprocess.check_output(args=wheel_args, env=build_env)
        except subprocess.CalledProcessError as cpe:
            print("===== BUILD FAILED =====", file=sys.stderr)
            print(cpe.output.decode(), file=sys.stderr)
            raise

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

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
