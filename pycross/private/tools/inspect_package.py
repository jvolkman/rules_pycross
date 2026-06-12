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

_EXCLUDED_DIRS = frozenset(
    {
        "bin",
        "benchmarks",
        "docs",
        "examples",
        "scripts",
        "src",
        "test",
        "tests",
        "testing",
        "tools",
    }
)

_EXCLUDED_ROOT_MODULES = frozenset({"setup", "conftest"})


def _extract_module_name(filename: str) -> str | None:
    suffixes = Path(filename).suffixes
    if suffixes and suffixes[-1] in (".py", ".so"):
        ext = "".join(suffixes)
        return filename[: -len(ext)]
    return None


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


def _resolve_namespace_packages(all_files: set[str], top_level_dirs: set[str]) -> set[str]:
    """Resolve namespace packages to their concrete sub-packages.

    For regular packages (directories with __init__.py), returns the directory
    name as-is. For implicit namespace packages (PEP 420 — directories without
    __init__.py), descends to find the shallowest concrete sub-packages.

    This is critical for venv symlink support: if two distributions share a
    namespace (e.g. google-cloud-storage and google-cloud-bigquery both install
    under google/), we must symlink at the concrete package level
    (google/cloud/storage, google/cloud/bigquery) rather than the namespace
    root (google/) to avoid one distribution shadowing the other.

    Args:
        all_files: Set of all file paths in the archive (forward-slash separated).
        top_level_dirs: Set of top-level directory names to classify.

    Returns:
        Set of package paths — either top-level names for regular packages, or
        deeper paths for namespace packages (using forward slashes).
    """
    init_files = {f for f in all_files if f.endswith("/__init__.py")}

    result = set()
    for dir_name in top_level_dirs:
        if f"{dir_name}/__init__.py" in init_files:
            # Regular package — can be linked directly.
            result.add(dir_name)
        else:
            # Namespace package — find the shallowest concrete sub-packages.
            prefix = dir_name + "/"
            candidates = []
            for init in init_files:
                if init.startswith(prefix):
                    # e.g. "google/cloud/storage/__init__.py" -> "google/cloud/storage"
                    pkg_path = init.rsplit("/", 1)[0]
                    candidates.append(pkg_path)

            # Sort by depth (shallowest first) so we can skip sub-packages
            # of already-selected packages.
            candidates.sort(key=lambda p: p.count("/"))

            kept = []
            for candidate in candidates:
                # Skip if this is a sub-package of an already-kept package.
                if any(candidate.startswith(k + "/") for k in kept):
                    continue
                kept.append(candidate)

            if kept:
                result.update(kept)
            # else: namespace dir with no concrete sub-packages — skip.

    return result


def _find_top_level_packages_sdist(sdist_path: Path) -> list[str]:
    """Find top-level Python packages in an sdist archive.

    Looks for directories containing __init__.py at depth 2 (root/pkg/__init__.py)
    or depth 3 for src-layout (root/src/pkg/__init__.py).

    Handles namespace packages (PEP 420) by descending to find the shallowest
    concrete sub-packages when a top-level directory lacks __init__.py.
    """
    # Collect all file paths and candidate top-level directories.
    all_files: set[str] = set()
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()
    src_layout = False

    # List of (name, is_dir, is_file)
    items = []
    if sdist_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
        with tarfile.open(sdist_path) as t:
            for member in t.getmembers():
                items.append((member.name, member.isdir(), member.isfile()))
    elif sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path) as z:
            for name in z.namelist():
                is_dir = name.endswith("/")
                items.append((name, is_dir, not is_dir))

    for name, is_dir, is_file in items:
        name = name.rstrip("/")
        parts = name.split("/")
        if is_file:
            # Strip the root dir prefix (e.g. "pkg-1.0/") for normalization.
            if len(parts) >= 2:
                relative = "/".join(parts[1:])
                all_files.add(relative)
            if len(parts) == 2 and parts[1]:
                root_files.add(parts[1])
            elif len(parts) == 3 and parts[1] == "src" and parts[2]:
                root_files.add(parts[2])
        elif is_dir and len(parts) >= 2:
            if len(parts) == 2 and parts[1] and parts[1] not in _EXCLUDED_DIRS and not parts[1].endswith(".egg-info"):
                top_level_dirs.add(parts[1])
            elif len(parts) == 3 and parts[1] == "src" and parts[2]:
                src_layout = True
                top_level_dirs.add(parts[2])

    # For src-layout, adjust file paths to be relative to src/
    if src_layout:
        adjusted_files = set()
        for f in all_files:
            if f.startswith("src/"):
                adjusted_files.add(f[4:])  # strip "src/"
            else:
                adjusted_files.add(f)
        all_files = adjusted_files

    pkgs = _resolve_namespace_packages(all_files, top_level_dirs)
    for f in root_files:
        name = _extract_module_name(f)
        if (
            name
            and name not in _EXCLUDED_DIRS
            and name not in _EXCLUDED_ROOT_MODULES
            and not name.endswith(".egg-info")
        ):
            pkgs.add(name)

    return sorted(pkgs)


