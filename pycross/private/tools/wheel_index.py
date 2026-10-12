"""Per-wheel index: an exact description of one installed site-packages directory.

`wheel_installer.py` writes it as the last step of the `PycrossWheelInstall` action, after
`install_exclude_globs`, `post_install_patches` and `.pyc` compilation, by scanning the installed
tree. It describes what is actually installed (for sdist-built wheels too), and holds only facts
local to the wheel. Anything that depends on a set of wheels (namespace merging, precedence,
conflicts, the Gazelle modules mapping) is up to the consumers.

Format, version 1. Paths are relative to site-packages and use "/". Lists are sorted, and there
are no absolute paths or timestamps, so the output is deterministic.

  version       1. Consumers must ignore keys they don't know: optional sections (such as a
                future "native" section with SONAME/NEEDED/RUNPATH per shared library) can be
                added without bumping the version.
  distribution  {"name": ..., "version": ...} from the installed METADATA.
  dist_info     The name of the .dist-info directory.
  top           Top-level importable name -> the root entries that provide it, for example
                {"six": ["six.py"], "yaml": ["yaml"], "_yaml": ["_yaml.cpython-312-x86_64-linux-gnu.so"]}.
  pth           The .pth files in the root.
  pth_paths     For root .pth files with path lines: the directories they add to sys.path, as
                normalized paths relative to the root, in file order, for example
                {"rerun_sdk.pth": ["rerun_sdk"]}. Like site.addpackage, this skips comments, blank
                lines and import lines, and only keeps lines naming an existing directory.
                Absolute paths and paths outside the root are dropped, and backslashes are read
                as separators (Windows .pth files).
  dirs          Every package directory: identifier-named directories below an importable
                top-level directory, excluding __pycache__.
  namespaces    Namespace package directories (no __init__ module, or an __init__.py that is a
                pure pkgutil/pkg_resources namespace stub) that are reachable from the root through
                namespace directories only, mapped to the names of the module files directly
                inside them. Their sub-packages are in "dirs". These are the directories that
                several distributions can share, so consumers need their module files to tell the
                distributions apart.

Module names don't depend on the interpreter running this code: extension modules are recognized
as `<name>.so`, `<name>.<tag>.so`, `<name>.pyd` and `<name>.<tag>.pyd` for any ABI tag, because
the installer can run on a different platform and Python version than the wheel targets.
"""

from __future__ import annotations

import ast
import json
import os
import posixpath
import re
from email.parser import BytesHeaderParser
from pathlib import Path
from typing import Any
from typing import Optional

INDEX_VERSION = 1

_EXTENSION_MODULE_RE = re.compile(r"^([^.]+)(?:\.[^.]+)?\.(?:so|pyd)$")

# Not packages. Skipping them also keeps the index the same with and without .pyc compilation.
_SKIPPED_DIRS = frozenset({"__pycache__"})


def module_name(filename: str) -> Optional[str]:
    """Returns the importable module name of a file name, or None if it isn't a module."""
    if filename.endswith(".py"):
        stem = filename[: -len(".py")]
    elif filename.endswith(".pyc"):
        stem = filename[: -len(".pyc")]
    else:
        match = _EXTENSION_MODULE_RE.match(filename)
        if not match:
            return None
        stem = match.group(1)
    return stem if stem.isidentifier() else None


# Keep the namespace stub detection in sync with inspect_package.py (_is_pkgutil_namespace_init).
# It is duplicated because inspect_package.py runs at repository time as a standalone file.
_NAMESPACE_MODULES = frozenset({"pkgutil", "pkg_resources"})
_NAMESPACE_FUNCTIONS = frozenset({"extend_path", "declare_namespace"})


def _is_name(node: ast.AST, name: str) -> bool:
    return isinstance(node, ast.Name) and node.id == name


def _is_namespace_call(node: ast.AST, function: str, args: tuple[str, ...]) -> bool:
    if not isinstance(node, ast.Call) or node.keywords or len(node.args) != len(args):
        return False
    func = node.func
    if not (_is_name(func, function) or (isinstance(func, ast.Attribute) and func.attr == function)):
        return False
    return all(_is_name(arg, name) for arg, name in zip(node.args, args))


def is_pkgutil_namespace_init(content: str) -> bool:
    """Whether an __init__.py is a pure pkgutil- or pkg_resources-style namespace package stub."""
    # A stub declares the namespace at least once, so this skips parsing regular packages that
    # keep their code in __init__.py (e.g. backports.tarfile's 100 KB one).
    if not any(function in content for function in _NAMESPACE_FUNCTIONS):
        return False
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


