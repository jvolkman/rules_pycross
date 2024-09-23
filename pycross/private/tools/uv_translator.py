from __future__ import annotations

import re
from collections import defaultdict
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Set
from urllib.parse import unquote
from urllib.parse import urlparse

import tomli
from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.utils import NormalizedName
from packaging.version import Version

from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage

EDITABLE_PATTERN = re.compile("^ *-e +")


class LockfileIncompatibleException(Exception):
    pass


class LockfileNotStaticException(Exception):
    pass


class MismatchedVersionException(Exception):
    pass


def get_default_dependencies(lock: Dict[str, Any]) -> List[Requirement]:
    deps = lock.get("project", {}).get("dependencies", [])
    return [Requirement(dep) for dep in deps]


def get_optional_dependencies(lock: Dict[str, Any]) -> Dict[str, List[Requirement]]:
    dep_groups = lock.get("project", {}).get("optional-dependencies", {})
    return {group: [Requirement(dep) for dep in deps] for group, deps in dep_groups.items()}


def get_development_dependencies(lock: Dict[str, Any]) -> Dict[str, List[Requirement]]:
    dep_groups = lock.get("tool", {}).get("uv", {}).get("dev-dependencies", {})
    return {group: [Requirement(EDITABLE_PATTERN.sub("", dep)) for dep in deps] for group, deps in dep_groups.items()}


def _print_warn(msg):
    print("WARNING:", msg)


@dataclass
class Package:
    name: NormalizedName
    version: Version
    python_versions: SpecifierSet
    dependencies: Set[Requirement]
    files: Set[PackageFile]
    is_local: bool
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
        return req.specifier.contains(self.version, prereleases=True)

    def to_lock_package(self) -> RawPackage:
        assert not self.is_local, "Local packages have no analogue in pycross lockfile"
        dependencies_without_self = sorted(
            [dep for dep in self.resolved_dependencies if dep.key != self.key], key=lambda p: p.key
        )
        return RawPackage(
            name=self.name,
            version=self.version,
            python_versions=str(self.python_versions),
            dependencies=dependencies_without_self,
            files=sorted(self.files, key=lambda f: f.name),
        )

    def merge(self, other: Package) -> Package:
        if (self.name, self.version) != (other.name, other.version):
            raise ValueError(f"Can only merge packages with the same name and version, not {self.key} and {other.key}")
        if self.python_versions != other.python_versions:
            raise ValueError(
                f"Can only merge packages that depend on the same Python version, not {self.python_versions} and {other.python_versions}"
            )

        merged_dependencies = set(self.dependencies) | set(other.dependencies)
        merged_files = set(self.files) | set(other.files)
        merged_is_local = self.is_local or other.is_local
        merged_resolved_dependencies = set(self.resolved_dependencies) | set(other.resolved_dependencies)
        merged_extras = set(self.extras) | set(other.extras)

        return Package(
            name=self.name,
            version=self.version,
            python_versions=self.python_versions,
            dependencies=merged_dependencies,
            files=merged_files,
            is_local=merged_is_local,
            resolved_dependencies=merged_resolved_dependencies,
            extras=merged_extras,
        )


def parse_file_info(file_info: Dict[str, Any]) -> PackageFile:
    if "file" in file_info:
        file_name = file_info["file"]
        urls = tuple()
    elif "url" in file_info:
        url = file_info["url"]
        _, file_name = urlparse(url).path.rsplit("/", 1)
        file_name = unquote(file_name)
        urls = (url,)
    else:
        raise AssertionError("file entry has no file or url member")
    file_hash = file_info["hash"]
    assert file_hash.startswith("sha256:")
    return PackageFile(name=file_name, sha256=file_hash[7:], urls=urls)


# Dataclass to hold the project and lock files
@dataclass
class ProjectFiles:
    project_file: dict
    lock_file: dict


# Function to read the project and lock files


def read_files(project_file: Path, lock_file: Path) -> ProjectFiles:
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

    return ProjectFiles(project_file=project_dict, lock_file=lock_dict)


def validate_uv_lockfile_version(lock_dict: Dict[str, Any]) -> None:
    lock_version = lock_dict.get("version")
    if not isinstance(lock_version, int):
        raise LockfileIncompatibleException(f"Lock file version {lock_version} is not an integer")
    if lock_version != 1:
        raise LockfileIncompatibleException(f"Lock file version {lock_version} is not supported")


