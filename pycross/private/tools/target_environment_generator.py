"""
A tool that takes an input PEP 425 tag and an optional list of environment
marker overrides and outputs the result of guessed markers with overrides.
"""
import json
import os
from pathlib import Path
from typing import Any
from typing import Iterable
from typing import List

from pip._internal.models.target_python import TargetPython

from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.target_environment import TargetEnv

_MANYLINUX_ALIASES = {
    "manylinux1_x86_64": "manylinux_2_5_x86_64",
    "manylinux1_i686": "manylinux_2_5_i686",
    "manylinux2010_x86_64": "manylinux_2_12_x86_64",
    "manylinux2010_i686": "manylinux_2_12_i686",
    "manylinux2014_x86_64": "manylinux_2_17_x86_64",
    "manylinux2014_i686": "manylinux_2_17_i686",
    "manylinux2014_aarch64": "manylinux_2_17_aarch64",
    "manylinux2014_armv7l": "manylinux_2_17_armv7l",
    "manylinux2014_ppc64": "manylinux_2_17_ppc64",
    "manylinux2014_ppc64le": "manylinux_2_17_ppc64le",
    "manylinux2014_s390x": "manylinux_2_17_s390x",
}
_MANYLINUX_ALIASES.update({v: k for k, v in _MANYLINUX_ALIASES.items()})


def _expand_manylinux_platforms(platforms: Iterable[str]) -> List[str]:
    extra_platforms = set()
    platforms = set(platforms)
    for platform in platforms:
        if platform in _MANYLINUX_ALIASES:
            extra_platforms.add(_MANYLINUX_ALIASES[platform])
    platforms.update(extra_platforms)
    return sorted(platforms)


def main(args: Any) -> None:
    overrides = {}
    for key, val in args.environment_marker or []:
        overrides[key] = val

    version_info = tuple(args.version.split("."))
    if len(version_info) != 3:
        raise ValueError("Version must be in the format a.b.c.")

    platforms = _expand_manylinux_platforms(args.platform or [])
    target_python = TargetPython(
        platforms=platforms or ["any"],
        py_version_info=version_info,
        abis=args.abi or ["none"],
        implementation=args.implementation,
    )

    target = TargetEnv.from_target_python(
        args.name,
        target_python,
        overrides,
        args.python_compatible_with,
        args.flag_value,
        args.config_setting_target,
    )
    with open(args.output, "w") as f:
        json.dump(target.to_dict(), f, indent=2, sort_keys=True)
        f.write("\n")


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Generate target python information.")

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
        nargs=2,
        action="append",
        help="Environment marker overrides in the format `marker=override`.",
    )

    parser.add_argument(
        "--python-compatible-with",
        action="append",
        help="Name of the environment constraint label.",
    )

    parser.add_argument(
        "--flag-value",
        nargs=2,
        action="append",
        help="A config_setting flag value.",
    )

    parser.add_argument(
        "--config-setting-target",
        help="The config_setting target to use.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The output file.",
    )

    return parser.parse_args()


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main(parse_flags())