def _find_top_level_packages_wheel(wheel_path: Path) -> list[str]:
    """Find top-level Python packages in a wheel archive.

    Handles namespace packages (PEP 420) by descending to find the shallowest
    concrete sub-packages when a top-level directory lacks __init__.py.
    """
    all_files: set[str] = set()
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()

    with zipfile.ZipFile(wheel_path) as z:
        for name in z.namelist():
            parts = name.split("/")
            if parts[0].endswith((".dist-info", ".data")):
                continue
            all_files.add(name)
            if len(parts) >= 2:
                top_level_dirs.add(parts[0])
            elif len(parts) == 1 and parts[0] and not name.endswith("/"):
                root_files.add(parts[0])

    pkgs = _resolve_namespace_packages(all_files, top_level_dirs)

    for f in root_files:
        name = _extract_module_name(f)
        if name and name not in _EXCLUDED_ROOT_MODULES:
            pkgs.add(name)

    return sorted(pkgs)


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
        "top_level_packages": _find_top_level_packages_sdist(sdist_path),
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
        "top_level_packages": _find_top_level_packages_wheel(wheel_path),
    }


def validate_requirements(requires: list[str], package_versions: dict[str, str], pkg_name: str) -> list[str]:
    warnings = []
    try:
        from packaging.requirements import Requirement
        from packaging.utils import canonicalize_name
    except ImportError:
        # Skip validation if packaging is not available in the host python
        return warnings

    for req_str in requires:
        try:
            req = Requirement(req_str)
        except Exception:
            continue

        req_name = canonicalize_name(req.name)
        if req_name == "oldest-supported-numpy":
            req_name = "numpy"

        # Check if the lock file has a version for this package
        # Sometimes lock files use un-canonicalized names, so check lowercased
        normalized_versions = {canonicalize_name(k): v for k, v in package_versions.items()}

        if req_name in normalized_versions:
            provided_version = normalized_versions[req_name]
            if not req.specifier.contains(provided_version, prereleases=True):
                warnings.append(
                    f"WARNING: The lock file provides '{req_name}=={provided_version}', "
                    f"but '{pkg_name}' requires '{req_str}' in pyproject.toml."
                )

    return warnings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdist", type=Path)
    parser.add_argument("--wheel", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lock-json", type=Path)
    args = parser.parse_args()

    if args.sdist:
        data = inspect_sdist(args.sdist)
        if args.lock_json:
            with open(args.lock_json, "r") as f:
                lock_data = json.load(f)

            package_versions = {}
            for key in lock_data.get("packages", {}):
                parts = key.split("@", 1)
                if len(parts) == 2:
                    package_versions[parts[0]] = parts[1]

            data["warnings"] = validate_requirements(data["build_requires"], package_versions, args.sdist.name)
    elif args.wheel:
        data = inspect_wheel(args.wheel)
    else:
        print("Must specify either --sdist or --wheel", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    main()
