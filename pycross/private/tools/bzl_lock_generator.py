from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Type, TypeVar
import argparse
import json
import os
import sys
import textwrap

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
    def __init__(self, requirements: List[Requirement], packages_by_name: Dict[str, List[Package]]):
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

        return cls(requirements, packages_by_name)


class PackageTargetBuilder:
    def __init__(self, package_name: str, prefix: str):
        self.prefix = prefix
        self.package_name = package_name
        self.common_deps: Set[Requirement] = set()
        self.env_deps: Dict[str, Set[Requirement]] = {}

    def set_dependencies(self, dependencies: List[Requirement], target_environments: List[TargetEnv]) -> None:
        env_deps = defaultdict(list)
        for dep in dependencies:
            for target in target_environments:
                if not dep.marker or dep.marker.evaluate(target.markers):
                    target_label = environment_target_name(target, self.prefix)
                    env_deps[target_label].append(dep)

        if env_deps:
            # Pull out deps common to all environments
            common_deps = set.intersection(*(set(v) for v in env_deps.values()))
            env_deps_deduped = {}
            for env, deps in env_deps.items():
                deps = set(deps) - common_deps
                if deps:
                    env_deps_deduped[env] = deps

            self.env_deps = env_deps_deduped
            self.common_deps = common_deps

    def __str__(self):
        def ind(text: str, tabs=1):
            return textwrap.indent(text, "    " * tabs)

        lines = [
            "Entry(",
            ind(f'name = "{self.package_name}",'),
        ]

        def dep_entries(deps, indent):
            return [ind(requirement_target_name(d, self.prefix), indent) + "," for d in deps]

        if self.common_deps and self.env_deps:
            lines.append(ind("deps = [", 1))
            lines.extend(dep_entries(self.common_deps, 2))
            lines.append(ind("] + select({", 1))
            for env, deps in self.env_deps.items():
                lines.append(ind(f'"{env}": [', 2))
                lines.extend(dep_entries(deps, 3))
                lines.append(ind("],", 2))
            lines.append(ind("}),", 1))

        elif self.common_deps:
            lines.append(ind("deps = [", 1))
            lines.extend(dep_entries(self.common_deps, 2))
            lines.append(ind("],", 1))

        elif self.env_deps:
            lines.append(ind("deps = select({", 1))
            for env, deps in self.env_deps.items():
                lines.append(f'"{environment_target_name(env, self.prefix)}": [', 2)
                lines.extend(dep_entries(deps, 3))
                lines.append(ind("],", 2))
            lines.append(ind("}),", 1))

        lines.append(")")

        return "\n".join(lines)


def requirement_target_name(requirement: Requirement, prefix: str) -> str:
    return prefix + "_" + requirement.name.lower().replace("-", "_")


def environment_target_name(requirement: Requirement, prefix: str) -> str:
    return prefix + "_" + requirement.name.lower().replace("-", "_")


def main():
    prefix = "foo_"
    parser = make_parser()
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

        entries[pkg_name] = PackageTargetBuilder(package_name=pkg_name, prefix=prefix)
        entries[pkg_name].set_dependencies(package.dependencies, targets)

    entry_list = sorted(entries.values(), key=lambda x: x.package_name)
    with open(output, "w") as f:
        for e in entry_list:
            print(e, file=f)
            print(file=f)


def make_parser() -> argparse.ArgumentParser:
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
        action='append',
        help="A pycross_target_environment output file.",
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