def _scan(path: Path) -> tuple[list[str], list[str]]:
    """Returns the sorted (package subdirectory names, file names) of a directory."""
    subdirs, files = [], []
    with os.scandir(path) as it:
        for entry in it:
            if entry.is_dir():
                if entry.name.isidentifier() and entry.name not in _SKIPPED_DIRS:
                    subdirs.append(entry.name)
            else:
                files.append(entry.name)
    return sorted(subdirs), sorted(files)


def _is_namespace_dir(path: Path, files: list[str]) -> bool:
    init_files = [f for f in files if module_name(f) == "__init__"]
    if not init_files:
        return True  # PEP 420
    if init_files != ["__init__.py"]:
        return False  # compiled or sourceless __init__
    content = (path / "__init__.py").read_bytes().decode("utf-8", "replace")
    return is_pkgutil_namespace_init(content)


def _read_distribution(dist_info_path: Optional[Path]) -> dict[str, Optional[str]]:
    if dist_info_path is None:
        return {}
    metadata = dist_info_path / "METADATA"
    if not metadata.is_file():
        return {}
    headers = BytesHeaderParser().parsebytes(metadata.read_bytes())
    return {"name": headers.get("Name"), "version": headers.get("Version")}


def _pth_paths(root: Path, name: str) -> list[str]:
    """Returns the directories a root .pth file adds to sys.path, relative to the root.

    Follows site.addpackage: comments, blank lines and import lines are skipped, and a path line is
    used only if it names an existing directory.
    """
    text = (root / name).read_bytes().decode("utf-8-sig", "replace")
    paths: list[str] = []
    for line in text.splitlines():
        if line.startswith("#") or not line.strip() or line.startswith(("import ", "import\t")):
            continue
        line = line.rstrip().replace("\\", "/")
        if posixpath.isabs(line) or re.match(r"^[A-Za-z]:", line):
            continue
        rel = posixpath.normpath(line)
        if rel == "." or rel == ".." or rel.startswith("../"):
            continue
        if (root / rel).is_dir() and rel not in paths:
            paths.append(rel)
    return paths


def index_site_packages(
    root: Path,
    fallback_name: Optional[str] = None,
    fallback_version: Optional[str] = None,
) -> dict[str, Any]:
    """Builds the per-wheel index of an installed site-packages directory.

    Args:
        root: The site-packages directory.
        fallback_name: Distribution name to use if METADATA has none (e.g. from the wheel file name).
        fallback_version: Distribution version to use if METADATA has none.
    """
    root = Path(root)
    top: dict[str, list[str]] = {}
    pth: list[str] = []
    dirs: list[str] = []
    namespaces: dict[str, list[str]] = {}
    dist_info = None

    def walk(rel: str, parent_is_namespace: bool) -> None:
        dirs.append(rel)
        path = root / rel
        subdirs, files = _scan(path)
        is_namespace = parent_is_namespace and _is_namespace_dir(path, files)
        if is_namespace:
            namespaces[rel] = sorted({m for m in map(module_name, files) if m and m != "__init__"})
        for subdir in subdirs:
            walk(rel + "/" + subdir, is_namespace)

    with os.scandir(root) as it:
        entries = sorted(it, key=lambda e: e.name)
    for entry in entries:
        name = entry.name
        if entry.is_dir():
            if name.endswith(".dist-info"):
                dist_info = dist_info or name
            elif name.isidentifier() and name not in _SKIPPED_DIRS:
                top.setdefault(name, []).append(name)
                walk(name, True)
        elif name.endswith(".pth"):
            pth.append(name)
        else:
            mod = module_name(name)
            if mod:
                top.setdefault(mod, []).append(name)

    pth_paths = {}
    for name in sorted(pth):
        paths = _pth_paths(root, name)
        if paths:
            pth_paths[name] = paths

    distribution = _read_distribution(root / dist_info if dist_info else None)
    return {
        "version": INDEX_VERSION,
        "distribution": {
            "name": distribution.get("name") or fallback_name,
            "version": distribution.get("version") or fallback_version,
        },
        "dist_info": dist_info,
        "top": {k: sorted(v) for k, v in sorted(top.items())},
        "pth": sorted(pth),
        "pth_paths": pth_paths,
        "dirs": sorted(dirs),
        "namespaces": dict(sorted(namespaces.items())),
    }


def write_index(
    root: Path,
    output: Path,
    fallback_name: Optional[str] = None,
    fallback_version: Optional[str] = None,
) -> None:
    """Writes the per-wheel index of `root` to `output` as compact, key-sorted JSON."""
    index = index_site_packages(root, fallback_name, fallback_version)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, "w", encoding="utf-8") as f:
        json.dump(index, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