def translate(
    project_dict: Dict[str, Any],
    packages_list: list[Dict[str, Any]],
    default_group: bool,
    optional_groups: List[str],
    all_optional_groups: bool,
    development_groups: List[str],
    all_development_groups: bool,
    package_processor: Callable[[list[Dict[str, Any]]], Dict[PackageKey, Package]],
) -> RawLockSet:
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

    distinct_packages = package_processor(packages_list)
    all_packages = distinct_packages.values()

    # Next, group packages by their canonical name
    packages_by_canonical_name: Dict[str, List[Package]] = defaultdict(list)
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
            if pin_spec.specifier.contains(pin_pkg.version, prereleases=True):
                pinned_keys[pin] = pin_pkg.key
                break
        else:
            raise MismatchedVersionException(f"Found no packages to satisfy pin (name={pin}, spec={pin_spec})")

    # Replace pins of local packages with pins of their dependencies.
    # We may need to loop multiple times if local packages depend on one another.
    while local_pins := [key for key in pinned_keys.values() if distinct_packages[key].is_local]:
        for pin_key in local_pins:
            pin_pkg = distinct_packages[pin_key]
            pinned_keys.update({dep.name: dep.key for dep in pin_pkg.resolved_dependencies})
            del pinned_keys[pin_key.name]

    lock_packages: Dict[PackageKey, RawPackage] = {}
    for package in all_packages:
        if package.is_local:
            _print_warn(
                "Local package {} elided from pycross repo. It can still be referenced directly from the main repo.".format(
                    package.key
                )
            )
            continue
        lock_package = package.to_lock_package()
        lock_packages[lock_package.key] = lock_package

    return RawLockSet(
        packages=lock_packages,
        pins=pinned_keys,
    )


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
        help="The path to uv.lock.",
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


def collect_and_process_packages(packages_list: list[Dict[str, Any]]) -> Dict[PackageKey, Package]:
    distinct_packages: Dict[PackageKey, Package] = {}
    # Pull out all Package entries in a uv-specific model.
    for lock_pkg in packages_list:
        package_listed_name = lock_pkg["name"]
        package_name = package_canonical_name(package_listed_name)
        package_version = lock_pkg["version"]
        package_requires_python = lock_pkg.get("requires_python", "")
        package_extras = lock_pkg.get("extras", [])

        if package_requires_python == "*":
            # Special case for all python versions
            package_requires_python = ""

        optional_deps = []
        for dep in lock_pkg.get("optional-dependencies", {}).values():
            optional_deps.extend(dep)
        dependencies = set()
        for dep in lock_pkg.get("dependencies", []) + optional_deps:
            name = dep.get("name")
            version = dep.get("version")
            marker = dep.get("marker")
            if version:
                dep_string = f"{name}=={version}"
            else:
                dep_string = name
            if marker:
                dep_string += f";{marker}"

            dependencies.add(Requirement(dep_string))

        files = lock_pkg.get("wheels", [])
        if lock_pkg.get("sdist"):
            files.append(lock_pkg.get("sdist"))

        files = {parse_file_info(f) for f in files}

        is_local = lock_pkg.get("source") == {"editable": "."} or lock_pkg.get("sdist") == {"path": "."}

        if not files and not is_local:
            raise Exception(lock_pkg, is_local)

        package = Package(
            name=package_name,
            version=Version(package_version),
            python_versions=SpecifierSet(package_requires_python),
            dependencies=dependencies,
            files=files,
            is_local=is_local,
            resolved_dependencies=set(),
            extras=set(package_extras),
        )
        if package.key in distinct_packages:
            distinct_packages[package.key] = package.merge(distinct_packages[package.key])
        else:
            distinct_packages[package.key] = package
    return distinct_packages


def validate_lockfile_version(lock_dict: Dict[str, Any]) -> None:
    lock_version = lock_dict.get("version")
    if not isinstance(lock_version, int):
        raise LockfileIncompatibleException(f"Lock file version {lock_version} is not an integer")
    if lock_version != 1:
        raise LockfileIncompatibleException(f"Lock file version {lock_version} is not supported")


def main(args: Any) -> None:
    """Entry point for the uv_translator script."""

    output = args.output

    project_files = read_files(args.project_file, args.lock_file)

    project_dict = project_files.project_file
    lock_dict = project_files.lock_file

    validate_lockfile_version(lock_dict)

    packages_list = lock_dict.get("package", [])

    lock_set = translate(
        project_dict,
        packages_list,
        default_group=args.default_group,
        optional_groups=args.optional_group,
        all_optional_groups=args.all_optional_groups,
        development_groups=args.development_group,
        all_development_groups=args.all_development_groups,
        package_processor=collect_and_process_packages,
    )

    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


if __name__ == "__main__":
    main(parse_flags())
