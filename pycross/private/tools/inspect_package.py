import argparse
import configparser
import json
import sys
import tarfile
import tomllib
import zipfile
from pathlib import Path
from pathlib import PurePosixPath

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
    # Skip legacy setuptools "-nspkg.pth" files. These are pkg_resources-style
    # namespace package declarations (e.g., google_cloud_aiplatform-1.156.0-py3.12-nspkg.pth)
    # that call pkg_resources.declare_namespace() at startup via site.py.
    # They are unnecessary with PEP 420 native namespace packages (Python 3.3+)
    # and cause AttributeError on Python 3.13.
    if filename.endswith("-nspkg.pth"):
        return None

    path = Path(filename)
    suffixes = path.suffixes
    if not suffixes:
        return None

    if suffixes[-1] in (".py", ".pth"):
        return filename[: -len(suffixes[-1])]

    if ".so" in suffixes:
        idx = suffixes.index(".so")
        # Verify all suffixes after .so are numeric (dashes are not allowed, only dots followed by digits)
        all_numeric = True
        for s in suffixes[idx + 1 :]:
            if not s[1:].isdigit():
                all_numeric = False
                break
        if all_numeric:
            ext = "".join(suffixes[idx:])
            return filename[: -len(ext)]

    return None


def _get_archive_file_content(archive_path: Path, target_filename: str, source_dir: str = "") -> str:
    """Reads a specific file from a tar.gz or zip archive without extracting it to disk.

    Args:
        archive_path: Path to the archive.
        target_filename: The filename to search for (e.g., "pyproject.toml").
        source_dir: Optional subdirectory within the archive to scope the search.
            When set, only matches files within that subdirectory (relative to
            the archive root dir). This handles git/URL packages with
            #subdirectory= fragments.
    """
    # Build the expected suffix path. For source_dir="packages/mylib" and
    # target_filename="pyproject.toml", we match "<root>/packages/mylib/pyproject.toml".
    if source_dir:
        target_suffix = PurePosixPath(source_dir.strip("/")) / target_filename
    else:
        target_suffix = PurePosixPath(target_filename)

    def _matches(name: str) -> bool:
        p = PurePosixPath(name)
        # With source_dir: match <root>/<source_dir>/<target>
        # Without: match <root>/<target> or bare <target>
        if source_dir:
            return len(p.parts) >= 2 and p.is_relative_to(PurePosixPath(p.parts[0]) / target_suffix)
        return p == target_suffix or (len(p.parts) >= 2 and PurePosixPath(*p.parts[1:]) == target_suffix)

    if archive_path.name.endswith(".zip") or archive_path.name.endswith(".whl"):
        with zipfile.ZipFile(archive_path) as z:
            for name in z.namelist():
                if _matches(name):
                    return z.read(name).decode("utf-8")
    elif archive_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
        with tarfile.open(archive_path) as t:
            for member in t.getmembers():
                if member.isfile() and _matches(member.name):
                    f = t.extractfile(member)
                    if f:
                        return f.read().decode("utf-8")
    return ""


def _resolve_top_level_paths(all_files: set[str], top_level_dirs: set[str]) -> set[str]:
    """Resolve top-level directories to their concrete importable paths.

    For regular packages (directories with __init__.py), returns the directory
    name as-is. For implicit namespace packages (PEP 420 — directories without
    __init__.py), descends to find the shallowest concrete sub-packages or
    standalone module files (preserving their extensions).

    This is critical for venv symlink support: if two distributions share a
    namespace (e.g. google-cloud-storage and google-cloud-bigquery both install
    under google/), we must symlink at the concrete package level
    (google/cloud/storage, google/cloud/bigquery) rather than the namespace
    root (google/) to avoid one distribution shadowing the other.

    Args:
        all_files: Set of all file paths in the archive (forward-slash separated).
        top_level_dirs: Set of top-level directory names to classify.

    Returns:
        Set of concrete paths — either top-level names for regular packages, or
        deeper paths for namespace packages (using forward slashes). Standalone
        module files retain their extensions (e.g. 'ns/helper.py').
    """
    init_files = {f for f in all_files if f.endswith("/__init__.py")}
    code_files = {f for f in all_files if _extract_module_name(f) is not None}

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

            for f in code_files:
                if f.startswith(prefix) and not f.endswith("/__init__.py"):
                    if _extract_module_name(f):
                        candidates.append(f)

            # Sort by depth (shallowest first) so we can skip sub-packages/files
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


