import argparse
import ast
import configparser
import json
import sys
import tarfile
import tempfile
import tomllib
import zipfile
from pathlib import Path
from pathlib import PurePosixPath
from typing import Callable
from typing import Optional

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

# Top-level namespace packages that ship an `__init__.py` that doesn't declare the namespace.
# Mirrors rules_python's _WELL_KNOWN_NAMESPACE_PACKAGES (python/private/venv_runfiles.bzl).
_WELL_KNOWN_NAMESPACE_PACKAGES = frozenset({"nvidia"})

# Reads an archive-relative file path (as in all_files), returning None if unavailable.
FileReader = Callable[[str], Optional[str]]


_NAMESPACE_MODULES = frozenset({"pkgutil", "pkg_resources"})
_NAMESPACE_FUNCTIONS = frozenset({"extend_path", "declare_namespace"})


def _is_name(node: ast.AST, name: str) -> bool:
    return isinstance(node, ast.Name) and node.id == name


def _is_namespace_call(node: ast.AST, function: str, args: tuple[str, ...]) -> bool:
    """Whether node is `<anything>.function(*args)` or `function(*args)` with the given Name args."""
    if not isinstance(node, ast.Call) or node.keywords or len(node.args) != len(args):
        return False
    func = node.func
    if not (_is_name(func, function) or (isinstance(func, ast.Attribute) and func.attr == function)):
        return False
    return all(_is_name(arg, name) for arg, name in zip(node.args, args))


def _is_pkgutil_namespace_init(content: str) -> bool:
    """Whether an __init__.py is a pure pkgutil- or pkg_resources-style namespace package stub.

    Only stubs qualify: every statement (also inside try/except/else/finally) must be a docstring,
    `pass`, an import of pkgutil/pkg_resources (or of extend_path/declare_namespace from them),
    `__path__ = <...>extend_path(__path__, __name__)`, or `<...>declare_namespace(__name__)`, with
    at least one declaration. Anything else (real code, `__version__`, a module that merely defines
    or mentions these functions, like setuptools' pkg_resources) is a regular package.
    """
    try:
        tree = ast.parse(content)
    except (SyntaxError, ValueError):
        return False

    declarations = 0

    def is_stub(statements: list[ast.stmt]) -> bool:
        nonlocal declarations
        for node in statements:
            if isinstance(node, ast.Pass):
                continue
            if (
                isinstance(node, ast.Expr)
                and isinstance(node.value, ast.Constant)
                and isinstance(node.value.value, str)
            ):
                continue  # docstring
            if isinstance(node, ast.Import):
                if not all(alias.name in _NAMESPACE_MODULES and alias.asname is None for alias in node.names):
                    return False
                continue
            if isinstance(node, ast.ImportFrom):
                if node.module not in _NAMESPACE_MODULES or not all(
                    alias.name in _NAMESPACE_FUNCTIONS and alias.asname is None for alias in node.names
                ):
                    return False
                continue
            if (
                isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and _is_name(node.targets[0], "__path__")
                and _is_namespace_call(node.value, "extend_path", ("__path__", "__name__"))
            ):
                declarations += 1
                continue
            if isinstance(node, ast.Expr) and _is_namespace_call(node.value, "declare_namespace", ("__name__",)):
                declarations += 1
                continue
            if isinstance(node, ast.Try):
                if not all(
                    is_stub(body) for body in [node.body, node.orelse, node.finalbody] + [h.body for h in node.handlers]
                ):
                    return False
                continue
            return False
        return True

    return is_stub(tree.body) and declarations > 0


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


