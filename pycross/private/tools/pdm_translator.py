import argparse
import os
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import List, Dict

from packaging.utils import NormalizedName
from packaging.utils import Version

from pdm.core import Core as PDMCore
from pdm.project import Project as PDMProject
from pdm.models.repositories import BaseRepository as PDMBaseRepository
from pdm.models.candidates import Candidate as PDMCandidate
from pdm.cli.utils import translate_groups as pdm_translate_groups
from pdm.exceptions import PdmUsageError

from pycross.private.tools.lock_model import LockSet
from pycross.private.tools.lock_model import Package
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import package_canonical_name


class Project(PDMProject):
    def __init__(self, project_file: Path, lock_file: Path, cache_dir: Path) -> None:
        super().__init__(
            core=PDMCore(),
            root_path=project_file.parent.absolute(),
        )
        self._lockfile_file = lock_file.absolute()
        self._pyproject_file = project_file.absolute()
        self._cache_dir = cache_dir

    @property
    def pyproject_file(self) -> Path:
        return self._pyproject_file

    @property
    def cache_dir(self) -> Path:
        return self._cache_dir


def candidate_package_key(candidate: PDMCandidate) -> PackageKey:
    return PackageKey.from_parts(
        package_canonical_name(candidate.name), Version(candidate.version)
    )


def parse_hash_sha256(hash: str) -> str:
    assert hash.startswith("sha256:")
    return hash[7:]


def get_pins(
    project: Project,
    default_dependencies: bool,
    dev_dependencies: bool,
    dependency_groups: List[str],
) -> Dict[NormalizedName, PackageKey]:
    pins = {}
    repository = project.locked_repository
    try:
        groups = pdm_translate_groups(
            project=project,
            default=default_dependencies,
            dev=dev_dependencies,
            groups=dependency_groups,
        )
    except PdmUsageError:
        raise Exception(
            "Failed to resolve groups."
            "Most likely because a dev-group is selected"
            "while dev-dependencies are disabled."
        )
    dependencies = []
    for group in groups:
        dependencies.extend(project.get_dependencies(group).values())

    for dependency in dependencies:
        for candidate in repository.find_candidates(dependency):
            # TODO handle the case where multiple candidates are found
            pin = package_canonical_name(candidate.name)
            pins[pin] = candidate_package_key(candidate)
    return pins


def get_packages(project: Project) -> Dict[PackageKey, Package]:
    packages = {}
    repository = project.locked_repository
    for _package in repository.packages.values():
        # NOTE we need to call `get_dependencies` first, as it also fills `requires_python`
        # NOTE we are calling `get_dependencies` of the parent-class, as it will noll not evaluate markers
        _dependencies, _, _ = PDMBaseRepository.get_dependencies(repository, _package)

        package_key = candidate_package_key(_package)
        package_name = _package.name
        package_version = Version(str(_package.version))
        package_python_versions = _package.requires_python
        package_dependencies = []
        package_files = []

        _package_files = {}
        hashes = repository.get_hashes(_package)
        if not hashes:
            raise Exception(f'package "{package_name}" has not hashes')
        for file_link, file_hash in hashes.items():
            file_name = file_link.filename
            file_url = file_link.url
            file_sha256 = parse_hash_sha256(file_hash)
            if file_name not in _package_files:
                _package_files[file_name] = (file_sha256, [file_url])
            else:
                _file_sha256, _file_urls = _package_files[file_name]
                if file_sha256 != _file_sha256:
                    raise Exception(
                        f'package "{package_name}" has conflicting hashes for "{file_name}"'
                    )
                _file_urls.append(file_url)

        for file_name, (file_sha256, file_urls) in _package_files.items():
            package_files.append(
                PackageFile(name=file_name, sha256=file_sha256, urls=tuple(file_urls))
            )

        for _dependency in _dependencies:
            for _candidate in repository.find_candidates(_dependency):
                # TODO handle the case where multiple candidates are found
                if _candidate.name == _package.name:
                    continue
                dependency = PackageDependency(
                    name=package_canonical_name(_candidate.name),
                    version=Version(_candidate.version),
                    marker=str(_dependency.marker) if _dependency.marker else "",
                )
                package_dependencies.append(dependency)

        # if there are multiple packages with the same name (eg in case of package+extras) merge dependencies into
        # the main package
        if package_key in packages:
            package_dependencies.extend(packages[package_key].dependencies)

        package_dependencies = set(package_dependencies)
        package_dependencies = sorted(package_dependencies, key=lambda d: d.key)

        package = Package(
            name=package_name,
            version=package_version,
            python_versions=package_python_versions,
            dependencies=package_dependencies,
            files=package_files,
        )
        packages[package_key] = package
    return packages


def translate(
    project_file: Path,
    lock_file: Path,
    default_dependencies: bool,
    dev_dependencies: bool,
    dependency_groups: List[str],
) -> LockSet:
    with TemporaryDirectory() as cache_dir:
        project = Project(
            project_file=project_file,
            lock_file=lock_file,
            cache_dir=Path(cache_dir),
        )
        pins = get_pins(
            project=project,
            default_dependencies=default_dependencies,
            dev_dependencies=dev_dependencies,
            dependency_groups=dependency_groups,
        )
        packages = get_packages(project)
        return LockSet(
            packages=packages,
            pins=pins,
        )


def main() -> None:
    parser = make_parser()
    args = parser.parse_args()
    output = args.output

    lock_set = translate(
        project_file=args.project_file,
        lock_file=args.lock_file,
        default_dependencies=args.default_dependencies,
        dev_dependencies=args.dev_dependencies,
        dependency_groups=args.dependency_groups,
    )

    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

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
        dest="default_dependencies",
        action="store_true",
        help="Whether to install dependencies from the default group.",
    )

    parser.add_argument(
        "--dev",
        dest="dev_dependencies",
        action="store_true",
        help="Whether to install dev dependencies.",
    )

    parser.add_argument(
        "--group",
        dest="dependency_groups",
        action="append",
        type=str,
        default=[],
        required=False,
        help="Additional groups to install.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
