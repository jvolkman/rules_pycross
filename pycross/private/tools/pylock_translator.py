import sys
import tomllib
from pathlib import Path
from typing import Any
from typing import List

from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.version import Version
from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import DependencyName
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.lock_model import package_canonical_name


class LockfileIncompatibleException(Exception):
    pass


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Generate pycross dependency json file from pylock.toml.")

    parser.add_argument(
        "--lock-file",
        type=Path,
        required=True,
        help="The path to pylock.toml.",
    )

    parser.add_argument(
        "--project-file",
        type=Path,
        help="The path to the project file.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output json file.",
    )

    parser.add_argument(
        "--default",
        action="store_true",
        default=True,
        help="Whether to install dependencies from the default group.",
    )
    parser.add_argument(
        "--no-default",
        action="store_false",
        dest="default",
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
        help="Install all optional dependencies.",
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
        help="Install all development dependencies.",
    )

    return parser.parse_args()


def translate(args: Any) -> RawLockSet:
    with open(args.lock_file, "rb") as f:
        lock_dict = tomllib.load(f)

    lock_version = lock_dict.get("lock-version")
    if str(lock_version) != "1.0":
        raise LockfileIncompatibleException(f"Unsupported lock-version: {lock_version}")

    requires_python = SpecifierSet(lock_dict.get("requires-python", ""))

    packages_list = lock_dict.get("package", lock_dict.get("packages", []))

    # Create lookup map for versions. In PEP 751, each package is strictly pinned.
    versions = {}
    for pkg in packages_list:
        name = package_canonical_name(pkg["name"])
        version = pkg["version"]
        versions[name] = version

    lock_packages = {}

    for pkg in packages_list:
        name = package_canonical_name(pkg["name"])
        version = pkg["version"]

        dependencies = []
        for dep in pkg.get("dependencies", []):
            dep_name = DependencyName(dep["name"])
            dep_version = versions.get(dep_name.package)
            if not dep_version:
                print(
                    f"WARNING: dependency '{dep_name}' of '{name}' not found in lockfile, skipping",
                    file=sys.stderr,
                )
                continue

            dependencies.append(
                PackageDependency(name=dep_name, version=Version(dep_version), marker=str(dep.get("marker", "")))
            )

        files = []
        for wheel in pkg.get("wheels", pkg.get("wheel", [])):
            if not isinstance(wheel, dict):
                continue
            filename = wheel.get("name", wheel.get("file", ""))
            if not filename and "url" in wheel:
                filename = wheel["url"].split("/")[-1]
            url = wheel.get("url")
            urls = (url,) if url else ()
            hash_str = wheel.get("hash")
            if hash_str and hash_str.startswith("sha256:"):
                hash_val = hash_str[7:]
            else:
                hashes = wheel.get("hashes", {})
                hash_val = hashes.get("sha256", "")
            files.append(PackageFile(name=filename, sha256=hash_val, urls=urls))

        sdist_list = pkg.get("sdists", pkg.get("sdist", []))
        if isinstance(sdist_list, dict):
            sdist_list = [sdist_list]
        for sdist in sdist_list:
            if not isinstance(sdist, dict):
                continue
            filename = sdist.get("name", sdist.get("file", ""))
            if not filename and "url" in sdist:
                filename = sdist["url"].split("/")[-1]
            url = sdist.get("url")
            urls = (url,) if url else ()
            hash_str = sdist.get("hash")
            if hash_str and hash_str.startswith("sha256:"):
                hash_val = hash_str[7:]
            else:
                hashes = sdist.get("hashes", {})
                hash_val = hashes.get("sha256", "")
            files.append(PackageFile(name=filename, sha256=hash_val, urls=urls))

        package_requires_python = SpecifierSet(pkg.get("requires-python", ""))

        raw_package = RawPackage(
            name=DependencyName(name),
            version=Version(version),
            python_versions=package_requires_python,
            dependencies=sorted(dependencies, key=lambda d: d.name),
            files=sorted(files, key=lambda f: f.name),
        )
        lock_packages[raw_package.key] = raw_package

    # Dependency graph
    deps_by_name = {pkg.name: pkg for pkg in lock_packages.values()}

    pins = {}

    # If we have a project file and filters are applied, subset the graph.
    has_filter = (
        not args.default
        or args.optional_group
        or args.all_optional_groups
        or args.development_group
        or args.all_development_groups
    )
    if args.project_file and has_filter:
        with open(args.project_file, "rb") as f:
            project_dict = tomllib.load(f)

        root_reqs: List[Requirement] = []

        project_section = project_dict.get("project", {})
        if args.default:
            for dep_str in project_section.get("dependencies", []):
                root_reqs.append(Requirement(dep_str))

        optional_deps = project_section.get("optional-dependencies", {})
        if args.all_optional_groups:
            opt_groups = list(optional_deps.keys())
        else:
            opt_groups = args.optional_group

        for g in opt_groups:
            if g in optional_deps:
                for dep_str in optional_deps[g]:
                    root_reqs.append(Requirement(dep_str))
            else:
                print(f"WARNING: Optional group '{g}' not found in project file.", file=sys.stderr)

        dev_deps = project_dict.get("dependency-groups", {})
        if args.all_development_groups:
            dev_groups = list(dev_deps.keys())
        else:
            dev_groups = args.development_group

        for g in dev_groups:
            if g in dev_deps:
                for dep_str in dev_deps[g]:
                    if isinstance(dep_str, str):
                        root_reqs.append(Requirement(dep_str))
                    elif isinstance(dep_str, dict) and "include-group" in dep_str:
                        inc_group = dep_str["include-group"]
                        if inc_group in dev_deps:
                            for inc_dep in dev_deps[inc_group]:
                                if isinstance(inc_dep, str):
                                    root_reqs.append(Requirement(inc_dep))
            else:
                print(f"WARNING: Development group '{g}' not found in project file.", file=sys.stderr)

        root_package_names = set(package_canonical_name(req.name) for req in root_reqs)

        # Traverse graph starting from root_package_names
        visited_names = set()
        queue = list(root_package_names)

        while queue:
            curr = queue.pop(0)
            if curr in visited_names:
                continue
            visited_names.add(curr)

            if curr in deps_by_name:
                for dep in deps_by_name[curr].dependencies:
                    queue.append(dep.name)

        # Filter lock_packages
        filtered_packages = {}
        for pkg_key, pkg in lock_packages.items():
            if pkg.name in visited_names:
                filtered_packages[pkg_key] = pkg

        lock_packages = filtered_packages

        # Pins are just the root_package_names that are available
        for root_name in root_package_names:
            if root_name in deps_by_name:
                pins[root_name] = deps_by_name[root_name].key
    else:
        # Default behavior: include all
        for pkg in lock_packages.values():
            pins[pkg.name] = pkg.key

    return RawLockSet(
        python_versions=requires_python,
        packages=lock_packages,
        pins=pins,
    )


def main(args: Any) -> None:
    output = args.output
    lock_set = translate(args)
    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


if __name__ == "__main__":
    main(parse_flags())
