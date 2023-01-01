import argparse
import os
from pathlib import Path
from typing import Any

from pycross.private.tools.auditwheel.repair import repair


def main() -> None:
    lib_path_env = os.environ["PYCROSS_LIBRARY_PATH"]
    lib_path = [Path(p) for p in lib_path_env.split(":")]
    wheel_file = Path(os.environ["PYCROSS_WHEEL_FILE"])
    output_dir = Path(os.environ["PYCROSS_WHEEL_OUTPUT_ROOT"])
    target_machine = os.environ["PYCROSS_TARGET_PYTHON_MACHINE"]

    repair(
        wheel_file=wheel_file,
        output_dir=output_dir,
        lib_path=lib_path,
        target_machine=target_machine,
    )


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main()
