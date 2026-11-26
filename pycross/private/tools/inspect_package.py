import argparse
import ast
import configparser
import json
import os
import sys
import tarfile
import tempfile
import zipfile
from collections.abc import Iterable
from collections.abc import Iterator
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
# Unified sdist entry: (archive_path, is_dir, is_file, read_bytes).
SdistEntry = tuple[str, bool, bool, Callable[[], Optional[bytes]]]


def _load_tomllib():
    """Load tomllib (Python 3.11+) or pip's vendored tomli (Python 3.10)."""
    try:
        import tomllib
    except ImportError:
        from pip._vendor import tomli as tomllib  # type: ignore[no-redef]
    return tomllib


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

    if suffixes[-1] in (".py", ".pth", ".pyd"):
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


def _is_shared_library(filename: str) -> bool:
    """Whether a file is loaded by the dynamic linker (mirrors rules_python's _is_linker_loaded_library)."""
    return filename.endswith((".so", ".dylib", ".dll")) or ".so." in filename


def _rel_under_effective_root(
    name: str,
    source_dir_path: Optional[PurePosixPath],
) -> Optional[PurePosixPath]:
    """Return path relative to `<archive_root>[/<source_dir>]`, or None if outside."""
    p = PurePosixPath(name.rstrip("/"))
    if len(p.parts) < 2:
        return None
    effective_root = PurePosixPath(p.parts[0]) / source_dir_path if source_dir_path else PurePosixPath(p.parts[0])
    if not p.is_relative_to(effective_root):
        return None
    rel = p.relative_to(effective_root)
    return rel if rel.parts else None


def _is_top_level_txt_rel(rel: PurePosixPath) -> bool:
    """Whether a root-relative path is a top-level egg-info `top_level.txt` (at root or `src/`)."""
    parts = rel.parts
    if len(parts) == 2 and parts[0].endswith(".egg-info") and parts[1] == "top_level.txt":
        return True
    if len(parts) == 3 and parts[0] == "src" and parts[1].endswith(".egg-info") and parts[2] == "top_level.txt":
        return True
    return False


def _parse_entry_points(content: str) -> set[str]:
    """Extract console_scripts and gui_scripts names from an entry_points.txt string."""
    scripts: set[str] = set()
    parser = configparser.ConfigParser(delimiters=("=",), interpolation=None)
    parser.optionxform = str
    parser.read_string(content)
    for section in ("console_scripts", "gui_scripts"):
        if section in parser:
            scripts.update(parser[section].keys())
    return scripts


