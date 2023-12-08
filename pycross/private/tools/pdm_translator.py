from __future__ import annotations

import os
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Set
from urllib.parse import urlparse

import tomli
from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.utils import NormalizedName
from packaging.version import Version

from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import LockSet
from pycross.private.tools.lock_model import Package
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey


class LockfileIncompatibleException(Exception):
    pass


class LockfileNotStaticException(Exception):
    pass


class MismatchedVersionException(Exception):
    pass


# We support anything in the 4.x range. At least that's the idea.
SUPPORTED_LOCK_VERSIONS = SpecifierSet("~=4.0")
EDITABLE_PATTERN = re.compile("^ *-e +")


def get_default_dependencies(lock: Dict[str, Any]) -> List[Requirement]:
    deps = lock.get("project", {}).get("dependencies", [])
    return [Requirement(dep) for dep in deps]


def get_optional_dependencies(lock: Dict[str, Any]) -> Dict[str, List[Requirement]]:
    dep_groups = lock.get("project", {}).get("optional-dependencies", {})
    return {group: [Requirement(dep) for dep in deps] for group, deps in dep_groups.items()}


def get_development_dependencies(lock: Dict[str, Any]) -> Dict[str, List[Requirement]]:
    dep_groups = lock.get("tool", {}).get("pdm", {}).get("dev-dependencies", {})
    return {group: [Requirement(EDITABLE_PATTERN.sub("", dep)) for dep in deps] for group, deps in dep_groups.items()}


@dataclass
class PDMPackage:
    name: NormalizedName
    version: Version
    python_versions: SpecifierSet
    dependencies: Set[Requirement]
    files: Set[PackageFile]
    resolved_dependencies: Set[PackageDependency]
    extras: Set[str]

    def __post_init__(self):
        self.extras = set(e.lower() for e in self.extras)

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)

    def satisfies(self, req: Requirement) -> bool:
        # The left side is already canonicalized.
        if self.name != package_canonical_name(req.name):
            return False
        # Extras are case-insensitive. The left side is already lower-cased.
        if not self.extras.issuperset(set(r.lower() for r in req.extras)):
            return False
        return req.specifier.contains(self.version)

    def to_lock_package(self) -> Package:
        dependencies_without_self = sorted(
            [dep for dep in self.resolved_dependencies if dep.key != self.key], key=lambda p: p.key
        )
        return Package(
            name=self.name,
            version=self.version,
            python_versions=str(self.python_versions),
            dependencies=dependencies_without_self,
            files=sorted(self.files, key=lambda f: f.name),
        )

    def merge(self, other: PDMPackage) -> PDMPackage:
        if (self.name, self.version) != (other.name, other.version):
            raise ValueError(f"Can only merge packages with the same name and version, not {self.key} and {other.key}")
        if self.python_versions != other.python_versions:
            raise ValueError(
                f"Can only merge packages that depend on the same Python version, not {self.python_versions} and {other.python_versions}"
            )

        merged_dependencies = set(self.dependencies) | set(other.dependencies)
        merged_files = set(self.files) | set(other.files)
        merged_resolved_dependencies = set(self.resolved_dependencies) | set(other.resolved_dependencies)
        merged_extras = set(self.extras) | set(other.extras)

        return PDMPackage(
            name=self.name,
            version=self.version,
            python_versions=self.python_versions,
            dependencies=merged_dependencies,
            files=merged_files,
            resolved_dependencies=merged_resolved_dependencies,
            extras=merged_extras,
        )


def parse_file_info(file_info: Dict[str, Any]) -> PackageFile:
    if "file" in file_info:
        file_name = file_info["file"]
        urls = None
    elif "url" in file_info:
        url = file_info["url"]
        _, file_name = urlparse(url).path.rsplit("/", 1)
        urls = (url,)
    else:
        raise AssertionError("file entry has no file or url member")
    file_hash = file_info["hash"]
    assert file_hash.startswith("sha256:")
    return PackageFile(name=file_name, sha256=file_hash[7:], urls=urls)


