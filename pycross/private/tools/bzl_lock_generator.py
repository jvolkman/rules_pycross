import argparse
import json
import os
import sys
import textwrap
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict
from typing import Iterator
from typing import List
from typing import Optional
from typing import Set
from typing import Union

import tomli
from packaging.markers import Marker
from packaging.specifiers import SpecifierSet
from packaging.version import Version
from pip._internal.index.package_finder import CandidateEvaluator
from pip._internal.index.package_finder import LinkEvaluator
from pip._internal.models.candidate import InstallationCandidate
from pip._internal.models.link import Link

from pycross.private.tools.target_environment import TargetEnv


# For downloads: https://github.com/pypa/warehouse/issues/1944
WAREHOUSE_HOST = "https://files.pythonhosted.org"


def ind(text: str, tabs=1):
    """Indent text with the given number of tabs."""
    return textwrap.indent(text, "    " * tabs)


def package_canonical_name(name: str) -> str:
    # Canonical package names are lower-cased with dashes, not underscores.
    return name.lower().replace("_", "-")


def package_label_name(name: str) -> str:
    # Label names use underscores instead of dashes.
    return name.lower().replace("-", "_")


def is_wheel(filename: str) -> bool:
    return filename.lower().endswith(".whl")


def pypi_url(filename: str, overrides: Optional[Dict[str, str]] = None) -> str:
    """Returns the pypi URL for fetching this file."""
    if overrides and filename in overrides:
        return overrides[filename]

    # See:
    # https://github.com/pypa/warehouse/issues/1239
    # https://github.com/pypa/warehouse/issues/1944

    filename_parts = filename.split("-")
    name = filename_parts[0]
    if is_wheel(filename):
        area = filename_parts[-3]  # python_tag
    else:
        area = "source"

    return f"{WAREHOUSE_HOST}/packages/{area}/{name[0]}/{name}/{filename}"


@dataclass(frozen=True)
class PackageFile:
    name: str
    hash: str
    url: str

    @property
    def is_wheel(self) -> bool:
        return is_wheel(self.name)

    @property
    def link(self) -> Link:
        return Link(self.url)


class PackageFileSet:
    def __init__(
        self, package_name: str, package_version: str, files: List[PackageFile]
    ):
        self.package_name = package_name
        self.package_version = package_version
        self.files = files

    def get_file_for_environment(
        self, environment: TargetEnv, source_only: bool = False
    ) -> PackageFile:
        formats = (
            frozenset(["source"]) if source_only else frozenset(["source", "binary"])
        )
        evaluator = LinkEvaluator(
            project_name=self.package_name,
            canonical_name=package_canonical_name(self.package_name),
            formats=formats,
            target_python=environment.target_python,
            allow_yanked=True,
            ignore_requires_python=True,
        )

        candidates_to_files = {
            InstallationCandidate(self.package_name, self.package_version, f.link): f
            for f in self.files
        }
        candidates = []
        for candidate in candidates_to_files:
            valid, _ = evaluator.evaluate_link(candidate.link)
            if valid:
                candidates.append(candidate)

        evaluator = CandidateEvaluator.create(
            self.package_name, environment.target_python
        )
        result = evaluator.compute_best_candidate(candidates)

        return candidates_to_files[result.best_candidate]


