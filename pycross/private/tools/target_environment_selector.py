from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.target_environment import TargetEnv


def main(args: Any) -> None:
    output = args.output

    result = None
    for input_file in args.file or []:
        with open(input_file, "r") as f:
            environment_data = json.load(f)
        # Coerce single files to lists
        if not isinstance(environment_data, list):
            environment_data = [environment_data]

        for target_env_data in environment_data:
            target_env = TargetEnv.from_dict(target_env_data)
            if target_env.name == args.name:
                if result is not None:
                    raise AssertionError(f"Multiple environment entries found with name '{args.name}'")
                result = target_env
                # Keep going so we can fail loudly if there are multiple matches.

        if result is None:
            raise AssertionError(f"No environment entries found with name '{args.name}'")

        with open(args.output, "w") as f:
            json.dump(result.to_dict(), f, indent=2, sort_keys=True)
            f.write("\n")


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Select the named target environment structure from a list of options")

    parser.add_argument(
        "--file",
        type=Path,
        action="append",
    )

    parser.add_argument(
        "--name",
        required=True,
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
    )

    return parser.parse_args()


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main(parse_flags())