def _resolve_top_level_paths(
    all_files: set[str],
    top_level_dirs: set[str],
    read_file: Optional[FileReader] = None,
) -> set[str]:
    """Resolve top-level directories to their concrete importable paths.

    For regular packages (directories with __init__.py), returns the directory
    name as-is. For namespace packages, descends to find the shallowest concrete
    sub-packages and the files directly inside (preserving their extensions).
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

    Every file in a namespace directory is kept, not just modules: data files such as PyQt5-Qt5's
    PyQt5/Qt5/qml/** must exist in the venv too.

    Below a namespace directory, shared libraries are linked individually and the directories
    above them are never linked as a whole (like rules_python's get_venv_symlinks). The dynamic
    linker expands $ORIGIN to the directory of the path a library was opened by, but the kernel
    resolves `..` and the rest of an RPATH entry against the real directories. Through a directory
    symlink, an RPATH such as nvidia/cusparse/lib's `$ORIGIN/../../nvjitlink/lib` would resolve
    inside the cusparse wheel instead of the venv, where nvidia-nvjitlink-cu12 is linked. Top-level
    regular packages stay whole: their libraries' RPATHs normally stay inside the wheel (e.g.
    auditwheel's `$ORIGIN/../<pkg>.libs`), which resolves the same through a directory symlink.

    Args:
        all_files: Set of all file paths in the archive (forward-slash separated).
        top_level_dirs: Set of top-level directory names to classify.
        read_file: Optional function returning the content of a path in all_files,
            used to detect pkgutil-style namespace packages.

    Returns:
        Set of concrete paths: directories that can be linked as a whole, plus individual files
        (with their extensions, e.g. 'ns/helper.py') in namespace directories or next to shared
        libraries.
    """
    init_files = {f for f in all_files if f.endswith("/__init__.py")}

    # dir -> (file names, subdirectory names) directly inside it.
    children: dict[str, tuple[set[str], set[str]]] = {}
    # Directories that contain a shared library at any depth.
    library_dirs: set[str] = set()
    for f in all_files:
        parent, _, name = f.rpartition("/")
        if not parent:
            continue
        children.setdefault(parent, (set(), set()))[0].add(name)
        is_library = _is_shared_library(name)
        while parent:
            if is_library:
                library_dirs.add(parent)
            grandparent, _, dir_name = parent.rpartition("/")
            if grandparent:
                children.setdefault(grandparent, (set(), set()))[1].add(dir_name)
            parent = grandparent

    def is_namespace(dir_path: str) -> bool:
        init = f"{dir_path}/__init__.py"
        if init not in init_files:
            return True
        if dir_path in _WELL_KNOWN_NAMESPACE_PACKAGES:
            return True
        content = read_file(init) if read_file else None
        return bool(content) and _is_pkgutil_namespace_init(content)

    def resolve(dir_path: str, in_namespace: bool, split_libraries: bool) -> list[str]:
        # Namespaces are only detected directly below other namespaces: other distributions can't
        # install into a regular package's subdirectories. Directories holding shared libraries
        # are split below a namespace (split_libraries), never at the top level.
        namespace = in_namespace and is_namespace(dir_path)
        split = split_libraries and dir_path in library_dirs
        if not namespace and not split:
            # Regular package (or plain directory): can be linked directly.
            return [dir_path]

        # Namespace package, or a directory holding shared libraries: link its files and descend
        # into its subdirectories. A namespace's own __init__.py (if any) is shared by every
        # distribution, so it isn't linked, and neither are its bytecode caches.
        file_names, subdir_names = children.get(dir_path, (set(), set()))
        kept = [f"{dir_path}/{name}" for name in file_names if not (namespace and name == "__init__.py")]
        for name in sorted(subdir_names):
            if namespace and name == "__pycache__":
                continue
            kept.extend(resolve(f"{dir_path}/{name}", namespace, True))
        # A namespace dir with no concrete sub-packages or files resolves to nothing.
        return kept

    result = set()
    for dir_name in top_level_dirs:
        result.update(resolve(dir_name, True, False))
    return result


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
            returned, except that namespace packages among them resolve to their concrete paths
            and single-file `.py` modules resolve to `<name>.py`.
    """
    source_dir_path = PurePosixPath(source_dir.strip("/")) if source_dir else None

    # Collect all file paths and candidate top-level directories.
    all_files: set[str] = set()
    members: dict[str, str] = {}  # relative path -> archive entry name
    top_level_dirs: set[str] = set()
    trusted_dirs: set[str] = set()  # explicit DIRTYPE entries or dirs under src/
    root_files: set[str] = set()
    src_layout = False

    def _is_candidate_dir(dir_name: str) -> bool:
        return dir_name not in _EXCLUDED_DIRS and not dir_name.endswith(".egg-info")

    for name, is_dir, is_file in items:
        clean_name = name.rstrip("/")
        rel = _rel_under_effective_root(clean_name, source_dir_path)
        if rel is None:
            continue

        if is_file:
            # Collect all relative file paths for namespace package resolution.
            rel_str = str(rel)
            all_files.add(rel_str)
            members[rel_str] = clean_name

            if len(rel.parts) == 1:
                root_files.add(rel.parts[0])
            elif len(rel.parts) == 2 and rel.parts[0] == "src":
                root_files.add(rel.parts[1])
                if _extract_module_name(rel.parts[1]):
                    src_layout = True
            elif len(rel.parts) >= 3 and rel.parts[0] == "src":
                # File-only sdists (flit, hatchling, poetry-core, maturin, uv_build)
                # omit explicit directory entries, so infer src_layout and top-level
                # dirs from Python module files under src/ (ignoring C/Rust-only src/ trees).
                if _is_candidate_dir(rel.parts[1]):
                    top_level_dirs.add(rel.parts[1])
                    trusted_dirs.add(rel.parts[1])
                    if _extract_module_name(rel.parts[-1]):
                        src_layout = True
            elif len(rel.parts) >= 2 and _is_candidate_dir(rel.parts[0]):
                top_level_dirs.add(rel.parts[0])
        elif is_dir:
            if len(rel.parts) == 1 and _is_candidate_dir(rel.parts[0]):
                top_level_dirs.add(rel.parts[0])
                trusted_dirs.add(rel.parts[0])
            elif len(rel.parts) == 2 and rel.parts[0] == "src" and _is_candidate_dir(rel.parts[1]):
                top_level_dirs.add(rel.parts[1])
                trusted_dirs.add(rel.parts[1])

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
        # namespace packages among them so distributions sharing a namespace don't collide, and
        # map single-file `.py` modules to `<name>.py` for venv symlink installation.
        declared = set()
        for name in top_level_names:
            if any(f.startswith(name + "/") for f in all_files):
                declared.update(_resolve_top_level_paths(all_files, {name}, read_file))
            elif f"{name}.py" in all_files:
                declared.add(f"{name}.py")
            else:
                declared.add(name)
        return sorted(declared)

    def _has_python(d: str) -> bool:
        prefix = d + "/"
        return any(f.startswith(prefix) and _extract_module_name(f.rsplit("/", 1)[1]) for f in all_files)

    # An sdist's top-level dirs are only a guess at what the built wheel installs; a dir with
    # no Python anywhere below it (.github/, requirements/, licenses/) can't be an import package.
    # For file-only sdists (flit, hatchling, poetry-core, pdm, maturin), also require an explicit
    # `<dir>/__init__.py` on non-`src/` dirs inferred solely from file entries so non-package trees
    # (`pysrc/`, `crates/`, `bindings/`, `bench/`) return `[]` and preserve wheel_library's fallback.
    top_level_dirs = {
        d
        for d in top_level_dirs
        if d.isidentifier() and _has_python(d) and (d in trusted_dirs or f"{d}/__init__.py" in all_files)
    }
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


def _collect_sdist_entries(
    entries: Iterable[SdistEntry],
    source_dir: str = "",
) -> tuple[str, list[str]]:
    """Collect pyproject.toml, top_level.txt, and site_paths in a single pass over sdist entries."""
    source_dir_path = PurePosixPath(source_dir.strip("/")) if source_dir else None
    pyproject_content = ""
    top_level_names: list[str] | None = None
    items: list[tuple[str, bool, bool]] = []
    init_contents: dict[str, str] = {}

    for name, is_dir, is_file, read_bytes in entries:
        items.append((name, is_dir, is_file))
        if not is_file:
            continue
        clean_name = name.rstrip("/")
        rel = _rel_under_effective_root(clean_name, source_dir_path)
        is_pyproject = not pyproject_content and (
            rel == PurePosixPath("pyproject.toml")
            or (not source_dir_path and PurePosixPath(clean_name) == PurePosixPath("pyproject.toml"))
        )
        is_top_level = (
            not source_dir_path and top_level_names is None and rel is not None and _is_top_level_txt_rel(rel)
        )
        is_init = rel is not None and rel.name == "__init__.py"
        if not (is_pyproject or is_top_level or is_init):
            continue
        raw = read_bytes()
        if raw is None:
            continue
        if is_pyproject:
            pyproject_content = raw.decode("utf-8")
        elif is_top_level:
            names = [line.strip() for line in raw.decode("utf-8").splitlines() if line.strip()]
            if names:
                top_level_names = names
        elif is_init:
            init_contents[clean_name] = raw.decode("utf-8", "replace")

    site_paths = _find_site_paths_from_items(
        items,
        source_dir=source_dir,
        read_member=init_contents.get,
        top_level_names=top_level_names,
    )
    return pyproject_content, site_paths


def _iter_tar_entries(tar: tarfile.TarFile) -> Iterator[SdistEntry]:
    for member in tar:
        is_dir = member.isdir()
        is_file = member.isfile()

        def _read(m: tarfile.TarInfo = member) -> Optional[bytes]:
            f = tar.extractfile(m)
            return f.read() if f else None

        yield member.name, is_dir, is_file, _read


def _iter_zip_entries(zf: zipfile.ZipFile) -> Iterator[SdistEntry]:
    for name in zf.namelist():
        is_dir = name.endswith("/")
        yield name, is_dir, not is_dir, (lambda n=name: zf.read(n))


def _iter_dir_entries(
    root: Path,
    base: Path,
    archive_dirs: set[str],
) -> Iterator[SdistEntry]:
    # Only mark extracted directories as explicit directory entries when the
    # original archive had a matching directory entry, so file-only sdists keep
    # excluding non-package trees (e.g. bench/, crates/) after extraction.
    for p in sorted(root.rglob("*"), key=lambda path: (len(path.parts), path.as_posix())):
        rel_posix = p.relative_to(base).as_posix()
        is_file = p.is_file()
        is_dir = p.is_dir() and rel_posix in archive_dirs
        if not is_file and not is_dir:
            continue
        yield rel_posix, is_dir, is_file, p.read_bytes


def _inspect_unpatched_sdist(sdist_path: Path, source_dir: str = "") -> tuple[str, list[str]]:
    """Inspect an unpatched sdist archive in a single pass, returning (pyproject_content, site_paths)."""
    if sdist_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
        with tarfile.open(sdist_path) as t:
            return _collect_sdist_entries(_iter_tar_entries(t), source_dir=source_dir)

    if sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path) as z:
            return _collect_sdist_entries(_iter_zip_entries(z), source_dir=source_dir)

    return "", []


def _inspect_patched_sdist(
    sdist_path: Path,
    source_dir: str,
    pre_build_patches: list[Path],
) -> tuple[str, list[str]]:
    """Extract an sdist, apply pre_build_patches, and return (pyproject_content, site_paths)."""
    from pycross_patch import apply_patch_or_exit

    resolved_patches = [(patch_path, Path(patch_path).resolve()) for patch_path in pre_build_patches]
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        if sdist_path.name.endswith((".tar.gz", ".tgz", ".tar.bz2", ".tar")):
            with tarfile.open(sdist_path, "r") as f:
                if hasattr(tarfile, "data_filter"):
                    f.extraction_filter = tarfile.data_filter
                members = f.getmembers()
                archive_dirs = {PurePosixPath(m.name.rstrip("/")).as_posix() for m in members if m.isdir()}
                f.extractall(tmp_path, members=members)
        elif sdist_path.name.endswith(".zip"):
            with zipfile.ZipFile(sdist_path, "r") as f:
                archive_dirs = {
                    PurePosixPath(info.filename.rstrip("/")).as_posix() for info in f.infolist() if info.is_dir()
                }
                f.extractall(tmp_path)
        else:
            raise ValueError(f"Unsupported sdist format: {sdist_path}")

        extracted_dirs = list(tmp_path.glob("*"))
        if len(extracted_dirs) != 1 or not extracted_dirs[0].is_dir():
            raise ValueError(f"Expected exactly one directory in sdist archive, got: {extracted_dirs}")

        sdist_root_dir = extracted_dirs[0]
        sdist_dir = sdist_root_dir / source_dir.strip("/") if source_dir else sdist_root_dir

        for orig_patch_path, abs_patch_path in resolved_patches:
            apply_patch_or_exit(sdist_dir, abs_patch_path, display_name=str(orig_patch_path))

        return _collect_sdist_entries(
            _iter_dir_entries(sdist_dir, tmp_path, archive_dirs),
            source_dir=source_dir,
        )


def _classify_site_paths(
    all_files: set[str],
    top_level_dirs: set[str],
    root_files: set[str],
    read_file: Optional[FileReader] = None,
) -> list[str]:
    """Classify site-packages entries into concrete top-level importable paths."""
    pkgs = _resolve_top_level_paths(all_files, top_level_dirs, read_file)
    for f in root_files:
        name = _extract_module_name(f)
        if name and name not in _EXCLUDED_ROOT_MODULES:
            pkgs.add(f)
    return sorted(pkgs)


def find_installed_site_paths(lib_dir: Path) -> list[str]:
    """Return concrete top-level site_paths installed under a site-packages directory.

    Shares classification with wheel inspection (`_find_wheel_paths`) so regular
    packages, namespace packages, top-level modules, and auditwheel `<pkg>.libs`
    directories stay consistent between repo-time inspection and install-time
    validation.
    """
    if not lib_dir.is_dir():
        return []

    all_files: set[str] = set()
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()

    for root, dirs, files in os.walk(lib_dir):
        rel_root = Path(root).relative_to(lib_dir)
        if rel_root == Path("."):
            dirs[:] = sorted(d for d in dirs if not d.endswith(".dist-info") and d != "__pycache__")
            root_files.update(files)
            continue

        top_level_dirs.add(rel_root.parts[0])
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for fn in files:
            all_files.add((rel_root / fn).as_posix())

    def read_file(rel_path: str) -> Optional[str]:
        target = lib_dir / rel_path
        if not target.is_file():
            return None
        return target.read_text(encoding="utf-8", errors="replace")

    return _classify_site_paths(all_files, top_level_dirs, root_files, read_file)


def _find_wheel_paths(wheel_path: Path) -> tuple[list[str], list[str], list[str], list[str]]:
    all_files: set[str] = set()
    top_level_dirs: set[str] = set()
    root_files: set[str] = set()

    bin_paths = set()
    data_paths = set()
    include_paths = set()

    # Maps site-packages-relative paths in all_files to archive member names.
    members: dict[str, str] = {}
    entry_points_member: Optional[str] = None

    with zipfile.ZipFile(wheel_path) as z:
        for name in z.namelist():
            parts = name.split("/")
            if parts[0].endswith(".dist-info"):
                if entry_points_member is None and len(parts) == 2 and parts[1] == "entry_points.txt":
                    entry_points_member = name
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

            if not parts[0] or parts[0].endswith(".data"):
                continue
            if not name.endswith("/"):
                all_files.add(name)
                members[name] = name
            if len(parts) >= 2:
                top_level_dirs.add(parts[0])
            elif len(parts) == 1 and parts[0] and not name.endswith("/"):
                root_files.add(parts[0])

        def read_file(path: str) -> Optional[str]:
            return z.read(members[path]).decode("utf-8", "replace") if path in members else None

        site_paths = _classify_site_paths(all_files, top_level_dirs, root_files, read_file)

        if entry_points_member is not None:
            bin_paths.update(_parse_entry_points(z.read(entry_points_member).decode("utf-8")))

    return site_paths, sorted(bin_paths), sorted(data_paths), sorted(include_paths)


def inspect_sdist(
    sdist_path: Path,
    source_dir: str = "",
    pre_build_patches: list[Path] | None = None,
) -> dict:
    if pre_build_patches:
        content, site_paths = _inspect_patched_sdist(sdist_path, source_dir, pre_build_patches)
    else:
        content, site_paths = _inspect_unpatched_sdist(sdist_path, source_dir=source_dir)

    warnings = []
    if content:
        tomllib = _load_tomllib()
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
    project = pyproject.get("project", {})
    bin_paths: set[str] = set()
    if isinstance(project, dict):
        for table_name in ("scripts", "gui-scripts"):
            scripts = project.get(table_name)
            if isinstance(scripts, dict):
                bin_paths.update(scripts.keys())

    result = {
        "build_backend": build_system.get("build-backend", PEP517_DEFAULT_BACKEND),
        "build_requires": build_system.get("requires", PEP517_DEFAULT_REQUIRES),
        "site_paths": site_paths,
        "bin_paths": sorted(bin_paths),
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
