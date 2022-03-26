from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Set
import argparse
import json
import os
import sys
import textwrap
from typing import Optional
from typing import Union

from packaging.markers import Marker
from packaging.specifiers import SpecifierSet
from packaging.version import Version
import tomli

from pycross.private.tools.target_environment import TargetEnv

# Filter through LinkEvaluator first
# Then compute_best_candidate


# For downloads: https://github.com/pypa/warehouse/issues/1944


class Naming:
    def __init__(self, prefix: str):
        self.prefix = prefix

    def package_target(self, package_name: str) -> str:
        return self.prefix + "_pkg_" + package_name.lower().replace("-", "_")

    def environment_target(self, environment_name: str) -> str:
        return self.prefix + "_env_" + environment_name.lower().replace("-", "_")


@dataclass(frozen=True)
class Dependency:
    name: str
    marker: Optional[Marker]

    @property
    def canonical_name(self) -> str:
        return self.name.lower()


@dataclass
class PoetryPackage:
    name: str
    version: Version
    requires_python: SpecifierSet
    all_extras: Set[str]
    dependencies: Set[Dependency]

    @property
    def canonical_name(self) -> str:
        return self.name.lower()

    def supports_environment(self, environment: TargetEnv) -> bool:
        return self.requires_python.contains(environment.version)

    def dependencies_by_environment(
        self, environments: List[TargetEnv]
    ) -> Dict[Optional[str], Set[Dependency]]:
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
    def __init__(self, pinned_package_names: Set[str], packages: List[PoetryPackage]):
        self.pinned_package_names = pinned_package_names
        self.packages = packages

    @staticmethod
    def create(project_file: str, lock_file: str) -> "PoetryMetadata":
        try:
            with open(project_file, "rb") as f:
                project_dict = tomli.load(f)
        except Exception as e:
            raise Exception(f"Could not load project file: {project_file}: {e}")

        try:
            with open(lock_file, "rb") as f:
                lock_dict = tomli.load(f)
        except Exception as e:
            raise Exception(f"Could not load lock file: {lock_file}: {e}")

        def poetry_requirement(name: str, spec: Union[str, Dict]) -> Dependency:
            # Poetry has already resolved everything, so we don't care about versions. Just specifiers.
            if not isinstance(spec, str):
                spec_markers = spec.get("markers")
                if spec_markers:
                    return Dependency(name=name, marker=Marker(spec_markers))
            return Dependency(name=name, marker=None)

        pinned_package_names = set()
        for pinned in (
            project_dict.get("tool", {}).get("poetry", {}).get("dependencies", {})
        ):
            pinned = pinned.lower()
            if pinned == "python":
                # Skip the special line indicating python version.
                continue
            pinned_package_names.add(pinned)

        packages = []
        for lock_pkg in lock_dict.get("package", []):
            package_name = lock_pkg["name"]
            packages.append(
                PoetryPackage(
                    name=package_name,
                    version=Version(lock_pkg["version"]),
                    all_extras=lock_pkg.get("extras", {}).keys(),
                    requires_python=SpecifierSet(lock_pkg.get("requires_python", "")),
                    dependencies={
                        poetry_requirement(name, spec)
                        for name, spec in lock_pkg.get("dependencies", {}).items()
                    },
                )
            )

        return PoetryMetadata(pinned_package_names, packages)


