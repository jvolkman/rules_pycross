import argparse
import os
import shutil
import subprocess
import sys
import tempfile

from packaging.requirements import Requirement
import tomli

# from pip._vendor.packaging import tags
# compatibility_tags.get_supported

# tag -> TargetPython??
# Filter through LinkEvaluator first
# Then compute_best_candidate




def main():
    parser = argparse.ArgumentParser(
        description = "Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--project-file",
        type=str,
        required=True,
        help="The path to pyproject.toml",
    )

    parser.add_argument(
        "--lock-file",
        type=str,
        required=True,
        help="The path to pdm.lock",
    )

    parser.add_argument(
        "--bzl-file",
        type=str,
        required=True,
        help="The path to output bzl file",
    )

    args = parser.parse_args()
    project_file = args.project_file
    lock_file = args.lock_file
    bzl_file = args.bzl_file

    try:
        with open(project_file, 'rb') as f:
            project_dict = tomli.load(f)
    except Exception as e:
        parser.error(f"Could not load project file: {project_file}: {e}")

    try:
        with open(lock_file, 'rb') as f:
            lock_dict = tomli.load(f)
    except Exception as e:
        parser.error(f"Could not load lock file: {lock_file}: {e}")

    dependency_requirements = project_dict.get("project", {}).get("dependencies", [])
    dependencies = [Requirement(d).name for d in dependency_requirements]

    lock_packages = {p["name"]: p for p in lock_dict["package"]}
    print(lock_packages)


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