def _read_top_level_txt(sdist_path: Path) -> list[str] | None:
    """Try to read top_level.txt from the egg-info directory inside an sdist.

    This is the authoritative source for importable top-level module names,
    generated by setuptools from the package's setup.py/setup.cfg metadata.
    It correctly handles C-only extensions (e.g. netifaces) that have no .py
    files at all.

    Returns a list of top-level names if found, or None if not present.
    """
    names: list[str] = []

    if sdist_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
        with tarfile.open(sdist_path) as t:
            for member in t.getmembers():
                if member.isfile() and member.name.endswith(".egg-info/top_level.txt"):
                    f = t.extractfile(member)
                    if f:
                        content = f.read().decode("utf-8")
                        names = [line.strip() for line in content.splitlines() if line.strip()]
                        break
    elif sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path) as z:
            for name in z.namelist():
                if name.endswith(".egg-info/top_level.txt"):
                    content = z.read(name).decode("utf-8")
                    names = [line.strip() for line in content.splitlines() if line.strip()]
                    break

    return names if names else None


def _find_site_paths_sdist(sdist_path: Path, source_dir: str = "") -> list[str]:
    """Find top-level Python packages in an sdist archive.

    First checks for an egg-info/top_level.txt, which is the most reliable
    source — it's generated by setuptools and correctly declares C-only
    extensions like netifaces.

    Falls back to heuristic scanning: looks for directories containing
    __init__.py at depth 2 (root/pkg/__init__.py) or depth 3 for src-layout
    (root/src/pkg/__init__.py).

    Handles namespace packages (PEP 420) by descending to find the shallowest
    concrete sub-packages when a top-level directory lacks __init__.py.

    Args:
        sdist_path: Path to the sdist archive.
        source_dir: Optional subdirectory within the archive root that contains
            the actual package. When set, only files under this subdirectory are
            considered. This handles git/URL packages with #subdirectory= fragments.
    """
    # Prefer the authoritative top_level.txt if present.
    top_level_names = _read_top_level_txt(sdist_path) if not source_dir else None
    if top_level_names is not None:
        return sorted(top_level_names)

    source_dir_path = PurePosixPath(source_dir.strip("/")) if source_dir else None

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
        p = PurePosixPath(name)

        # Every archive entry starts with an archive root dir (e.g., "pkg-1.0").
        if len(p.parts) < 2:
            continue

        # Compute the effective root: <archive_root> / <source_dir>
        effective_root = PurePosixPath(p.parts[0]) / source_dir_path if source_dir_path else PurePosixPath(p.parts[0])

        # Filter: only process entries under the effective root.
        if not p.is_relative_to(effective_root):
            continue

        # Get the path relative to the effective root.
        try:
            rel = p.relative_to(effective_root)
        except ValueError:
            continue

        if not rel.parts:
            continue

        if is_file:
            # Collect all relative file paths for namespace package resolution.
            all_files.add(str(rel))

            if len(rel.parts) == 1:
                root_files.add(rel.parts[0])
            elif len(rel.parts) == 2 and rel.parts[0] == "src":
                root_files.add(rel.parts[1])
        elif is_dir:
            if len(rel.parts) == 1 and rel.parts[0] not in _EXCLUDED_DIRS and not rel.parts[0].endswith(".egg-info"):
                top_level_dirs.add(rel.parts[0])
            elif len(rel.parts) == 2 and rel.parts[0] == "src":
                src_layout = True
                top_level_dirs.add(rel.parts[1])

    # For src-layout, adjust file paths to be relative to src/
    if src_layout:
        adjusted_files = set()
        for f in all_files:
            if f.startswith("src/"):
                adjusted_files.add(f[4:])  # strip "src/"
            else:
                adjusted_files.add(f)
        all_files = adjusted_files

    pkgs = _resolve_top_level_paths(all_files, top_level_dirs)
    for f in root_files:
        name = _extract_module_name(f)
        if (
            name
            and name not in _EXCLUDED_DIRS
            and name not in _EXCLUDED_ROOT_MODULES
            and not name.endswith(".egg-info")
        ):
            pkgs.add(f)

    return sorted(pkgs)


def _find_wheel_paths(wheel_path: Path) -> tuple[list[str], list[str], list[str], list[str]]:
    all_files: set[str] = set()
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()

    bin_paths = set()
    data_paths = set()
    include_paths = set()

    with zipfile.ZipFile(wheel_path) as z:
        for name in z.namelist():
            parts = name.split("/")
            if parts[0].endswith(".dist-info"):
                continue
            if parts[0].endswith(".data") and len(parts) > 2:
                scheme = parts[1]
                top_level_name = parts[2]
                if scheme == "scripts":
                    bin_paths.add(top_level_name)
                elif scheme == "data":
                    data_paths.add(top_level_name)
                elif scheme == "headers":
                    include_paths.add(top_level_name)
                elif scheme in ("purelib", "platlib"):
                    adjusted_name = "/".join(parts[2:])
                    all_files.add(adjusted_name)
                    if len(parts) >= 4:
                        top_level_dirs.add(parts[2])
                    elif len(parts) == 3 and parts[2] and not name.endswith("/"):
                        root_files.add(parts[2])
                continue

            if not parts[0].endswith(".data"):
                all_files.add(name)
                if len(parts) >= 2:
                    top_level_dirs.add(parts[0])
                elif len(parts) == 1 and parts[0] and not name.endswith("/"):
                    root_files.add(parts[0])

    pkgs = _resolve_top_level_paths(all_files, top_level_dirs)

    for f in root_files:
        name = _extract_module_name(f)
        if name and name not in _EXCLUDED_ROOT_MODULES:
            pkgs.add(f)

    site_paths = sorted(pkgs)

    content = _get_archive_file_content(wheel_path, "entry_points.txt")
    if content:
        parser = configparser.ConfigParser()
        parser.read_string(content)
        if "console_scripts" in parser:
            for script in parser["console_scripts"].keys():
                bin_paths.add(script)

    return site_paths, sorted(bin_paths), sorted(data_paths), sorted(include_paths)