class EnvTarget:
    def __init__(self, environment_name: str, constraints: List[str], naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.constraints = constraints

    def __str__(self):
        def ind(text: str, tabs=1):
            return textwrap.indent(text, "    " * tabs)

        lines = [
            "config_setting(",
            ind(f'name = "{self.naming.environment_target(self.environment_name)}",'),
            ind(f"constraint_values = ["),
        ]
        for cv in self.constraints:
            lines.append(ind(f'"{cv}",', 2))
        lines.extend([ind("],"), ")"])

        return "\n".join(lines)


class PackageTarget:
    def __init__(
        self,
        package_name: str,
        naming: Naming,
        poetry_package: PoetryPackage,
        environments: List[TargetEnv],
    ):
        self.naming = naming
        self.package_name = package_name
        self.common_deps: Set[Dependency] = set()
        self.environments = environments
        self.env_deps: Dict[str, Set[Dependency]] = {}

        deps_by_env = poetry_package.dependencies_by_environment(environments)
        self.common_deps = deps_by_env.get(None, set())
        self.env_deps = {k: v for k, v in deps_by_env.items() if k is not None}

    @property
    def all_dependency_names(self) -> Set[str]:
        """Returns all package names (lower-cased) that this target depends on, including platform-specific."""
        names = set(d.name.lower() for d in self.common_deps)
        for env_deps in self.env_deps.values():
            names |= set(d.name.lower() for d in env_deps)
        return names

    def __str__(self):
        def ind(text: str, tabs=1):
            return textwrap.indent(text, "    " * tabs)

        lines = [
            "Entry(",
            ind(f'name = "{self.naming.package_target(self.package_name)}",'),
        ]

        def common_entries(_deps, indent):
            for d in _deps:
                yield ind(f'":{self.naming.package_target(d.name)}",', indent)

        def select_entries(_env_deps, indent):
            for _env, _deps in _env_deps.items():
                yield ind(f'":{self.naming.environment_target(_env)}": [', indent)
                yield from common_entries(_deps, indent + 1)
                yield ind("],", indent)

        if self.common_deps and self.env_deps:
            lines.append(ind("deps = [", 1))
            lines.extend(common_entries(self.common_deps, 2))
            lines.append(ind("] + select({", 1))
            lines.extend(select_entries(self.env_deps, 2))
            lines.append(ind("}),", 1))

        elif self.common_deps:
            lines.append(ind("deps = [", 1))
            lines.extend(common_entries(self.common_deps, 2))
            lines.append(ind("],", 1))

        elif self.env_deps:
            lines.append(ind("deps = select({", 1))
            lines.extend(select_entries(self.env_deps, 2))
            lines.append(ind("}),", 1))

        lines.append(")")

        return "\n".join(lines)


def check_package_compatibility(
    package: PoetryPackage, environments: List[TargetEnv]
) -> None:
    for environment in environments:
        if not package.supports_environment(environment):
            raise Exception(
                f"Package {package.name} does not support Python version {environment.version} "
                f"in environment {environment.name}"
            )


def main():
    parser = make_parser()
    args = parser.parse_args()
    output = args.output
    environments = []
    for target_file in args.target_environment_file or []:
        with open(target_file, "r") as f:
            environments.append(TargetEnv.from_dict(json.load(f)))

    naming = Naming(args.prefix)
    metadata = PoetryMetadata.create(args.poetry_project_file, args.poetry_lock_file)

    # First we walk the dependency graph starting from the set if pinned packages (in pyproject.toml), computing the
    # transitive closure.
    packages_by_name = {p.canonical_name: p for p in metadata.packages}
    work = list(metadata.pinned_package_names)
    package_targets_by_package_name = {}

    while work:
        next_package_name = work.pop()
        if next_package_name in package_targets_by_package_name:
            continue
        package = packages_by_name[next_package_name]
        check_package_compatibility(package, environments)
        entry = PackageTarget(package.canonical_name, naming, package, environments)
        package_targets_by_package_name[next_package_name] = entry
        work.extend(entry.all_dependency_names)

    package_targets = sorted(
        package_targets_by_package_name.values(), key=lambda x: x.package_name
    )
    with open(output, "w") as f:
        for environment in environments:
            print(
                EnvTarget(environment.name, environment.python_compatible_with, naming),
                file=f,
            )
            print(file=f)
        for e in package_targets:
            print(e, file=f)
            print(file=f)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--prefix",
        type=str,
        required=True,
        help="The prefix to apply to all targets.",
    )

    parser.add_argument(
        "--poetry-project-file",
        type=str,
        required=True,
        help="The path to pyproject.toml.",
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
        action="append",
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
