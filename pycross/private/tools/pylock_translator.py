import tomllib
from pathlib import Path
from typing import Any

from packaging.specifiers import SpecifierSet
from packaging.version import Version
from pycross.private.tools.args import FlagFileArgumentParser
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
        help="The path to the project file. Ignored by pylock_translator.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output json file.",
    )

    return parser.parse_args()


def translate(lock_file: Path) -> RawLockSet:
    with open(lock_file, "rb") as f:
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
    pins = {}

    for pkg in packages_list:
        name = package_canonical_name(pkg["name"])
        version = pkg["version"]

        dependencies = []
        for dep in pkg.get("dependencies", []):
            dep_name = package_canonical_name(dep["name"])
            dep_version = versions.get(dep_name)
            if not dep_version:
                continue  # Skip if missing from lock file

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
            name=name,
            version=Version(version),
            python_versions=package_requires_python,
            dependencies=sorted(dependencies, key=lambda d: d.name),
            files=sorted(files, key=lambda f: f.name),
        )
        lock_packages[raw_package.key] = raw_package
        pins[name] = raw_package.key

    return RawLockSet(
        python_versions=requires_python,
        packages=lock_packages,
        pins=pins,
    )


def main(args: Any) -> None:
    output = args.output
    lock_set = translate(args.lock_file)
    with open(output, "w") as f:
        f.write(lock_set.to_json(indent=2))


if __name__ == "__main__":
    main(parse_flags())
