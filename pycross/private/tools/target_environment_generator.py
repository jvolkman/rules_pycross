"""
A tool that takes an input PEP 425 tag and an optional list of environment
marker overrides and outputs the result of guessed markers with overrides.
"""

import argparse
import json
import os
import sys

from pip._internal.models.target_python import TargetPython
from pycross.private.tools.target_environment import TargetEnv


def main():
    parser = make_parser()
    args = parser.parse_args()

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


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate target python information.")

    parser.add_argument(
        "--name",
        type=str,
        required=True,
        help="The given platform name.",
    )

    parser.add_argument(
        "--implementation",
        type=str,
        required=True,
        help="The PEP 425 implementation abbreviation (e.g., cp for cpython).",
    )

    parser.add_argument(
        "--version",
        type=str,
        required=True,
        help="The Python version.",
    )

    parser.add_argument(
        "--abi",
        type=str,
        action="append",
        help="A list of PEP 425 abi tags.",
    )

    parser.add_argument(
        "--platform",
        type=str,
        action="append",
        help="A list of PEP 425 platform tags.",
    )

    parser.add_argument(
        "--environment-marker",
        type=str,
        action="append",
        help="Environment marker overrides in the format `marker=override`.",
    )

    parser.add_argument(
        "--python-compatible-with",
        type=str,
        action="append",
        required=True,
        help="Name of the environment constraint label.",
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The output file.",
    )

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
