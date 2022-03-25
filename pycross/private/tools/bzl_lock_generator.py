from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Set, Type, TypeVar
import argparse
import json
import os
import sys
import textwrap
from typing import Optional
from typing import Union

from packaging.requirements import Requirement
from packaging.version import Version
import tomli

from pycross.private.tools.target_environment import TargetEnv

T = TypeVar("T")

# Filter through LinkEvaluator first
# Then compute_best_candidate


# For downloads: https://github.com/pypa/warehouse/issues/1944


@dataclass
class PoetryPackage:
    name: str
    version: Version
    requires_python: str
    all_extras: Set[str]
    dependencies: Set[Requirement]

    @property
    def canonical_name(self) -> str:
        return self.name.lower()

    def dependencies_by_environment(self, environments: List[TargetEnv]) -> Dict[Optional[str], Set[Requirement]]:
        env_deps = defaultdict(list)
        for dep in self.dependencies:
            for target in environments:
                # Only requested extra dependencies are included in a package's deps list - whether they're requested
                # by a top-level requirement or by some transitive dependency. Their specifiers still include
                # `extra == "foo"` in addition to any platform-specific markers, so to match we need to include the
                # correct extra value in our marker environment. We don't know the correct value, so instead we just
                # try all possible extra names until something matches.
                for extra in self.all_extras:
                    markers_with_extra = dict(target.markers, extra=extra)
                    if not dep.marker or dep.marker.evaluate(markers_with_extra):
                        env_deps[target.name].append(dep)
                        break

        if env_deps:
            # Pull out deps common to all environments
            common_deps = set.intersection(*(set(v) for v in env_deps.values()))
            env_deps_deduped = {}
            for env, deps in env_deps.items():
                deps = set(deps) - common_deps
                if deps:
                    env_deps_deduped[env] = deps

            env_deps_deduped[None] = common_deps
            return env_deps_deduped

        return {}


class PoetryMetadata:
    def __init__(self, packages: List[PoetryPackage]):
        self.packages = packages

    @staticmethod
    def create(lock_file: str) -> "PoetryMetadata":
        try:
            with open(lock_file, "rb") as f:
                lock_dict = tomli.load(f)
        except Exception as e:
            raise Exception(f"Could not load lock file: {lock_file}: {e}")

        def poetry_requirement(name: str, spec: Union[str, Dict]) -> Requirement:
            # Poetry has already resolved everything, so we don't care about versions. Just specifiers.
            if not isinstance(spec, str):
                spec_markers = spec.get("markers")
                if spec_markers:
                    return Requirement(name + "; " + spec_markers)
            return Requirement(name)

        packages = []
        for lock_pkg in lock_dict.get("package", []):
            package_name = lock_pkg["name"]
            packages.append(
                PoetryPackage(
                    name=package_name,
                    version=Version(lock_pkg["version"]),
                    all_extras=lock_pkg.get("extras", {}).keys(),
                    requires_python=lock_pkg.get("requires_python", ""),
                    dependencies={
                        poetry_requirement(name, spec) for name, spec in lock_pkg.get("dependencies", {}).items()
                    },
                )
            )

        return PoetryMetadata(packages)


class EnvTargetBuilder:
    def __init__(self, environment_name: str, constraints: List[str], prefix: str):
        self.prefix = prefix
        self.environment_name = environment_name
        self.constraints = constraints

    def __str__(self):
        def ind(text: str, tabs=1):
            return textwrap.indent(text, "    " * tabs)

        lines = [
            "config_setting(",
            ind(f'name = "{environment_target_name(self.environment_name, self.prefix)}",'),
            ind(f'constraint_values = ['),
        ]
        for cv in self.constraints:
            lines.append(ind(f'"{cv}",', 2))
        lines.extend([
            ind('],'),
            ")"
        ])

        return "\n".join(lines)


class PackageTargetBuilder:
    def __init__(self, package_name: str, prefix: str):
        self.prefix = prefix
        self.package_name = package_name
        self.common_deps: Set[Requirement] = set()
        self.env_deps: Dict[str, Set[Requirement]] = {}

    def set_dependencies(self, poetry_package: PoetryPackage, environments: List[TargetEnv]) -> None:
        deps_by_env = poetry_package.dependencies_by_environment(environments)
        self.common_deps = deps_by_env.get(None, set())
        self.env_deps = {k: v for k, v in deps_by_env.items() if k is not None}

    def __str__(self):
        def ind(text: str, tabs=1):
            return textwrap.indent(text, "    " * tabs)

        lines = [
            "Entry(",
            ind(f'name = "{package_target_name(self.package_name, self.prefix)}",'),
        ]

        def dep_entries(deps, indent):
            return [ind(f'":{package_target_name(d.name, self.prefix)}",', indent) for d in deps]

        if self.common_deps and self.env_deps:
            lines.append(ind("deps = [", 1))
            lines.extend(dep_entries(self.common_deps, 2))
            lines.append(ind("] + select({", 1))
            for env, deps in self.env_deps.items():
                lines.append(ind(f'":{environment_target_name(env, self.prefix)}": [', 2))
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
                lines.append(ind(f'":{environment_target_name(env, self.prefix)}": [', 2))
                lines.extend(dep_entries(deps, 3))
                lines.append(ind("],", 2))
            lines.append(ind("}),", 1))

        lines.append(")")

        return "\n".join(lines)


def package_target_name(package_name: str, prefix: str) -> str:
    return prefix + "_pkg_" + package_name.lower().replace("-", "_")


def environment_target_name(environment_name: str, prefix: str) -> str:
    return prefix + "_env_" + environment_name.lower().replace("-", "_")


def main():
    prefix = "foo"
    parser = make_parser()
    args = parser.parse_args()
    output = args.output
    environments = []
    for target_file in args.target_environment_file or []:
        with open(target_file, "r") as f:
            environments.append(TargetEnv.from_dict(json.load(f)))

    metadata = PoetryMetadata.create(args.poetry_lock_file)

    entries = []
    for package in metadata.packages:
        entry = PackageTargetBuilder(package_name=package.canonical_name, prefix=prefix)
        entry.set_dependencies(package, environments)
        entries.append(entry)

    entries.sort(key=lambda x: x.package_name)
    with open(output, "w") as f:
        for environment in environments:
            print(EnvTargetBuilder(environment.name, environment.python_compatible_with, prefix), file=f)
            print(file=f)
        for e in entries:
            print(e, file=f)
            print(file=f)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--poetry-lock-file",
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
