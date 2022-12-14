"""
A tool that takes an input PEP 425 tag and an optional list of environment
marker overrides and outputs the result of guessed markers with overrides.
"""

import json
import os
from pathlib import Path
from typing import Any

from absl import app
from absl.flags import argparse_flags
from pip._internal.models.target_python import TargetPython

from pycross.private.tools.target_environment import TargetEnv


def main(args: Any) -> None:
    overrides = {}
    for override_str in args.environment_marker or []:
        key, val = override_str.split("=", maxsplit=1)
        overrides[key] = val

    version_info = tuple(args.version.split("."))
    if len(version_info) != 3:
        parser.error("Version must be in the format a.b.c.")

    target_python = TargetPython(
        platforms=args.platform or [],
        py_version_info=version_info,
        abis=args.abi or [],
        implementation=args.implementation,
    )

    target = TargetEnv.from_target_python(
        args.name, target_python, overrides, args.python_compatible_with
    )
    with open(args.output, "w") as f:
        json.dump(target.to_dict(), f, indent=2, sort_keys=True)
        f.write("\n")


def parse_flags(argv) -> Any:
    parser = argparse_flags.ArgumentParser(
        description="Generate target python information."
    )

    parser.add_argument(
        "--name",
        required=True,
        help="The given platform name.",
    )

    parser.add_argument(
        "--implementation",
        required=True,
        help="The PEP 425 implementation abbreviation (e.g., cp for cpython).",
    )

    parser.add_argument(
        "--version",
        required=True,
        help="The Python version.",
    )

    parser.add_argument(
        "--abi",
        action="append",
        help="A list of PEP 425 abi tags.",
    )

    parser.add_argument(
        "--platform",
        action="append",
        help="A list of PEP 425 platform tags.",
    )

    parser.add_argument(
        "--environment-marker",
        action="append",
        help="Environment marker overrides in the format `marker=override`.",
    )

    parser.add_argument(
        "--python-compatible-with",
        action="append",
        required=True,
        help="Name of the environment constraint label.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The output file.",
    )

    return parser.parse_args(argv[1:])


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    app.run(main, flags_parser=parse_flags)
