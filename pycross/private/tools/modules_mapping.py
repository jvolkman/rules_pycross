"""Builds the Gazelle modules mapping from per-wheel index files.

The output is the JSON that rules_python_gazelle_plugin's `gazelle_python_manifest` consumes:
`{import name: distribution name}`, with canonical (PEP 503) distribution names that use "_"
instead of "-".

The Gazelle plugin looks up `a.b.c`, then `a.b`, then `a` (exact matches), so the mapping lists,
per distribution, the shallowest import names that identify it:

* Names that a single distribution provides concretely (a module, or a regular package) map to it.
* Namespace packages (PEP 420, pkgutil/pkg_resources stubs, and the well-known `nvidia`) are
  never mapped themselves: the lookup descends into them to the concrete modules and packages
  that each distribution adds. This holds even when only one distribution in the set provides the
  namespace, since a dependency outside the set can still add to it.
* Names that several distributions provide concretely (e.g. two wheels shipping the same package)
  are dropped, and the lookup descends into them so that sub-packages provided by only one of
  them still map to it.
* Directories that a distribution's .pth files put on sys.path (`pth_paths`) are extra roots:
  the names below them are top-level names too (rerun-sdk's `rerun_sdk.pth` makes
  `rerun_sdk/rerun` importable as `rerun`).
* Top-level names in inspect_package.py's denylists (`tests`, `docs`, `setup`, ...) are never
  mapped. Gazelle consults the mapping before first-party code, so such keys would capture
  imports of a project's own `tests` package.
* Finally, entries whose ancestor maps to the same distribution are collapsed into the ancestor,
  like rules_python's modules_mapping merger.

Packages without an index can pass their analysis-time `site_paths` instead (`--site-path`), which
are treated as concrete names below namespace parents.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any
from typing import Iterable
from typing import Optional

from pycross.private.tools.args import FlagFileArgumentParser

SUPPORTED_INDEX_VERSION = 1

# Top-level namespace packages whose distributions each ship a plain (non-declaring) __init__.py.
# Mirrors inspect_package.py's _WELL_KNOWN_NAMESPACE_PACKAGES (from rules_python).
WELL_KNOWN_NAMESPACES = frozenset({"nvidia"})

# Top-level names that are never mapped: inspect_package.py's _EXCLUDED_DIRS and
# _EXCLUDED_ROOT_MODULES, plus names that can't refer to a third-party module.
EXCLUDED_TOP_LEVEL_NAMES = frozenset(
    {
        # _EXCLUDED_DIRS
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
        # _EXCLUDED_ROOT_MODULES
        "setup",
        "conftest",
        # Not importable as third-party modules.
        "__init__",
        "__main__",
    }
)

MODULE = "module"
PACKAGE = "package"
NAMESPACE = "namespace"


def canonical_name(name: str) -> str:
    """PEP 503-normalizes a distribution name, using "_" as the separator."""
    return re.sub(r"[-_.]+", "-", name).lower().replace("-", "_")


def _strip_extensions(path: str) -> str:
    for ext in [".pth", ".so", ".py", ".pyd"]:
        if path.endswith(ext):
            path = path[: -len(ext)]
            if ".cpython-" in path:
                path = path.split(".cpython-")[0]
            elif ".abi3-" in path:
                path = path.split(".abi3-")[0]
            elif path.endswith(".abi3"):
                path = path[: -len(".abi3")]
            break
    return path


def module_name_from_site_path(site_path: str) -> Optional[str]:
    """Converts a site_paths entry (e.g. `ns/pkg` or `six.py`) to a dotted import name."""
    name = _strip_extensions(site_path).replace("/", ".")
    if not all(part.isidentifier() for part in name.split(".")):
        return None
    return name


class Distribution:
    """The import names that one distribution provides, as a tree of dotted names."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.kinds: dict[str, str] = {}
        self.children: dict[str, set[str]] = {}

    def add(self, dotted: str, kind: str) -> None:
        # A module next to a namespace directory of the same name is what gets imported, so
        # concrete kinds win over NAMESPACE. (A regular package wins over a module; both are
        # concrete, so it doesn't matter which is recorded.)
        if self.kinds.get(dotted) in (None, NAMESPACE):
            self.kinds[dotted] = kind
        self.children.setdefault(dotted.rpartition(".")[0], set()).add(dotted)

    def add_index(self, index: dict[str, Any]) -> None:
        namespaces = index.get("namespaces", {})
        for d in index.get("dirs", []):
            is_namespace = d in namespaces or ("/" not in d and d in WELL_KNOWN_NAMESPACES)
            self.add(d.replace("/", "."), NAMESPACE if is_namespace else PACKAGE)
        for d, modules in namespaces.items():
            for module in modules:
                self.add(d.replace("/", ".") + "." + module, MODULE)
        for d, modules in index.get("modules", {}).items():
            for module in modules:
                self.add(d.replace("/", ".") + "." + module, MODULE)
        for name, entries in index.get("top", {}).items():
            if any(entry != name for entry in entries):
                self.add(name, MODULE)  # a module file in the root
            elif name not in self.kinds:
                self.add(name, PACKAGE)  # defensive: a top-level directory missing from "dirs"
        for paths in index.get("pth_paths", {}).values():
            for path in paths:
                self.add_root(path.replace("/", "."))

    def add_root(self, prefix: str) -> None:
        """Makes the names below `prefix` top-level names too, like a .pth path entry does.

        Only names the index knows are re-rooted: the directory's sub-packages, and its module
        files if it is a namespace directory (as .pth targets usually are).
        """
        cut = len(prefix) + 1
        for name, kind in sorted(self.kinds.items()):
            if name.startswith(prefix + "."):
                self.add(name[cut:], kind)

    def add_site_path(self, site_path: str) -> None:
        name = module_name_from_site_path(site_path)
        if not name:
            return
        parts = name.split(".")
        for i in range(1, len(parts)):
            self.add(".".join(parts[:i]), NAMESPACE)
        self.add(name, MODULE)


