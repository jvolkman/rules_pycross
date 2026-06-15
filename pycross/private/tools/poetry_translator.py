import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from typing import List
from typing import Optional

from packaging.specifiers import SpecifierSet
from packaging.utils import InvalidSdistFilename
from packaging.utils import InvalidWheelFilename
from packaging.utils import NormalizedName
from packaging.utils import parse_sdist_filename
from packaging.utils import parse_wheel_filename
from packaging.version import Version
from poetry.core.constraints.version import Version as PoetryVersion
from poetry.core.constraints.version import parse_constraint
from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.translator_utils import resolve_lock_graph


@dataclass
class PoetryDependency:
    name: str
    spec: str
    marker: Optional[str]
    extras: List[str]

    @property
    def constraint(self):
        return parse_constraint(self.spec)

    def matches(self, other: "PoetryPackage") -> bool:
        if package_canonical_name(self.name) != package_canonical_name(other.name):
            return False
        return self.constraint.allows(other.version)


@dataclass
class PoetryPackage:
    name: NormalizedName
    version: PoetryVersion
    python_versions: SpecifierSet
    dependencies: List[PoetryDependency]
    files: List[PackageFile]
    resolved_dependencies: List[PackageDependency]
    is_local: bool = False

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, Version(str(self.version)))

    @property
    def pypa_version(self) -> Version:
        return Version(str(self.version))

    def add_resolved_dependency(self, dep: PackageDependency) -> None:
        self.resolved_dependencies.append(dep)

    def satisfies_dependency(self, dep: PoetryDependency) -> bool:
        return dep.matches(self)

    def satisfies_pin(self, pin: Any) -> bool:
        return pin.allows(self.version)

    def to_lock_package(self) -> RawPackage:
        return RawPackage(
            name=self.name,
            version=self.pypa_version,
            python_versions=self.python_versions,
            dependencies=sorted(self.resolved_dependencies, key=lambda p: p.key),
            files=sorted(self.files, key=lambda f: f.name),
        )


def parse_python_versions(python_versions: str) -> SpecifierSet:
    if python_versions == "*":
        return SpecifierSet()
    return SpecifierSet(python_versions)


def get_files_for_package(
    files: List[PackageFile],
    package_name: NormalizedName,
    package_version: PoetryVersion,
) -> List[PackageFile]:
    result = []
    for file in files:
        try:
            file_package_name, file_package_version, _, _ = parse_wheel_filename(file.name)
        except InvalidWheelFilename:
            try:
                file_package_name, file_package_version = parse_sdist_filename(file.name)
            except InvalidSdistFilename:
                continue

        if file_package_name == package_name and str(file_package_version) == str(package_version):
            result.append(file)

    return result


def translate(
    project_file: Path,
    lock_file: Path,
    default_group: bool,
    optional_groups: List[str],
    all_optional_groups: bool,
) -> RawLockSet:
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

    pinned_package_specs = {}

    dependency_items = []

    if default_group:
        dependency_items.extend((project_dict.get("tool", {}).get("poetry", {}).get("dependencies", {})).items())

    groups = project_dict.get("tool", {}).get("poetry", {}).get("group", {})

    for group_name, group in groups.items():
        if all_optional_groups or group_name in optional_groups:
            dependency_items.extend(group.get("dependencies", {}).items())

    for pin, pin_info in dependency_items:
        pin = package_canonical_name(pin)
        if pin == "python":
            # Skip the special line indicating python version.
            continue
        if isinstance(pin_info, str):
            pinned_package_specs[pin] = parse_constraint(pin_info)
        else:
            if "path" in pin_info:
                # Skip path dependencies.
                continue
            pinned_package_specs[pin] = parse_constraint(pin_info["version"])

    def parse_file_info(file_info) -> PackageFile:
        file_name = file_info["file"]
        file_hash = file_info["hash"]
        assert file_hash.startswith("sha256:")
        return PackageFile(name=file_name, sha256=file_hash[7:])

    # Grab the list of supported Python versions
    lock_python_versions = parse_python_versions(lock_dict.get("metadata", {}).get("python-versions", ""))

    # First, build a list of package files.
    # There are scenarios when files for multiple versions of a package are present in the list. They'll be filtered
    # later.
    lock_files = lock_dict.get("metadata", {}).get("files", {})
    files_by_package_name = {
        package_name: [parse_file_info(f) for f in files] for package_name, files in lock_files.items()
    }

    # Next, pull out all Package entries in a poetry-specific model.
    poetry_packages: List[PoetryPackage] = []
    for lock_pkg in lock_dict.get("package", []):
        package_listed_name = lock_pkg["name"]
        package_name = package_canonical_name(package_listed_name)
        package_version = lock_pkg["version"]
        package_python_versions = lock_pkg["python-versions"]

        dependencies = []
        for name, dep_list in lock_pkg.get("dependencies", {}).items():
            # In some cases the dependency is actually a list of alternatives, each with a different
            # marker. Generally this is not the case, but we coerce a single entry into a list of 1.
            if not isinstance(dep_list, list):
                dep_list = [dep_list]
            for dep in dep_list:
                if isinstance(dep, str):
                    marker = None
                    spec = dep
                    extras = []
                else:
                    marker = dep.get("markers")
                    spec = dep.get("version")
                    extras = dep.get("extras", [])

                dependencies.append(PoetryDependency(name=name, spec=spec, marker=marker, extras=extras))

        source_type = lock_pkg.get("source", {}).get("type")
        is_local = source_type in ("directory", "git", "url")

        files = [parse_file_info(f) for f in lock_pkg.get("files", [])]
        if len(files) == 0:
            files = files_by_package_name.get(package_listed_name, [])

        poetry_packages.append(
            PoetryPackage(
                name=package_name,
                version=PoetryVersion.parse(package_version),
                python_versions=parse_python_versions(package_python_versions),
                dependencies=dependencies,
                files=get_files_for_package(
                    files,
                    package_name,
                    package_version,
                ),
                resolved_dependencies=[],
                is_local=is_local,
            )
        )

    return resolve_lock_graph(
        packages=poetry_packages,
        pinned_package_specs=pinned_package_specs,
        requires_python=lock_python_versions,
        strict_dependencies=True,
    )


def main(args: Any) -> None:
    output = args.output

    lock_set = translate(
        project_file=args.project_file,
        lock_file=args.lock_file,
        default_group=args.default,
        optional_groups=args.optional_group,
        all_optional_groups=args.all_optional_groups,
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
        "--default",
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
        "--output",
        type=Path,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser.parse_args()


if __name__ == "__main__":
    main(parse_flags())
