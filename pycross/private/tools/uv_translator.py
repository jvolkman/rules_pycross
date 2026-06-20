from __future__ import annotations

import hashlib
import tomllib
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Set
from typing import Tuple
from urllib.parse import unquote
from urllib.parse import urlparse

from packaging.markers import Marker
from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.version import Version
from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import DependencyName
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.lock_model import VariantItem
from pycross.private.tools.lock_model import VariantSet
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.translator_utils import resolve_lock_graph


class LockfileIncompatibleException(Exception):
    pass


class LockfileNotStaticException(Exception):
    pass


@dataclass
class Package:
    name: DependencyName
    version: Version
    python_versions: List[SpecifierSet]
    dependencies: Set[Requirement]
    files: Set[PackageFile]
    is_local: bool
    resolved_dependencies: Set[PackageDependency]
    extras: Set[str]
    source_dir: str | None = None

    def __post_init__(self):
        self.extras = set(e.lower() for e in self.extras)

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)

    def satisfies(self, req: Requirement) -> bool:
        req_extra = list(req.extras)[0] if req.extras else None
        req_name = DependencyName.from_parts(req.name, req_extra)
        if self.name != req_name:
            return False
        return req.specifier.contains(self.version, prereleases=True)

    @property
    def pypa_version(self) -> Version:
        return self.version

    def add_resolved_dependency(self, dep: PackageDependency) -> None:
        self.resolved_dependencies.add(dep)

    def satisfies_dependency(self, dep: Requirement) -> bool:
        return self.satisfies(dep)

    def satisfies_pin(self, pin: Requirement) -> bool:
        return pin.specifier.contains(self.version, prereleases=True)

    def to_lock_package(self) -> RawPackage:
        assert not self.is_local, "Local packages have no analogue in pycross lockfile"
        dependencies_without_self = sorted(
            [dep for dep in self.resolved_dependencies if dep.key != self.key], key=lambda p: p.key
        )
        return RawPackage(
            name=self.name,
            version=self.version,
            python_versions=self.python_versions[0] if self.python_versions else SpecifierSet(),
            python_version_specifiers=self.python_versions,
            dependencies=dependencies_without_self,
            files=sorted(self.files, key=lambda f: f.name),
            source_dir=self.source_dir,
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
            source_dir=self.source_dir or other.source_dir,
        )