class Naming:
    def __init__(self, package_prefix: Optional[str], build_prefix: Optional[str], environment_prefix: Optional[str], repo_prefix: Optional[str]):
        self.package_prefix = package_prefix
        self.build_prefix = build_prefix
        self.environment_prefix = environment_prefix
        self.repo_prefix = repo_prefix

    @staticmethod
    def _sanitize(name: str) -> str:
        return name.lower().replace("-", "_")

    @staticmethod
    def _prefixed(name: str, prefix: Optional[str]):
        if not prefix:
            return name
        # Strip any trailing underscores from the provided prefix, first, then add one of our own.
        return prefix.rstrip("_") + "_" + name

    def package_target(self, package_name: str) -> str:
        return self._prefixed(self._sanitize(package_name), self.package_prefix)

    def package_label(self, package_name: str) -> str:
        return f":{self.package_target(package_name)}"

    def environment_target(self, environment_name: str) -> str:
        return self._prefixed(self._sanitize(environment_name), self.environment_prefix)

    def environment_label(self, environment_name: str) -> str:
        return f":{self.environment_target(environment_name)}"

    def wheel_repo(self, file: PackageFile) -> str:
        assert file.is_wheel
        normalized_name = file.name[:-4].lower().replace("-", "_")
        return f"{self.repo_prefix}_wheel_{normalized_name}"

    def wheel_build_target(self, package_or_file: Union[str, PackageFile]) -> str:
        if isinstance(package_or_file, PackageFile):
            assert not package_or_file.is_wheel
            parts = package_or_file.name.split("-")
            name = parts[0].lower()
            return self._prefixed(name, self.build_prefix)
        else:
            return self._prefixed(package_or_file, self.build_prefix)

    def sdist_repo(self, file: PackageFile) -> str:
        assert file.name.endswith(".tar.gz")
        name = file.name[:-7]
        return f"{self.repo_prefix}_sdist_{self._sanitize(name)}"

    def sdist_label(self, file: PackageFile) -> str:
        return f"@{self.sdist_repo(file)}//file"

    def wheel_label(self, file: PackageFile):
        if file.is_wheel:
            return f"@{self.wheel_repo(file)}//file"
        else:
            return f":{self.wheel_build_target(file)}"


@dataclass(frozen=True)
class Dependency:
    name: str
    marker: Optional[Marker]

    @property
    def canonical_name(self) -> str:
        return package_canonical_name(self.name)


@dataclass
class PoetryPackage:
    name: str
    version: Version
    requires_python: SpecifierSet
    all_extras: Set[str]
    dependencies: Set[Dependency]

    @property
    def canonical_name(self) -> str:
        return package_canonical_name(self.name)

    @property
    def label_name(self) -> str:
        return package_label_name(self.name)

    def supports_environment(self, environment: TargetEnv) -> bool:
        return self.requires_python.contains(environment.version)

    def dependencies_by_environment(
        self, environments: List[TargetEnv]
    ) -> Dict[Optional[str], Set[Dependency]]:
        env_deps = defaultdict(list)
        for dep in self.dependencies:
            for target in environments:

                # If the dependency has no marker, just add it for each environment.
                if not dep.marker:
                    env_deps[target.name].append(dep)

                # Only requested extra dependencies are included in a package's deps list - whether they're requested
                # by a top-level requirement or by some transitive dependency. Their specifiers still include
                # `extra == "foo"` in addition to any platform-specific markers, so to match we need to include the
                # correct extra value in our marker environment. We don't know the correct value, so instead we just
                # try all possible extra names until something matches.
                elif self.all_extras:
                    for extra in self.all_extras:
                        markers_with_extra = dict(target.markers, extra=extra)
                        if dep.marker.evaluate(markers_with_extra):
                            env_deps[target.name].append(dep)
                            break

                # Otherwise, if no extras, just evaluate the markers normally.
                else:
                    if dep.marker.evaluate(target.markers):
                        env_deps[target.name].append(dep)

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
    def __init__(
        self,
        pinned_package_names: Set[str],
        packages: List[PoetryPackage],
        package_file_sets: Dict[str, PackageFileSet],
    ):
        self.pinned_package_names = pinned_package_names
        self.packages = packages
        self.package_file_sets = package_file_sets

    @staticmethod
    def create(
        project_file: str, lock_file: str, url_overrides: Dict[str, str]
    ) -> "PoetryMetadata":
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
            pinned = package_canonical_name(pinned)
            if pinned == "python":
                # Skip the special line indicating python version.
                continue
            pinned_package_names.add(pinned)

        metadata_files = {
            package_canonical_name(k): v
            for k, v in lock_dict.get("metadata", {}).get("files", {}).items()
        }

        packages = []
        package_file_sets = {}
        for lock_pkg in lock_dict.get("package", []):
            package_name = lock_pkg["name"]
            package_version = lock_pkg["version"]
            package = PoetryPackage(
                name=package_name,
                version=Version(package_version),
                all_extras=lock_pkg.get("extras", {}).keys(),
                requires_python=SpecifierSet(lock_pkg.get("requires_python", "")),
                dependencies={
                    poetry_requirement(name, spec)
                    for name, spec in lock_pkg.get("dependencies", {}).items()
                },
            )
            packages.append(package)

            package_file_dicts = metadata_files[package.canonical_name]
            package_files = [
                PackageFile(
                    name=p["file"],
                    hash=p["hash"],
                    url=pypi_url(p["file"], url_overrides),
                )
                for p in package_file_dicts
            ]
            package_file_sets[package.canonical_name] = PackageFileSet(
                package.name, package_version, package_files
            )

        return PoetryMetadata(pinned_package_names, packages, package_file_sets)


