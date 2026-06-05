import argparse
import configparser
import json
import sys
import tarfile
import tomllib
import zipfile
from pathlib import Path

PEP517_DEFAULT_BACKEND = "setuptools.build_meta:__legacy__"
PEP517_DEFAULT_REQUIRES = ["setuptools>=40.8.0", "wheel"]


def _get_archive_file_content(archive_path: Path, target_filename: str) -> str:
    """Reads a specific file from a tar.gz or zip archive without extracting it to disk."""
    if archive_path.name.endswith(".zip") or archive_path.name.endswith(".whl"):
        with zipfile.ZipFile(archive_path) as z:
            for name in z.namelist():
                if name.endswith(f"/{target_filename}") or name == target_filename:
                    return z.read(name).decode("utf-8")
    elif archive_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
        with tarfile.open(archive_path) as t:
            for member in t.getmembers():
                if member.isfile() and (member.name.endswith(f"/{target_filename}") or member.name == target_filename):
                    f = t.extractfile(member)
                    if f:
                        return f.read().decode("utf-8")
    return ""


def inspect_sdist(sdist_path: Path) -> dict:
    content = _get_archive_file_content(sdist_path, "pyproject.toml")
    if content:
        pyproject = tomllib.loads(content)
    else:
        pyproject = {}

    build_system = pyproject.get("build-system", {})
    return {
        "build_backend": build_system.get("build-backend", PEP517_DEFAULT_BACKEND),
        "build_requires": build_system.get("requires", PEP517_DEFAULT_REQUIRES),
    }


def inspect_wheel(wheel_path: Path) -> dict:
    content = _get_archive_file_content(wheel_path, "entry_points.txt")
    scripts = []
    if content:
        parser = configparser.ConfigParser()
        parser.read_string(content)
        if "console_scripts" in parser:
            scripts = list(parser["console_scripts"].keys())

    return {
        "console_scripts": scripts,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdist", type=Path)
    parser.add_argument("--wheel", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.sdist:
        data = inspect_sdist(args.sdist)
    elif args.wheel:
        data = inspect_wheel(args.wheel)
    else:
        print("Must specify either --sdist or --wheel", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    main()