def parse_file_info(file_info: Dict[str, Any]) -> PackageFile:
    if "file" in file_info:
        file_name = file_info["file"]
        urls = tuple()
    elif "filename" in file_info:
        file_name = file_info["filename"]
        urls = tuple()
    elif "url" in file_info:
        url = file_info["url"]
        _, file_name = urlparse(url).path.rsplit("/", 1)
        file_name = unquote(file_name)
        urls = (url,)
    else:
        raise AssertionError(f"file entry has no file, filename or url member: {file_info}")
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
            project_dict = tomllib.load(f)
    except Exception as e:
        raise Exception(f"Could not load project file: {project_file}: {e}")

    try:
        with open(lock_file, "rb") as f:
            lock_dict = tomllib.load(f)
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
    project_name: str,
    packages_list: list[Dict[str, Any]],
    requires_python: SpecifierSet,
    default_group: bool,
    optional_groups: List[str],
    all_optional_groups: bool,
    development_groups: List[str],
    all_development_groups: bool,
    package_processor: Callable[[list[Dict[str, Any]]], Dict[PackageKey, Package]],
    variants: List[List[Dict[str, str]]] | None = None,
    default_groups: List[str] = None,
) -> RawLockSet:
    variants = variants or []
    default_groups = set(default_groups or [])

    # Parse conflict entries into VariantItem/VariantSet objects.
    # Each uv conflict entry has a "package" and optionally "extra" or "group" key.
    # When neither extra nor group is present, it's a project-level conflict.
    # We use VariantItem.qualified_name as the constraint key for pins.
    #
    # Items whose group name appears in default_groups are marked default=True.
    # On the Bazel side, the default item's target is used for //conditions:default
    # in the select(), so builds without explicit flags use the default variant.
    variant_items_by_source: Dict[Tuple[str, str, str], VariantItem] = {}  # (package, kind, name) -> VariantItem
    variant_sets: List[VariantSet] = []
    for variant_list in variants:
        items = []
        for c in variant_list:
            package = c["package"]
            if "extra" in c:
                kind, name = "extra", c["extra"]
            elif "group" in c:
                kind, name = "group", c["group"]
            else:
                kind, name = "project", ""
            key = (package, kind, name)
            if key not in variant_items_by_source:
                is_default = kind == "group" and name in default_groups
                variant_items_by_source[key] = VariantItem(
                    package=package,
                    kind=kind,
                    name=name,
                    default=is_default,
                )
            items.append(variant_items_by_source[key])
        variant_sets.append(VariantSet(items=tuple(items)))

    # Build a lookup from (kind, name) -> qualified_name for constraint assignment.
    # This maps optional group names and dev group names to their qualified constraint values.
    extra_variant_values: Dict[str, str] = {}  # extra_name -> qualified constraint value
    group_variant_values: Dict[str, str] = {}  # group_name -> qualified constraint value
    for item in variant_items_by_source.values():
        if item.kind == "extra":
            extra_variant_values[item.name] = item.qualified_name
        elif item.kind == "group":
            group_variant_values[item.name] = item.qualified_name

    requirements: List[Tuple[Requirement, str]] = []

    project_info = next(pkg for pkg in packages_list if package_canonical_name(pkg["name"]) == project_name)

    def parse_dependency(dep: Dict[str, Any]) -> Requirement:
        name = dep["name"]
        extras = dep.get("extra") or dep.get("extras", [])
        if extras:
            req_str = f"{name}[{','.join(extras)}]"
        else:
            req_str = name
        if "version" in dep:
            req_str += f"=={dep['version']}"
        if "marker" in dep:
            req_str += f"; {dep['marker']}"
        return Requirement(req_str)

    default_dependencies = [parse_dependency(dep) for dep in project_info.get("dependencies", {})]
    optional_dependencies = {
        group: [parse_dependency(dep) for dep in deps]
        for group, deps in project_info.get("optional-dependencies", {}).items()
    }
    development_dependencies = {
        group: [parse_dependency(dep) for dep in deps]
        for group, deps in project_info.get("dev-dependencies", {}).items()
    }

    if default_group:
        for dep in default_dependencies:
            requirements.append((dep, ""))

    if all_optional_groups:
        optional_groups = list(optional_dependencies)

    if all_development_groups:
        development_groups = list(development_dependencies)

    for group_name in optional_groups:
        if group_name not in optional_dependencies:
            raise Exception(f"Non-existent optional dependency group: {group_name}")
        constraint = extra_variant_values.get(group_name, "")
        for dep in optional_dependencies[group_name]:
            requirements.append((dep, constraint))

    for group_name in development_groups:
        if group_name not in development_dependencies:
            raise Exception(f"Non-existent development dependency group: {group_name}")
        constraint = group_variant_values.get(group_name, "")
        for dep in development_dependencies[group_name]:
            requirements.append((dep, constraint))

    pinned_package_specs: Dict[DependencyName, Dict[str, Requirement]] = {}
    for req, constraint in requirements:
        if req.extras:
            for extra in req.extras:
                pin = DependencyName.from_parts(req.name, extra)
                req_string = f"{req.name}[{extra}]{req.specifier}" if req.specifier else f"{req.name}[{extra}]"
                if req.marker:
                    req_string += f";{req.marker}"
                if pin not in pinned_package_specs:
                    pinned_package_specs[pin] = {}
                pinned_package_specs[pin][constraint] = Requirement(req_string)
        else:
            pin = package_canonical_name(req.name)
            if pin not in pinned_package_specs:
                pinned_package_specs[pin] = {}
            pinned_package_specs[pin][constraint] = req

    distinct_packages = package_processor(packages_list)
    return resolve_lock_graph(
        packages=distinct_packages.values(),
        pinned_package_specs=pinned_package_specs,
        requires_python=requires_python,
        strict_dependencies=True,
        variants=variant_sets,
    )


