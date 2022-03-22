"""
A tool that takes an input PEP 425 tag and an optional list of environment
marker overrides and outputs the result of guessed markers with overrides.
"""

import argparse
import json
import os
import sys

from packaging import tags

import env_markers


def main():
    parser = argparse.ArgumentParser(
        description = "Generate target python information."
    )

    parser.add_argument(
        "--platform-tag",
        type=str,
        required=True,
        help="The PEP 425 tag that describes the target platform.",
    )

    parser.add_argument(
        "--marker-override",
        type=str,
        nargs="*",
        help="Environment marker overrides in the format `marker=override`."
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The output file.",
    )

    args = parser.parse_args()
    platform_tag_set = tags.parse_tag(args.platform_tag)
    if len(platform_tag_set) > 1:
        raise ValueError(f"Platform tag must be singular, but evaluated to {list(platform_tag_set)}")

    platform_tag = next(iter(platform_tag_set))

    overrides = {}
    for override_str in args.marker_override or []:
        key, val = override_str.split("=", maxsplit=1)
        overrides[key] = val

    markers = env_markers.guess_environment_markers(platform_tag)
    for key, val in overrides.items():
        if key not in markers:
            raise ValueError(f"Invalid marker: {key}")
        markers[key] = val

    struct = dict(
        platform_tag=str(platform_tag),
        compatibility_tags=[str(platform_tag)],
        markers=markers,
    )
    with open(args.output, "w") as f:
        json.dump(struct, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