def _resolve_top_level_paths(
    all_files: set[str],
    top_level_dirs: set[str],
    read_file: Optional[FileReader] = None,
) -> set[str]:
    """Resolve top-level directories to their concrete importable paths.

    For regular packages (directories with __init__.py), returns the directory
    name as-is. For namespace packages, descends to find the shallowest concrete
    sub-packages or standalone module files (preserving their extensions).
    Namespace packages are:

    * implicit namespace packages (PEP 420 — directories without __init__.py);
    * pkgutil- or pkg_resources-style namespace packages, whose __init__.py calls
      pkgutil.extend_path or pkg_resources.declare_namespace (needs `read_file`);
    * well-known top-level namespaces that ship an empty __init__.py (nvidia).

    This is critical for venv symlink support: if two distributions share a
    namespace (e.g. google-cloud-storage and google-cloud-bigquery both install
    under google/), we must symlink at the concrete package level
    (google/cloud/storage, google/cloud/bigquery) rather than the namespace
    root (google/) to avoid one distribution shadowing the other.

    Args:
        all_files: Set of all file paths in the archive (forward-slash separated).
        top_level_dirs: Set of top-level directory names to classify.
        read_file: Optional function returning the content of a path in all_files,
            used to detect pkgutil-style namespace packages.

    Returns:
        Set of concrete paths — either top-level names for regular packages, or
        deeper paths for namespace packages (using forward slashes). Standalone
        module files retain their extensions (e.g. 'ns/helper.py').
    """
    init_files = {f for f in all_files if f.endswith("/__init__.py")}

    def is_namespace(dir_path: str) -> bool:
        init = f"{dir_path}/__init__.py"
        if init not in init_files:
            return True
        if dir_path in _WELL_KNOWN_NAMESPACE_PACKAGES:
            return True
        content = read_file(init) if read_file else None
        return bool(content) and _is_pkgutil_namespace_init(content)

    def resolve(dir_path: str) -> list[str]:
        if not is_namespace(dir_path):
            # Regular package — can be linked directly.
            return [dir_path]

        # Namespace package — link its modules and descend into its subdirectories. The namespace's
        # own __init__.py (if any) is shared by every distribution, so it isn't linked.
        prefix = dir_path + "/"
        kept = []
        subdirs = set()
        for f in all_files:
            if not f.startswith(prefix):
                continue
            rest = f[len(prefix) :]
            if "/" in rest:
                subdirs.add(prefix + rest.split("/", 1)[0])
            elif rest != "__init__.py" and _extract_module_name(rest):
                kept.append(f)
        for subdir in sorted(subdirs):
            kept.extend(resolve(subdir))
        # A namespace dir with no concrete sub-packages or modules resolves to nothing.
        return kept

    result = set()
    for dir_name in top_level_dirs:
        result.update(resolve(dir_name))
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


def _find_site_paths_from_items(
    items: list[tuple[str, bool, bool]],
    source_dir: str = "",
    read_member: Optional[FileReader] = None,
    top_level_names: Optional[list[str]] = None,
) -> list[str]:
    """Find top-level importable paths from an sdist's (name, is_dir, is_file) entries.

    Args:
        items: Archive entries.
        source_dir: Optional subdirectory within the archive root containing the package.
        read_member: Optional function returning the content of an archive entry (by name), used
            to detect pkgutil-style namespace packages.
        top_level_names: Top-level names declared by the sdist's top_level.txt. When set, these are
            returned, except that namespace packages among them resolve to their concrete paths.
    """
    source_dir_path = PurePosixPath(source_dir.strip("/")) if source_dir else None

    # Collect all file paths and candidate top-level directories.
    all_files: set[str] = set()
    members: dict[str, str] = {}  # relative path -> archive entry name
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()
    src_layout = False

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
            members[str(rel)] = name

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
        adjusted_members = {}
        for f in all_files:
            adjusted = f[4:] if f.startswith("src/") else f  # strip "src/"
            adjusted_files.add(adjusted)
            adjusted_members[adjusted] = members[f]
        all_files = adjusted_files
        members = adjusted_members

    def read_file(path: str) -> Optional[str]:
        return read_member(members[path]) if read_member and path in members else None

    if top_level_names is not None:
        # Keep declared names (they may be C-only extensions with no files to scan), but resolve
        # namespace packages among them so distributions sharing a namespace don't collide.
        declared = set()
        for name in top_level_names:
            if any(f.startswith(name + "/") for f in all_files):
                declared.update(_resolve_top_level_paths(all_files, {name}, read_file))
            else:
                declared.add(name)
        return sorted(declared)

    pkgs = _resolve_top_level_paths(all_files, top_level_dirs, read_file)
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

    # List of (name, is_dir, is_file)
    items = []
    if sdist_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
        with tarfile.open(sdist_path) as t:
            for member in t.getmembers():
                items.append((member.name, member.isdir(), member.isfile()))

            def read_tar_member(name: str) -> Optional[str]:
                f = t.extractfile(name)
                return f.read().decode("utf-8", "replace") if f else None

            return _find_site_paths_from_items(
                items, source_dir=source_dir, read_member=read_tar_member, top_level_names=top_level_names
            )
    elif sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path) as z:
            for name in z.namelist():
                is_dir = name.endswith("/")
                items.append((name, is_dir, not is_dir))

            def read_zip_member(name: str) -> Optional[str]:
                return z.read(name).decode("utf-8", "replace")

            return _find_site_paths_from_items(
                items, source_dir=source_dir, read_member=read_zip_member, top_level_names=top_level_names
            )

    return sorted(top_level_names) if top_level_names is not None else []