def collect_and_process_packages(packages_list: list[Dict[str, Any]]) -> Dict[PackageKey, Package]:
    distinct_packages: Dict[PackageKey, Package] = {}
    # Pull out all Package entries in a uv-specific model.
    for lock_pkg in packages_list:
        package_listed_name = lock_pkg["name"]
        package_name = package_canonical_name(package_listed_name)
        package_version = lock_pkg["version"]
        package_requires_python = resolve_package_requires_python(lock_pkg.get("resolution-markers", []))
        package_extras = lock_pkg.get("extras", [])

        base_dependencies = set()
        for dep in lock_pkg.get("dependencies", []):
            name = dep.get("name")
            version = dep.get("version")
            marker = dep.get("marker")
            extras = dep.get("extra") or dep.get("extras", [])
            if extras:
                for extra in extras:
                    dep_string = f"{name}[{extra}]"
                    if version:
                        dep_string += f"=={version}"
                    if marker:
                        dep_string += f";{marker}"
                    base_dependencies.add(Requirement(dep_string))
            else:
                dep_string = f"{name}=={version}" if version else name
                if marker:
                    dep_string += f";{marker}"
                base_dependencies.add(Requirement(dep_string))

        extra_dependencies = {}
        for extra_name, deps in lock_pkg.get("optional-dependencies", {}).items():
            parsed_deps = set()
            for dep in deps:
                name = dep.get("name")
                version = dep.get("version")
                marker = dep.get("marker")
                extras = dep.get("extra") or dep.get("extras", [])
                if extras:
                    for extra in extras:
                        dep_string = f"{name}[{extra}]"
                        if version:
                            dep_string += f"=={version}"
                        if marker:
                            dep_string += f";{marker}"
                        parsed_deps.add(Requirement(dep_string))
                else:
                    dep_string = f"{name}=={version}" if version else name
                    if marker:
                        dep_string += f";{marker}"
                    parsed_deps.add(Requirement(dep_string))
            extra_dependencies[extra_name] = parsed_deps

        files = lock_pkg.get("wheels", [])
        if lock_pkg.get("sdist"):
            files.append(lock_pkg.get("sdist"))

        files = {parse_file_info(f) for f in files}

        source = lock_pkg.get("source", {})
        sdist = lock_pkg.get("sdist", {})

        files = {parse_file_info(f) for f in lock_pkg.get("wheels", [])}
        if sdist:
            if "url" in sdist or "file" in sdist:
                files.add(parse_file_info(sdist))
            elif "url" in source:
                # URL-based sources (e.g. an archive referenced with a
                # `#subdirectory=` fragment) put the download URL on the
                # `source` entry rather than the `sdist` entry. The archive
                # file name (e.g. a git ref tarball) is not a PEP 503 sdist
                # name, which both PackageFile and pip's link evaluator
                # reject, so synthesise a canonical `{name}-{version}.tar.gz`
                # file name while keeping the real download URL.
                url = source["url"]
                file_hash = sdist["hash"]
                assert file_hash.startswith("sha256:")
                file_name = f"{package_name}-{package_version}.tar.gz"
                files.add(
                    PackageFile(
                        name=file_name,
                        sha256=file_hash[7:],
                        urls=(url,),
                        package_name=package_name,
                        package_version=Version(package_version),
                    )
                )
            else:
                files.add(parse_file_info(sdist))
        elif "git" in source:
            git_url = source["git"]
            parsed = urlparse(git_url)
            commit = parsed.fragment
            if not commit:
                raise Exception(f"Git source must specify a commit hash in the fragment: {git_url}")
            # Synthetic hash derived from the commit string, NOT a content hash.
            # Used as a stable cache key — if the commit changes, the hash changes.
            synthetic_hash = hashlib.sha256(commit.encode("utf-8")).hexdigest()
            file_name = f"{package_name}-{package_version}.tar.gz"
            files.add(
                PackageFile(
                    name=file_name,
                    sha256=synthetic_hash,
                    urls=(f"git+{git_url}",),
                    package_name=package_name,
                    package_version=Version(package_version),
                )
            )

        # Extract source_dir if present
        source_dir = source.get("subdirectory")

        # Check for editable source (any path value)
        is_local_editable = "editable" in source and isinstance(source.get("editable"), str)

        # Check for virtual source (any path value)
        is_local_virtual = "virtual" in source and isinstance(source.get("virtual"), str)

        # Check for sdist with path (not URL-based - local sdists have "path" but not "url")
        is_local_sdist = isinstance(sdist, dict) and "path" in sdist and "url" not in sdist

        is_local = is_local_sdist or is_local_editable or is_local_virtual

        if not files and not is_local:
            raise Exception(lock_pkg, is_local)

        base_package = Package(
            name=package_name,
            version=Version(package_version),
            python_versions=package_requires_python,
            dependencies=base_dependencies,
            files=files,
            is_local=is_local,
            resolved_dependencies=set(),
            extras=set(package_extras),
            source_dir=source_dir,
        )
        if base_package.key in distinct_packages:
            distinct_packages[base_package.key] = base_package.merge(distinct_packages[base_package.key])
        else:
            distinct_packages[base_package.key] = base_package

        for extra_name, deps in extra_dependencies.items():
            extra_deps = set(deps)
            extra_deps.add(Requirement(f"{package_listed_name}=={package_version}"))

            extra_package = Package(
                name=DependencyName.from_parts(package_listed_name, extra_name),
                version=Version(package_version),
                python_versions=package_requires_python,
                dependencies=extra_deps,
                files=set(),
                is_local=is_local,
                resolved_dependencies=set(),
                extras=set(),
                source_dir=source_dir,
            )
            if extra_package.key in distinct_packages:
                distinct_packages[extra_package.key] = extra_package.merge(distinct_packages[extra_package.key])
            else:
                distinct_packages[extra_package.key] = extra_package
    return distinct_packages