def inspect_sdist(sdist_path: Path, source_dir: str = "") -> dict:
    content = _get_archive_file_content(sdist_path, "pyproject.toml", source_dir=source_dir)
    if content:
        pyproject = tomllib.loads(content)
    else:
        pyproject = {}

    build_system = pyproject.get("build-system", {})
    return {
        "build_backend": build_system.get("build-backend", PEP517_DEFAULT_BACKEND),
        "build_requires": build_system.get("requires", PEP517_DEFAULT_REQUIRES),
        "site_paths": _find_site_paths_sdist(sdist_path, source_dir=source_dir),
        "bin_paths": [],
        "data_paths": [],
        "include_paths": [],
    }


def inspect_wheel(wheel_path: Path) -> dict:
    site_paths, bin_paths, data_paths, include_paths = _find_wheel_paths(wheel_path)

    return {
        "site_paths": site_paths,
        "bin_paths": bin_paths,
        "data_paths": data_paths,
        "include_paths": include_paths,
    }


def validate_requirements(requires: list[str], pin_versions: dict[str, str | dict], pkg_name: str) -> list[str]:
    """Validate build-system.requires against pinned versions from the thin repo.

    Args:
        requires: List of PEP 508 requirement strings from build-system.requires.
        pin_versions: Dict from pin_versions.json. Simple pins: name -> version string.
            Variant pins: name -> {variant -> version}.
        pkg_name: Name of the package being inspected (for warning messages).

    Returns:
        List of warning strings.
    """
    warnings = []
    try:
        from packaging.requirements import Requirement
        from packaging.utils import canonicalize_name
    except ImportError:
        # Skip validation if packaging is not available in the host python
        return warnings

    # Normalize pin names for lookup
    normalized_pins = {canonicalize_name(k): v for k, v in pin_versions.items()}

    for req_str in requires:
        try:
            req = Requirement(req_str)
        except Exception:
            continue

        req_name = canonicalize_name(req.name)
        if req_name == "oldest-supported-numpy":
            req_name = "numpy"

        if req_name in normalized_pins:
            version_or_dict = normalized_pins[req_name]
            if isinstance(version_or_dict, str):
                # Simple pin: validate the single version
                if not req.specifier.contains(version_or_dict, prereleases=True):
                    warnings.append(
                        f"WARNING: The build tools repo pins '{req_name}=={version_or_dict}', "
                        f"but '{pkg_name}' requires '{req_str}' in pyproject.toml."
                    )
            else:
                # Variant pin: check if ANY variant satisfies
                satisfying = [v for v in version_or_dict.values() if req.specifier.contains(v, prereleases=True)]
                if not satisfying:
                    versions_str = ", ".join(f"{k}={v}" for k, v in sorted(version_or_dict.items()))
                    warnings.append(
                        f"WARNING: No variant of '{req_name}' satisfies '{req_str}' (available: {versions_str})."
                    )

    return warnings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdist", type=Path)
    parser.add_argument("--wheel", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pin-versions", type=Path, help="Path to pin_versions.json from the build tools thin repo.")
    # Keep --lock-json for backward compatibility
    parser.add_argument("--lock-json", type=Path, help="(Deprecated) Path to lock.json. Use --pin-versions instead.")
    parser.add_argument(
        "--source-dir", type=str, default="", help="Subdirectory within the sdist archive containing the package."
    )
    args = parser.parse_args()

    if args.sdist:
        data = inspect_sdist(args.sdist, source_dir=args.source_dir)

        pin_versions = {}
        if args.pin_versions:
            with open(args.pin_versions, "r") as f:
                pin_versions = json.load(f)
        elif args.lock_json:
            # Backward compat: derive pin_versions from lock JSON
            with open(args.lock_json, "r") as f:
                lock_data = json.load(f)
            for key in lock_data.get("packages", {}):
                parts = key.split("@", 1)
                if len(parts) == 2:
                    pin_versions[parts[0]] = parts[1]

        if pin_versions:
            data["warnings"] = validate_requirements(data["build_requires"], pin_versions, args.sdist.name)
    elif args.wheel:
        data = inspect_wheel(args.wheel)
    else:
        print("Must specify either --sdist or --wheel", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    main()
