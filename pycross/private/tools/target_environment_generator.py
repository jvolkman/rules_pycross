"""
A tool that takes an input PEP 425 tag and an optional list of environment
marker overrides and outputs the result of guessed markers with overrides.
"""
from __future__ import annotations

import json
import os
from argparse import Namespace
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Any
from typing import Dict
from typing import Iterable
from typing import List
from typing import Optional

from dacite.config import Config
from dacite.core import from_dict
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


@dataclass
class Input:
    name: str
    implementation: str
    version: str
    abis: List[str] = field(default_factory=list)
    platforms: List[str] = field(default_factory=list)
    environment_markers: Dict[str, str] = field(default_factory=dict)
    python_compatible_with: List[str] = field(default_factory=list)
    flag_values: Dict[str, str] = field(default_factory=dict)
    config_setting_target: Optional[str] = None

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> Input:
        return from_dict(Input, data, config=Config(cast=[Path]))


def _expand_manylinux_platforms(platforms: Iterable[str]) -> List[str]:
    extra_platforms = set()
    platforms = set(platforms)
    for platform in platforms:
        if platform in _MANYLINUX_ALIASES:
            extra_platforms.add(_MANYLINUX_ALIASES[platform])
    platforms.update(extra_platforms)
    return sorted(platforms)


def create_environment(input: Input) -> TargetEnv:
    overrides = {}
    for key, val in input.environment_markers:
        overrides[key] = val

    version_info = tuple(int(part) for part in input.version.split("."))
    if len(version_info) != 3:
        raise ValueError("Version must be in the format a.b.c.")

    platforms = _expand_manylinux_platforms(input.platforms)
    target_python = TargetPython(
        platforms=platforms or ["any"],
        py_version_info=version_info,
        abis=input.abis or ["none"],
        implementation=input.implementation,
    )

    return TargetEnv.from_target_python(
        input.name,
        target_python,
        overrides,
        input.python_compatible_with,
        input.flag_values,
        input.config_setting_target,
    )


def create(inputs: List[Input], output: Path) -> None:
    environment_dicts = [create_environment(input).to_dict() for input in inputs]
    with open(output, "w") as f:
        json.dump(environment_dicts, f, indent=2, sort_keys=True)
        f.write("\n")


def parse_flags() -> Namespace:
    root = FlagFileArgumentParser(description="Generate target python information.")

    subparsers = root.add_subparsers(dest="subparser_name")

    create_parser = subparsers.add_parser("create")
    create_parser.add_argument(
        "--name",
        required=True,
        help="The given platform name.",
    )

    create_parser.add_argument(
        "--implementation",
        required=True,
        help="The PEP 425 implementation abbreviation (e.g., cp for cpython).",
    )

    create_parser.add_argument(
        "--version",
        required=True,
        help="The Python version.",
    )

    create_parser.add_argument(
        "--abi",
        action="append",
        dest="abis",
        help="A list of PEP 425 abi tags.",
    )

    create_parser.add_argument(
        "--platform",
        action="append",
        dest="platforms",
        help="A list of PEP 425 platform tags.",
    )

    create_parser.add_argument(
        "--environment-marker",
        nargs=2,
        action="append",
        dest="environment_markers",
        help="Environment marker overrides in the format `marker override`.",
    )

    create_parser.add_argument(
        "--python-compatible-with",
        action="append",
        help="Name of the environment constraint label.",
    )

    create_parser.add_argument(
        "--flag-value",
        nargs=2,
        action="append",
        dest="flag_values",
        help="A config_setting flag value.",
    )

    create_parser.add_argument(
        "--config-setting-target",
        help="The config_setting target to use.",
    )

    create_parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The output file.",
    )

    batch_create_parser = subparsers.add_parser("batch-create")
    batch_create_parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="The input file.",
    )

    create_parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The output file.",
    )

    return root.parse_args()


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    args = parse_flags()
    if args.subparser_name == "create":
        input_dict = {k: v for k, v in vars(args).items() if v is not None}

        # output is specified separately.
        input_dict.pop("output", None)

        # Some of the parsed values come as lists of tuples, but they should be dicts.
        for dict_key in ("environment_markers", "flag_values"):
            if dict_key in input_dict:
                input_dict[dict_key] = dict(input_dict[dict_key])

        input = Input.from_dict(input_dict)
        create([input], args.output)

    elif args.subparser_name == "batch-create":
        with open(args.input) as f:
            input_dicts = json.load(f)
        inputs = [Input.from_dict(input_dict) for input_dict in input_dicts]
        create(inputs, args.output)

    else:
        raise AssertionError("Bad subparser_name: " + args.subparser_name)