def translate(
    project_file: Path,
    lock_file: Path,
    default_group: bool,
    optional_groups: List[str],
    all_optional_groups: bool,
    development_groups: List[str],
    all_development_groups: bool,
) -> LockSet:
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

    lock_version = lock_dict.get("metadata", {}).get("lock_version")
    if not lock_version:
        raise LockfileIncompatibleException(f"Lock file at {lock_file} has no version")
    if Version(lock_version) not in SUPPORTED_LOCK_VERSIONS:
        raise LockfileIncompatibleException(
            f"Lock file version {lock_version} not included in {SUPPORTED_LOCK_VERSIONS}"
        )

    requirements: List[Requirement] = []

    default_dependencies = get_default_dependencies(project_dict)
    optional_dependencies = get_optional_dependencies(project_dict)
    development_dependencies = get_development_dependencies(project_dict)

    if default_group:
        requirements.extend(default_dependencies)

    if all_optional_groups:
        optional_groups = list(optional_dependencies)

    if all_development_groups:
        development_groups = list(development_dependencies)

    for group_name in optional_groups:
        if group_name not in optional_dependencies:
            raise Exception(f"Non-existent optional dependency group: {group_name}")
        requirements.extend(optional_dependencies[group_name])

    for group_name in development_groups:
        if group_name not in development_dependencies:
            raise Exception(f"Non-existent development dependency group: {group_name}")
        requirements.extend(development_dependencies[group_name])

    pinned_package_specs: Dict[NormalizedName, Requirement] = {}
    for req in requirements:
        pin = package_canonical_name(req.name)
        pinned_package_specs[pin] = req

    distinct_packages: Dict[PackageKey, PDMPackage] = {}
    # Pull out all Package entries in a pdm-specific model.
    for lock_pkg in lock_dict.get("package", []):
        package_listed_name = lock_pkg["name"]
        package_name = package_canonical_name(package_listed_name)
        package_version = lock_pkg["version"]
        package_requires_python = lock_pkg.get("requires_python", "")
        package_extras = lock_pkg.get("extras", [])

        if package_requires_python == "*":
            # Special case for all python versions
            package_requires_python = ""

        dependencies = {Requirement(dep) for dep in lock_pkg.get("dependencies", [])}
        files = {parse_file_info(f) for f in lock_pkg.get("files", [])}

        package = PDMPackage(
            name=package_name,
            version=Version(package_version),
            python_versions=SpecifierSet(package_requires_python),
            dependencies=dependencies,
            files=files,
            resolved_dependencies=set(),
            extras=set(package_extras),
        )
        if package.key in distinct_packages:
            distinct_packages[package.key] = package.merge(distinct_packages[package.key])
        else:
            distinct_packages[package.key] = package

    all_packages = distinct_packages.values()

    # Next, group packages by their canonical name
    packages_by_canonical_name: Dict[str, List[PDMPackage]] = defaultdict(list)
    for package in all_packages:
        packages_by_canonical_name[package.name].append(package)

    # And sort the packages by version in descending order (newest first)
    for package_list in packages_by_canonical_name.values():
        package_list.sort(key=lambda p: p.version, reverse=True)

    # Next, iterate through each package's dependencies and find the newest one that matches.
    # Construct a PackageDependency and store it.
    for package in all_packages:
        for dep in package.dependencies:
            dependency_packages = packages_by_canonical_name[package_canonical_name(dep.name)]
            for dep_pkg in dependency_packages:
                if dep_pkg.satisfies(dep):
                    resolved = PackageDependency(
                        name=dep_pkg.name,
                        version=dep_pkg.version,
                        marker=str(dep.marker or ""),
                    )
                    package.resolved_dependencies.add(resolved)
                    break
            else:
                raise MismatchedVersionException(
                    f"Found no packages to satisfy dependency (name={dep.name}, spec={dep.specifier})"
                )

    pinned_keys: Dict[NormalizedName, PackageKey] = {}
    for pin, pin_spec in pinned_package_specs.items():
        pin_packages = packages_by_canonical_name[pin]
        for pin_pkg in pin_packages:
            if pin_spec.specifier.contains(pin_pkg.version):
                pinned_keys[pin] = pin_pkg.key
                break
        else:
            raise MismatchedVersionException(f"Found no packages to satisfy pin (name={pin}, spec={pin_spec})")

    lock_packages: Dict[PackageKey, Package] = {}
    for package in all_packages:
        lock_package = package.to_lock_package()
        lock_packages[lock_package.key] = lock_package

    return LockSet(
        packages=lock_packages,
        pins=pinned_keys,
    )


def main(args: Any) -> None:
    output = args.output

    lock_set = translate(
        project_file=args.project_file,
        lock_file=args.lock_file,
        default_group=args.default_group,
        optional_groups=args.optional_group,
        all_optional_groups=args.all_optional_groups,
        development_groups=args.development_group,
        all_development_groups=args.all_development_groups,
    )

    if args.require_static_urls:
        for pkg in lock_set.packages.values():
            for file in pkg.files:
                if not file.urls:
                    raise LockfileNotStaticException(
                        "Lock file does not contain static urls. Please use --static-urls when creating the lockfile."
                    )

    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Generate pycross dependency bzl file.")

    parser.add_argument(
        "--project-file",
        type=Path,
        required=True,
        help="The path to pyproject.toml.",
    )

    parser.add_argument(
        "--lock-file",
        type=Path,
        required=True,
        help="The path to pdm.lock.",
    )

    parser.add_argument(
        "--default-group",
        action="store_true",
        help="Whether to install dependencies from the default group.",
    )

    parser.add_argument(
        "--optional-group",
        action="append",
        default=[],
        help="Optional dependency groups to install.",
    )

    parser.add_argument(
        "--all-optional-groups",
        action="store_true",
        help="Install all optional dependency groups.",
    )

    parser.add_argument(
        "--development-group",
        action="append",
        default=[],
        help="Development dependency groups to install.",
    )

    parser.add_argument(
        "--all-development-groups",
        action="store_true",
        help="Install all development dependency groups.",
    )

    parser.add_argument(
        "--require-static-urls",
        action="store_true",
        help="Require that the lock file provide static URLs.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser.parse_args()


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main(parse_flags())
