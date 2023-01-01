import argparse
import os
from pathlib import Path
from typing import Any

from absl import app
from absl.flags import argparse_flags

from pycross.private.tools.auditwheel.repair import repair


def main(args: Any) -> None:
    lib_path = []
    for p in args.lib_path:
        lib_path.extend(map(Path, p.split(":")))

    repair(
        wheel_file=args.wheel_file,
        output_dir=args.output_dir,
        lib_path=lib_path,
        target_machine=args.target_machine,
        verbosity=args.verbose,
    )


def parse_flags(argv) -> Any:
    parser = argparse_flags.ArgumentParser(
        description="Repair linux wheel."
    )

    parser.add_argument(
        "--wheel-file",
        help="Path to wheel file.",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--lib-path",
        help="Directories to be added to LD_LIBRARY_PATH",
        action="append",
        default=[],
    )

    parser.add_argument(
        "--target-machine",
        help="The machine name for the target platform (x86_64, aarch64, ...)",
        required=True,
    )

    parser.add_argument(
        "--output-dir",
        help="Path to directory where new wheel is written.",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--verbose",
        action="count",
        dest="verbose",
        default=0,
        help="Give more output. Option is additive",
    )

    return parser.parse_args(argv[1:])


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    app.run(main, flags_parser=parse_flags)