def resolve_package_requires_python(markers: list[str]) -> List[SpecifierSet]:
    specifiers = []
    for marker in markers:
        # Use Marker implementation details to parse marker
        match Marker(marker)._markers:
            case [(l, op, r)] if l.value == "python_full_version":
                specifiers.append(SpecifierSet(f"{op.value} {r.value}"))
    return specifiers


def validate_lockfile_version(lock_dict: Dict[str, Any]) -> None:
    lock_version = lock_dict.get("version")
    if not isinstance(lock_version, int):
        raise LockfileIncompatibleException(f"Lock file version {lock_version} is not an integer")
    if lock_version != 1:
        raise LockfileIncompatibleException(f"Lock file version {lock_version} is not supported")


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


def main(args: Any) -> None:
    """Entry point for the uv_translator script."""

    output = args.output

    project_files = read_files(args.project_file, args.lock_file)

    project_dict = project_files.project_file
    project_name = package_canonical_name(project_dict["project"]["name"])

    lock_dict = project_files.lock_file
    validate_lockfile_version(lock_dict)

    # backwards-compatiblity for https://github.com/astral-sh/uv/pull/5861
    distributions_list = lock_dict.get("distribution", [])
    packages_list = lock_dict.get("package", distributions_list)
    requires_python = SpecifierSet(lock_dict.get("requires-python", ""))

    # Extract default-groups from [tool.uv] in pyproject.toml.
    uv_settings = project_dict.get("tool", {}).get("uv", {})
    uv_default_groups = uv_settings.get("default-groups", [])

    lock_set = translate(
        project_name,
        packages_list,
        requires_python,
        default_group=args.default_group,
        optional_groups=args.optional_group,
        all_optional_groups=args.all_optional_groups,
        development_groups=args.development_group,
        all_development_groups=args.all_development_groups,
        package_processor=collect_and_process_packages,
        variants=lock_dict.get("conflicts", []),
        default_groups=uv_default_groups,
    )

    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


if __name__ == "__main__":
    main(parse_flags())
