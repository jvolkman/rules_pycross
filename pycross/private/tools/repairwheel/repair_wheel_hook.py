import os
import subprocess
import sys
from pathlib import Path


def main() -> None:
    lib_path_env = os.environ["PYCROSS_LIBRARY_PATH"]
    lib_path = [Path(p) for p in lib_path_env.split(os.pathsep)]
    wheel_file = Path(os.environ["PYCROSS_WHEEL_FILE"])
    output_dir = Path(os.environ["PYCROSS_WHEEL_OUTPUT_ROOT"])

    args = [
        sys.executable,
        "-m",
        "repairwheel",
        str(wheel_file),
        "--output-dir",
        str(output_dir),
    ]

    for lp in lib_path:
        args.extend(["--lib-dir", str(lp)])

    subprocess.check_call(args, env=os.environ)


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main()