class EnvTarget:
    def __init__(self, environment_name: str, constraints: List[str], naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.constraints = constraints

    def render(self) -> str:
        lines = [
            "native.config_setting(",
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
        package: PoetryPackage,
        naming: Naming,
        package_file_set: PackageFileSet,
        environments: List[TargetEnv],
    ):
        self.package = package
        self.naming = naming
        self.package_file_set = package_file_set
        self.common_deps: Set[Dependency] = set()
        self.environments = environments
        self.env_deps: Dict[str, Set[Dependency]] = {}

        deps_by_env = package.dependencies_by_environment(environments)
        self.common_deps = deps_by_env.get(None, set())
        self.env_deps = {k: v for k, v in deps_by_env.items() if k is not None}

        self.files_by_env = {
            e.name: package_file_set.get_file_for_environment(e) for e in environments
        }
        self.distinct_files = set(self.files_by_env.values())

    @property
    def all_dependency_names(self) -> Set[str]:
        """Returns all package names (lower-cased) that this target depends on, including platform-specific."""
        names = set(package_canonical_name(d.name) for d in self.common_deps)
        for env_deps in self.env_deps.values():
            names |= set(package_canonical_name(d.name) for d in env_deps)
        return names

    @property
    def source_file(self) -> Optional[PackageFile]:
        for f in self.distinct_files:
            if not f.is_wheel:
                return f

    @property
    def has_deps(self) -> bool:
        return bool(self.common_deps or self.env_deps)

    @property
    def has_source(self) -> bool:
        return self.source_file is not None

    def _common_entries(self, deps: Set[Dependency], indent: int) -> Iterator[str]:
        for d in sorted(deps, key=lambda x: package_canonical_name(x.name)):
            yield ind(f'"{self.naming.package_label(d.name)}",', indent)

    def _select_entries(
        self, env_deps: Dict[str, Set[PoetryPackage]], indent
    ) -> Iterator[str]:
        for env_name, deps in sorted(env_deps.items(), key=lambda x: x[0].lower()):
            yield ind(f'"{self.naming.environment_label(env_name)}": [', indent)
            yield from self._common_entries(deps, indent + 1)
            yield ind("],", indent)
        yield ind('"//conditions:default": [],', indent)

    @property
    def _deps_name(self):
        return f"_{self.package.label_name}_deps"

    def render_deps(self) -> str:
        assert self.has_deps
        lines = []

        if self.common_deps and self.env_deps:
            lines.append(f"{self._deps_name} = [")
            lines.extend(self._common_entries(self.common_deps, 1))
            lines.append("] + select({")
            lines.extend(self._select_entries(self.env_deps, 1))
            lines.append("})")

        elif self.common_deps:
            lines.append(f"{self._deps_name} = [")
            lines.extend(self._common_entries(self.common_deps, 1))
            lines.append("]")

        elif self.env_deps:
            lines.append(self._deps_name + " = select({")
            lines.extend(self._select_entries(self.env_deps, 1))
            lines.append("})")

        return "\n".join(lines)

    def render_build(self) -> str:
        source_file = self.source_file
        assert source_file is not None

        lines = [
            "pycross_wheel_build(",
            ind(
                f'name = "{self.naming.wheel_build_target(self.package.canonical_name)}",'
            ),
            ind(f'sdist = "{self.naming.sdist_label(source_file)}",'),
        ]
        if self.has_deps:
            lines.append(ind(f"deps = {self._deps_name},"))
        lines.extend(
            [
                ind('tags = ["manual"],'),
                ")",
            ]
        )

        return "\n".join(lines)

    def render_pkg(self) -> str:
        lines = [
            "pycross_wheel_library(",
            ind(f'name = "{self.naming.package_target(self.package.canonical_name)}",'),
        ]
        if self.has_deps:
            lines.append(ind(f"deps = {self._deps_name},"))

        # Add the wheel attribute.
        # If all environments use the same wheel, don't use select.
        if len(self.distinct_files) == 1:
            file = next(iter(self.distinct_files))
            lines.append(ind(f'wheel = "{self.naming.wheel_label(file)}",'))
        else:
            lines.append(ind("wheel = select({"))
            for env_name, file in self.files_by_env.items():
                lines.append(
                    ind(
                        f'"{self.naming.environment_label(env_name)}": "{self.naming.wheel_label(file)}",',
                        2,
                    )
                )
            lines.append(ind("}),"))

        lines.append(")")

        return "\n".join(lines)

    def render(self) -> str:
        parts = []
        if self.has_deps:
            parts.append(self.render_deps())
            parts.append("")
        if self.has_source:
            parts.append(self.render_build())
            parts.append("")
        parts.append(self.render_pkg())
        return "\n".join(parts)


class FileRepoTarget:
    def __init__(self, name: str, file: PackageFile):
        self.name = name
        self.file = file

    def render(self) -> str:
        assert self.file.hash.startswith("sha256:")
        sha256 = self.file.hash[7:]
        lines = [
            "maybe(",
            ind("http_file,"),
            ind(f'name = "{self.name}",'),
            ind(f'urls = ["{self.file.url}"],'),
            ind(f'sha256 = "{sha256}",'),
            ind(f'downloaded_file_path = "{self.file.name}",'),
            ")",
        ]

        return "\n".join(lines)


class WheelRepoTarget(FileRepoTarget):
    def __init__(self, file: PackageFile, naming: Naming):
        super().__init__(naming.wheel_repo(file), file)


class SdistRepoTarget(FileRepoTarget):
    def __init__(self, file: PackageFile, naming: Naming):
        super().__init__(naming.sdist_repo(file), file)


def check_package_compatibility(
    package: PoetryPackage, environments: List[TargetEnv]
) -> None:
    """Sanity check to make sure the requires_python attribute on each package matches our environments."""
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

    # TODO: Make this a file instead
    url_overrides = {}
    for url_override in args.file_url or []:
        filename, url = url_override.split("=", maxsplit=1)
        url_overrides[filename] = url

    naming = Naming(repo_prefix=args.repo_prefix, package_prefix=args.package_prefix, build_prefix=args.build_prefix, environment_prefix=args.environment_prefix)
    metadata = PoetryMetadata.create(
        args.poetry_project_file, args.poetry_lock_file, url_overrides
    )

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
        entry = PackageTarget(
            package,
            naming,
            metadata.package_file_sets[next_package_name],
            environments,
        )
        package_targets_by_package_name[next_package_name] = entry
        work.extend(entry.all_dependency_names)

    package_targets = sorted(
        package_targets_by_package_name.values(), key=lambda x: x.package.canonical_name
    )

    repos = []
    for package in package_targets:
        for file in package.distinct_files:
            if file.is_wheel:
                repos.append(WheelRepoTarget(file, naming))
            else:
                repos.append(SdistRepoTarget(file, naming))

    repos.sort(key=lambda r: r.name)

    with open(output, "w") as f:

        def w(text=""):
            print(text, file=f)

        # Header stuff
        w('load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")')
        w('load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")')
        w(
            'load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library")'
        )
        w()

        # Build targets
        w("def targets():")

        for environment in sorted(environments, key=lambda x: x.name.lower()):
            env_target = EnvTarget(
                environment.name, environment.python_compatible_with, naming
            )
            w(ind(env_target.render()))
            w()

        for e in package_targets:
            w(ind(e.render()))
            w()

        # Repos
        w("def repositories():")
        for r in repos:
            w(ind(r.render()))
            w()


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--repo-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to repository targets.",
    )

    parser.add_argument(
        "--package-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to packages targets.",
    )

    parser.add_argument(
        "--build-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to package build targets.",
    )

    parser.add_argument(
        "--environment-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to packages environment targets.",
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
        "--file-url",
        type=str,
        action="append",
        help="A file=url parameter that sets the URL for the given wheel or sdist file.",
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