def simplify(mapping: dict[str, str]) -> dict[str, str]:
    """Collapses entries into an ancestor that maps to the same distribution.

    Same algorithm as rules_python's gazelle/modules_mapping/merger.py.
    """
    simplified: dict[str, str] = {}
    for module, dist in sorted(mapping.items()):
        mod = module
        while True:
            if mod in simplified:
                if simplified[mod] == dist:
                    dist = ""
                break
            if "." not in mod:
                break
            mod = mod.rsplit(".", 1)[0]
        if dist:
            simplified[module] = dist
    return simplified


def _canonical_owner(pkg: str, concrete: list[Distribution]) -> Optional[Distribution]:
    """When several distributions ship `__init__.py` for `pkg`, picks the one named after `pkg`."""
    if not all(d.kinds[pkg] == PACKAGE for d in concrete):
        return None
    norm = canonical_name(pkg.replace(".", "_"))
    norm_base = re.sub(r"_v\d+$", "", norm)
    matches = [d for d in concrete if d.name in (norm, norm_base)]
    return matches[0] if len(matches) == 1 else None


def build_mapping(distributions: Iterable[Distribution]) -> dict[str, str]:
    """Builds the import name -> distribution mapping for a set of distributions."""
    mapping: dict[str, str] = {}

    def resolve(parent: str, contributors: list[Distribution]) -> None:
        claims: dict[str, tuple[list[Distribution], list[Distribution]]] = {}
        for dist in contributors:
            for child in dist.children.get(parent, ()):
                if not parent and child in EXCLUDED_TOP_LEVEL_NAMES:
                    continue
                concrete, namespace = claims.setdefault(child, ([], []))
                (namespace if dist.kinds[child] == NAMESPACE else concrete).append(dist)

        for child in sorted(claims):
            concrete, namespace = claims[child]
            if len(concrete) == 1:
                mapping[child] = concrete[0].name
            elif len(concrete) > 1:
                owner = _canonical_owner(child, concrete)
                if owner is not None:
                    mapping[child] = owner.name
            # Descend unless a single distribution owns the name outright. Entries that end up
            # below an ancestor with the same distribution are collapsed by simplify().
            if namespace or len(concrete) > 1:
                resolve(child, concrete + namespace)

    resolve("", sorted(distributions, key=lambda d: d.name))
    return simplify(mapping)


def _index_distribution_name(index: dict[str, Any], path: Path) -> str:
    name = (index.get("distribution") or {}).get("name")
    if not name and index.get("dist_info"):
        name = index["dist_info"][: -len(".dist-info")].rpartition("-")[0]
    if not name:
        raise SystemExit(f"error: per-wheel index {path} has no distribution name")
    return name


def load_index(path: Path) -> dict[str, Any]:
    with open(path, encoding="utf-8") as f:
        index = json.load(f)
    version = index.get("version")
    if not isinstance(version, int) or version > SUPPORTED_INDEX_VERSION:
        raise SystemExit(
            f"error: per-wheel index {path} has version {version!r}; "
            f"this tool supports versions up to {SUPPORTED_INDEX_VERSION}"
        )
    return index


def main(args: Any) -> None:
    distributions: dict[str, Distribution] = {}

    def distribution(name: str) -> Distribution:
        key = canonical_name(name)
        return distributions.setdefault(key, Distribution(key))

    for path in sorted(set(args.indexes)):
        index = load_index(path)
        distribution(_index_distribution_name(index, path)).add_index(index)

    for entry in args.site_paths:
        name, sep, site_path = entry.partition("=")
        if not sep or not name or not site_path:
            raise SystemExit(f"error: --site-path expects NAME=PATH, got {entry!r}")
        distribution(name).add_site_path(site_path)

    mapping = build_mapping(distributions.values())
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(mapping, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")


def parse_flags(argv: Optional[list[str]] = None) -> Any:
    parser = FlagFileArgumentParser(description="Generate a Gazelle modules mapping from per-wheel indexes.")
    parser.add_argument("--output", type=Path, required=True, help="The modules_mapping.json to write.")
    parser.add_argument(
        "--index",
        type=Path,
        action="append",
        dest="indexes",
        default=[],
        help="A per-wheel index file written by the wheel installer.",
    )
    parser.add_argument(
        "--site-path",
        action="append",
        dest="site_paths",
        default=[],
        help="NAME=PATH: a site_paths entry of a package without a per-wheel index.",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    main(parse_flags())
