from dataclasses import dataclass
from typing import List
import argparse
import json
import os
import sys

from packaging.requirements import Requirement
import tomli

# from pip._vendor.packaging import tags
# compatibility_tags.get_supported

# tag -> TargetPython??
# Filter through LinkEvaluator first
# Then compute_best_candidate


def requirement_name(req: str) -> str:
    return Requirement(req).name.lower()


@dataclass
class Entry:
    package_name: str
    package_deps: List[str]

    def __str__(self):
        return f"Entry(\n    name = \"{self.package_name}\"\n    deps={self.package_deps}\n)"


def main():
    parser = argparse.ArgumentParser(
        description = "Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--project-file",
        type=str,
        required=True,
        help="The path to pyproject.toml.",
    )

    parser.add_argument(
        "--lock-file",
        type=str,
        required=True,
        help="The path to pdm.lock.",
    )

    parser.add_argument(
        "--target-python-file",
        type=str,
        nargs="*",
        help="A target_python output file.",
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The path to the output bzl file.",
    )

    args = parser.parse_args()
    project_file = args.project_file
    lock_file = args.lock_file
    output = args.output
    targets = []
    for tpf in args.target_python_file or []:
        with open(tpf, "r") as f:
            targets.append(json.load(f))

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

    top_dependency_requirements = project_dict.get("project", {}).get("dependencies", [])
    top_dependencies = [requirement_name(d) for d in top_dependency_requirements]
    lock_packages = {p["name"]: p for p in lock_dict["package"]}

    work = list(top_dependencies)

    entries = {}
    while work:
        next_pkg = work.pop()
        if next_pkg in entries:
            continue
        info = lock_packages[next_pkg]
        # TODO: handle platform/extra crap
        dependencies = [requirement_name(d) for d in info.get("dependencies", [])]

        entries[next_pkg] = Entry(package_name=next_pkg, package_deps=dependencies)
        work.extend(dependencies)

    entry_list = sorted(entries.values(), key=lambda e: e.package_name)
    for e in entry_list:
        print(e)
        print()
        print()


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