def _inspect_patched_sdist(
    sdist_path: Path,
    source_dir: str,
    pre_build_patches: list[Path],
) -> tuple[str, list[str]]:
    """Extract an sdist, apply pre_build_patches, and return (pyproject_content, site_paths)."""
    import patch_ng

    resolved_patches = [(patch_path, Path(patch_path).resolve()) for patch_path in pre_build_patches]
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        if sdist_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
            with tarfile.open(sdist_path, "r") as f:
                if hasattr(tarfile, "data_filter"):
                    f.extraction_filter = tarfile.data_filter
                f.extractall(tmp_path)
        elif sdist_path.name.endswith(".zip"):
            with zipfile.ZipFile(sdist_path, "r") as f:
                f.extractall(tmp_path)
        else:
            raise ValueError(f"Unsupported sdist format: {sdist_path}")

        extracted_dirs = list(tmp_path.glob("*"))
        if len(extracted_dirs) != 1 or not extracted_dirs[0].is_dir():
            raise ValueError(f"Expected exactly one directory in sdist archive, got: {extracted_dirs}")

        sdist_root_dir = extracted_dirs[0]
        sdist_dir = sdist_root_dir / source_dir.strip("/") if source_dir else sdist_root_dir

        for orig_patch_path, abs_patch_path in resolved_patches:
            patch_file = patch_ng.fromfile(str(abs_patch_path))
            if not patch_file:
                raise SystemExit(f"error: failed to parse patch file: {orig_patch_path}")
            if not patch_file.apply(root=str(sdist_dir)):
                raise SystemExit(f"error: failed to apply patch file: {orig_patch_path}")

        pyproject_path = sdist_dir / "pyproject.toml"
        content = pyproject_path.read_text(encoding="utf-8") if pyproject_path.is_file() else ""

        top_level_names: list[str] | None = None
        if not source_dir:
            for p in sorted(sdist_root_dir.rglob("*.egg-info/top_level.txt")):
                if p.is_file():
                    tl_content = p.read_text(encoding="utf-8")
                    names = [line.strip() for line in tl_content.splitlines() if line.strip()]
                    if names:
                        top_level_names = names
                    break

        def read_extracted(name: str) -> Optional[str]:
            return (tmp_path / name).read_text(encoding="utf-8", errors="replace")

        items = [(p.relative_to(tmp_path).as_posix(), p.is_dir(), p.is_file()) for p in sdist_root_dir.rglob("*")]
        site_paths = _find_site_paths_from_items(
            items, source_dir=source_dir, read_member=read_extracted, top_level_names=top_level_names
        )

        return content, site_paths


