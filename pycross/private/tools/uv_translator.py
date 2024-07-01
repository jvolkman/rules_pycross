from __future__ import annotations

import os
from typing import Any
from typing import Dict

from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.version import Version

from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.translation_utils import LockfileIncompatibleException
from pycross.private.tools.translation_utils import Package
from pycross.private.tools.translation_utils import parse_file_info
from pycross.private.tools.translation_utils import parse_flags
from pycross.private.tools.translation_utils import read_files
from pycross.private.tools.translation_utils import translate


def collect_and_process_packages(packages_list: list[Dict[str, Any]]) -> Dict[PackageKey, Package]:
    distinct_packages: Dict[PackageKey, Package] = {}
    # Pull out all Package entries in a pdm-specific model.
    for lock_pkg in packages_list:
        package_listed_name = lock_pkg["name"]
        package_name = package_canonical_name(package_listed_name)
        package_version = lock_pkg["version"]
        package_requires_python = lock_pkg.get("requires_python", "")
        package_extras = lock_pkg.get("extras", [])

        if package_requires_python == "*":
            # Special case for all python versions
            package_requires_python = ""

        dependencies = set()
        for dep in lock_pkg.get("dependencies", []):
            if isinstance(dep, dict):
                dep_string = (
                    f"{dep['name']}=={dep['version']};{dep['marker']}"
                    if dep.get("marker")
                    else f"{dep['name']}=={dep['version']}"
                )
                dependencies.add(Requirement(dep_string))
            else:
                dependencies.add(Requirement(dep))

        # dependencies = {Requirement(dep) for dep in lock_pkg.get("dependencies", [])}
        files = {parse_file_info(f) for f in lock_pkg.get("files", lock_pkg.get("wheels", []))}
        is_local = ("path" in lock_pkg and "files" not in lock_pkg) or lock_pkg.get("sdist") == {"path": "."}

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
    output = args.output
    project_files = read_files(args.project_file, args.lock_file)
    project_dict = project_files.project_file
    lock_dict = project_files.lock_file
    validate_lockfile_version(lock_dict)
    packages_list = lock_dict.get("distribution", [])

    lock_set = translate(
        project_dict,
        packages_list,
        default_group=args.default_group,
        optional_groups=args.optional_group,
        all_optional_groups=args.all_optional_groups,
        development_groups=args.development_group,
        all_development_groups=args.all_development_groups,
    )

    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main(parse_flags())
