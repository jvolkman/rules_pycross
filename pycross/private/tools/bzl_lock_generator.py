from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Type, TypeVar
import argparse
import json
import os
import sys

from packaging.requirements import Requirement
from packaging.version import Version
import tomli

from pycross.private.tools.target_environment import TargetEnv

T = TypeVar("T")

# Filter through LinkEvaluator first
# Then compute_best_candidate


# For downloads: https://github.com/pypa/warehouse/issues/1944


@dataclass
class Package:
    name: str
    version: Version
    extras: List[str]
    requires_python: str
    dependencies: List[Requirement]


class PdmMetadata:
    def __init__(self, requirements, packages_by_name, links):
        self._requirements = requirements
        self._packages_by_name = packages_by_name

    def get_requirements(self) -> List[Requirement]:
        return self._requirements

    def get_package(self, req: Requirement) -> Package:
        matching = self._packages_by_name.get(req.name.lower(), [])
        for m in matching:
            if set(m.extras) == req.extras and req.specifier.contains(m.version):
                return m

        raise Exception(f"Could not find a package matching {req}")

    @classmethod
    def create(cls: Type[T], project_file: str, lock_file: str) -> T:
        try:
            with open(project_file, "rb") as f:
                project_dict = tomli.load(f)
        except Exception as e:
            raise Exception(f"Could not load project file: {project_file}: {e}")

        requirement_strings = project_dict.get("project", {}).get("dependencies", [])
        requirements = [Requirement(s) for s in requirement_strings]

        try:
            with open(lock_file, "rb") as f:
                lock_dict = tomli.load(f)
        except Exception as e:
            raise Exception(f"Could not load lock file: {lock_file}: {e}")

        packages_by_name: Dict[str, List[Package]] = defaultdict(list)
        for lock_pkg in lock_dict.get("package", []):
            package_name = lock_pkg["name"]
            packages_by_name[package_name.lower()].append(
                Package(
                    name=package_name,
                    version=Version(lock_pkg["version"]),
                    extras=lock_pkg.get("extras", []),
                    requires_python=lock_pkg.get("requires_python", ""),
                    dependencies=[
                        Requirement(d) for d in lock_pkg.get("dependencies", [])
                    ],
                )
            )

        return cls(requirements, packages_by_name, [])


@dataclass
class Entry:
    package_name: str
    package_deps: List[str]

    def __str__(self):
        return (
            f'Entry(\n    name = "{self.package_name}"\n    deps={self.package_deps}\n)'
        )


def main():
    parser = argparse.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--pdm-project-file",
        type=str,
        required=True,
        help="The path to pyproject.toml.",
    )

    parser.add_argument(
        "--pdm-lock-file",
        type=str,
        required=True,
        help="The path to pdm.lock.",
    )

    parser.add_argument(
        "--target-environment-file",
        type=str,
        nargs="*",
        help="A pycross_target_environment output file.",
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The path to the output bzl file.",
    )

    args = parser.parse_args()
    output = args.output
    targets = []
    for target_file in args.target_environment_file or []:
        with open(target_file, "r") as f:
            targets.append(TargetEnv.from_dict(json.load(f)))

    metadata = PdmMetadata.create(args.pdm_project_file, args.pdm_lock_file)

    work = list(metadata.get_requirements())

    entries = {}
    while work:
        next_req = work.pop()
        pkg_name = next_req.name.lower()
        if pkg_name in entries:
            continue
        package = metadata.get_package(next_req)
        work.extend(package.dependencies)

        # TODO: handle platform/extra crap
        dependency_names = [d.name.lower() for d in package.dependencies]
        entries[pkg_name] = Entry(package_name=pkg_name, package_deps=dependency_names)

    entry_list = sorted(entries.values(), key=lambda x: x.package_name)
    with open(output, "w") as f:
        for e in entry_list:
            print(e, file=f)
            print(file=f)


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