def _find_wheel_paths(wheel_path: Path) -> tuple[list[str], list[str], list[str], list[str]]:
    all_files: set[str] = set()
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()

    bin_paths = set()
    data_paths = set()
    include_paths = set()

    # Maps site-packages-relative paths in all_files to archive member names.
    members: dict[str, str] = {}

    with zipfile.ZipFile(wheel_path) as z:
        for name in z.namelist():
            parts = name.split("/")
            if parts[0].endswith(".dist-info"):
                continue
            if parts[0].endswith(".data") and len(parts) > 2:
                scheme = parts[1]
                top_level_name = parts[2]
                if not top_level_name:
                    continue
                if scheme == "scripts":
                    bin_paths.add(top_level_name)
                elif scheme == "data":
                    data_paths.add(top_level_name)
                elif scheme == "headers":
                    include_paths.add(top_level_name)
                elif scheme in ("purelib", "platlib"):
                    if not name.endswith("/"):
                        adjusted_name = "/".join(parts[2:])
                        all_files.add(adjusted_name)
                        members[adjusted_name] = name
                    if len(parts) >= 4:
                        top_level_dirs.add(parts[2])
                    elif len(parts) == 3 and parts[2] and not name.endswith("/"):
                        root_files.add(parts[2])
                continue

            if parts[0] and not parts[0].endswith(".data"):
                if not name.endswith("/"):
                    all_files.add(name)
                    members[name] = name
                if len(parts) >= 2:
                    top_level_dirs.add(parts[0])
                elif len(parts) == 1 and parts[0] and not name.endswith("/"):
                    root_files.add(parts[0])

        def read_file(path: str) -> Optional[str]:
            return z.read(members[path]).decode("utf-8", "replace") if path in members else None

        pkgs = _resolve_top_level_paths(all_files, top_level_dirs, read_file)

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


def inspect_sdist(
    sdist_path: Path,
    source_dir: str = "",
    pre_build_patches: list[Path] | None = None,
) -> dict:
    if pre_build_patches:
        content, site_paths = _inspect_patched_sdist(sdist_path, source_dir, pre_build_patches)
    else:
        content = _get_archive_file_content(sdist_path, "pyproject.toml", source_dir=source_dir)
        site_paths = _find_site_paths_sdist(sdist_path, source_dir=source_dir)

    warnings = []
    if content:
        try:
            pyproject = tomllib.loads(content)
        except tomllib.TOMLDecodeError as exc:
            warnings.append(
                f"WARNING: Failed to parse pyproject.toml in '{sdist_path.name}' ({exc}); "
                f"falling back to default build-system settings."
            )
            pyproject = {}
    else:
        pyproject = {}

    build_system = pyproject.get("build-system", {})
    result = {
        "build_backend": build_system.get("build-backend", PEP517_DEFAULT_BACKEND),
        "build_requires": build_system.get("requires", PEP517_DEFAULT_REQUIRES),
        "site_paths": site_paths,
        "bin_paths": [],
        "data_paths": [],
        "include_paths": [],
    }
    if warnings:
        result["warnings"] = warnings
    return result


def inspect_wheel(wheel_path: Path) -> dict:
    site_paths, bin_paths, data_paths, include_paths = _find_wheel_paths(wheel_path)

    return {
        "site_paths": site_paths,
        "bin_paths": bin_paths,
        "data_paths": data_paths,
        "include_paths": include_paths,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdist", type=Path)
    parser.add_argument("--wheel", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--source-dir", type=str, default="", help="Subdirectory within the sdist archive containing the package."
    )
    parser.add_argument(
        "--pre-build-patch",
        dest="pre_build_patches",
        action="append",
        type=Path,
        default=[],
        help="Patch file to apply to the extracted sdist before inspection (may be specified multiple times).",
    )
    args = parser.parse_args()

    if args.sdist:
        data = inspect_sdist(
            args.sdist,
            source_dir=args.source_dir,
            pre_build_patches=args.pre_build_patches,
        )
    elif args.wheel:
        data = inspect_wheel(args.wheel)
    else:
        print("Must specify either --sdist or --wheel", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    main()
