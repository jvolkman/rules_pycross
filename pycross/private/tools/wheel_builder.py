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

        # TODO: set PYTHONPATH
        env = os.environ.copy()
        subprocess.run(wheel_args, check=True, env=env)

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

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
