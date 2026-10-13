# Copyright 2026 The rules_pycross Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Import index over the wheel roots of a binary.

When `--@rules_pycross//pycross/settings:venv_import_index` isn't `off`, this
module is linked into the binary's venv site-packages as `_bazel_import_index.py`
alongside `pycross_import_index.pth`, which calls `auto_install()` right after
`bazel.pth` initializes `sys.path`.

Every wheel root stays on `sys.path`, so code that walks `sys.path` (pkgutil,
torch's CUDA preload glob, IDEs probing the interpreter) keeps working. The
finder replaces `importlib.machinery.PathFinder` in `sys.meta_path` and
resolves imports as if all wheel roots were one merged site-packages directory
(what pip would produce), located where the first wheel root sits on
`sys.path`.
"""

import os
import posixpath
import sys
from importlib import machinery as _machinery

try:
    # Avoid importing importlib.util at startup: it's only a re-export of these
    # and costs ~1ms.
    from importlib._bootstrap_external import _NamespacePath
    from importlib._bootstrap_external import spec_from_file_location
except ImportError:  # pragma: no cover
    from importlib.util import spec_from_file_location

    _NamespacePath = None

_LOG_PREFIX = "rules_pycross import_index:"
_SUPPORTED_VERSION = 1

# Substituted when expanded by pycross_venv_import_index_runtime.
_DEFAULT_MODE = "%import_index_mode%"

# FileFinder's loader order: extension modules, then source, then bytecode.
_LOADERS = (
    [(s, _machinery.ExtensionFileLoader) for s in _machinery.EXTENSION_SUFFIXES]
    + [(s, _machinery.SourceFileLoader) for s in _machinery.SOURCE_SUFFIXES]
    + [(s, _machinery.SourcelessFileLoader) for s in _machinery.BYTECODE_SUFFIXES]
)

_DEBUG = False
# The installed _Index, or None.
_INDEX = None
# Names of packages whose __path__ spans several directories. Lookups of their
# children keep merging same-named directories.
_MERGED = set()
# Cache for _split(): (search path, pre, post, wheel roots on the search path).
_SPLIT = (None, (), (), frozenset())
# Cache for PathDistribution.read_text(): (dist-info path, filename) -> text.
_METADATA_TEXT = {}
_CACHED_DIST_CLS = {}
_CACHED_METADATA_FILES = ("METADATA", "PKG-INFO", "entry_points.txt")


def _log(*args):
    print(_LOG_PREFIX, *args, file=sys.stderr, flush=True)


def _normalize_dist_name(name):
    """importlib.metadata's Prepared.normalize()."""
    import re

    return re.sub(r"[-_.]+", "-", name).lower().replace("-", "_")


def dist_info_key(dist_info):
    """The normalized distribution name of a .dist-info directory name."""
    return _normalize_dist_name(dist_info.lower().rpartition(".")[0].partition("-")[0])


def _candidate_origin_dirs(own_dirs, so_dir, entry):
    for token in ("$ORIGIN/", "${ORIGIN}/"):
        if entry.startswith(token):
            after = entry[len(token) :]
            break
    else:
        return ()
    if not after:
        return ()
    norm = posixpath.normpath(posixpath.join(so_dir, after) if so_dir else after)
    if norm == "." or (not norm.startswith("..") and norm in own_dirs):
        return ()
    candidates = []
    if not norm.startswith(".."):
        candidates.append(norm)
    parts = posixpath.normpath(after).split("/")
    while parts and parts[0] == "..":
        parts.pop(0)
    if parts and parts != ["."]:
        stripped = "/".join(parts)
        if stripped not in own_dirs and stripped not in candidates:
            candidates.append(stripped)
    return candidates


def _compute_preload(wheel_indexes):
    if not any(idx.get("native") for idx in wheel_indexes):
        return {}

    own_dirs_per_wheel = []
    libs_by_dir = {}
    by_soname = {}
    meta_by_key = {}

    for i, idx in enumerate(wheel_indexes):
        own_dirs = set(idx.get("dirs", ())) | set(idx.get("top", ()))
        for rel_so, meta in sorted(idx.get("native", {}).items()):
            parent = posixpath.dirname(rel_so)
            while parent:
                own_dirs.add(parent)
                parent = posixpath.dirname(parent)
            key = (i, rel_so)
            meta_by_key[key] = meta
            soname = meta.get("soname")
            if soname:
                so_dir = posixpath.dirname(rel_so)
                libs_by_dir.setdefault(so_dir, []).append(key)
                by_soname.setdefault(soname, key)
        own_dirs_per_wheel.append(own_dirs)

    def escaping_targets(wheel_idx, rel_so, meta):
        so_dir = posixpath.dirname(rel_so)
        own_dirs = own_dirs_per_wheel[wheel_idx]
        rpaths = list(meta.get("runpath") or ()) + list(meta.get("rpath") or ())
        targets = []
        for entry in rpaths:
            for cand_dir in _candidate_origin_dirs(own_dirs, so_dir, entry):
                for key in libs_by_dir.get(cand_dir, ()):
                    if key[0] != wheel_idx and key not in targets:
                        targets.append(key)
        return targets

    pkg_roots = {}
    for i, idx in enumerate(wheel_indexes):
        for rel_so, meta in sorted(idx.get("native", {}).items()):
            targets = escaping_targets(i, rel_so, meta)
            if not targets:
                continue
            top_pkg = rel_so.split("/", 1)[0] if "/" in rel_so else rel_so.split(".", 1)[0]
            seeds = pkg_roots.setdefault(top_pkg, [])
            for t in targets:
                if t not in seeds:
                    seeds.append(t)

    preload = {}
    for top_pkg, seeds in sorted(pkg_roots.items()):
        ordered = []
        visited = set()

        def visit(key):
            if key in visited:
                return
            visited.add(key)
            meta = meta_by_key[key]
            for needed_name in meta.get("needed") or ():
                dep_key = by_soname.get(needed_name)
                if dep_key is not None:
                    visit(dep_key)
            for dep_key in escaping_targets(key[0], key[1], meta):
                visit(dep_key)
            ordered.append([key[0], key[1]])

        for seed in seeds:
            visit(seed)
        if ordered:
            preload[top_pkg] = ordered

    return preload


def merge_wheel_indexes(entries):
    """Merges per-wheel indexes into a single binary import index dict.

    Args:
        entries: [(root, per-wheel index dict)] in sys.path order.

    Returns:
        The merged index dict.
    """
    roots = []
    wheel_indexes = []
    distributions = []
    top = {}
    dists = {}
    pth = []
    dir_owners = {}
    for root, index in entries:
        version = index.get("version")
        if version != _SUPPORTED_VERSION:
            raise ValueError(
                "{}: unsupported per-wheel index version {!r} (want {})".format(root, version, _SUPPORTED_VERSION)
            )
        if root in roots:
            continue
        i = len(roots)
        roots.append(root)
        wheel_indexes.append(index)
        distributions.append(index.get("distribution"))
        for name, root_entries in sorted(index.get("top", {}).items()):
            top.setdefault(name, []).append([i, sorted(root_entries)])
        dist_info = index.get("dist_info")
        if dist_info:
            dists.setdefault(dist_info_key(dist_info), []).append([i, dist_info])
        pth.extend([name, i] for name in index.get("pth", ()))
        for d in index.get("dirs", ()):
            dir_owners.setdefault(d.replace("/", "."), []).append(i)

    merged = {d: owners for d, owners in sorted(dir_owners.items()) if len(owners) > 1}
    sub = {
        d: owners[0] for d, owners in sorted(dir_owners.items()) if len(owners) == 1 and d.rpartition(".")[0] in merged
    }
    result = {
        "version": 1,
        "roots": roots,
        "distributions": distributions,
        "top": dict(sorted(top.items())),
        "dists": dict(sorted(dists.items())),
        "pth": sorted(pth),
        "merged": merged,
        "sub": sub,
        "conflicts": sorted(
            name for name, owners in top.items() if len(owners) > 1 and any(e != name for _, es in owners for e in es)
        ),
    }
    preload = _compute_preload(wheel_indexes)
    if preload:
        result["preload"] = preload
    return result


def _module_name(filename):
    """The module a file in a wheel root provides, per the per-wheel index rules."""
    if filename.endswith(".py"):
        stem = filename[:-3]
    elif filename.endswith(".pyc"):
        stem = filename[:-4]
    else:
        if filename.endswith(".so"):
            base = filename[:-3]
        elif filename.endswith(".pyd"):
            base = filename[:-4]
        else:
            return None
        stem, dot, tag = base.partition(".")
        if dot and (not tag or "." in tag):
            return None
    return stem if stem.isidentifier() else None


def _scan_root(root):
    """Lists a wheel root like the per-wheel index (version 1) describes it."""
    names = []
    dists = []
    pths = []
    with os.scandir(root) as it:
        for e in it:
            n = e.name
            if n.lower().endswith((".dist-info", ".egg-info")):
                dists.append(n)
            elif n.isidentifier():
                if n != "__pycache__" and e.is_dir():
                    names.append((n, n))
            elif n.endswith(".pth"):
                if not e.is_dir():
                    pths.append(n)
            else:
                name = _module_name(n)
                if name and not e.is_dir():
                    names.append((name, n))
    return names, dists, pths


def _walk_dirs(root):
    """Dotted names of a root's package directories, like the per-wheel `dirs`."""
    found = []

    def subdirs(path):
        with os.scandir(path) as it:
            return [e for e in it if e.name.isidentifier() and e.name != "__pycache__" and e.is_dir()]

    def walk(path, dotted):
        found.append(dotted)
        for e in subdirs(path):
            walk(e.path, dotted + "." + e.name)

    for e in subdirs(root):
        walk(e.path, e.name)
    return found


class _JsonContext:
    """Settings for the C JSON scanner, which spares importing json (and re)."""

    strict = True
    object_hook = None
    object_pairs_hook = None
    parse_float = float
    parse_int = int
    parse_constant = None
    memo = {}


def _read_json(path):
    with open(path, "rb") as f:
        text = f.read().decode("utf-8")
    try:
        from _json import make_scanner
    except ImportError:  # pragma: no cover
        make_scanner = None
    if make_scanner is not None:
        try:
            value, _ = make_scanner(_JsonContext)(text.lstrip(), 0)
            return value
        except Exception:  # pragma: no cover
            pass  # Let json produce a proper error.
    import json

    return json.loads(text)


class _Prebuilt:
    """A prebuilt index (merged JSON file or merged per-wheel index dict)."""

    def __init__(self, data_or_path, runfiles_root, source=None):
        if isinstance(data_or_path, dict):
            data = data_or_path
            self.path = source or "<per-wheel indexes>"
        else:
            data = _read_json(data_or_path)
            self.path = data_or_path
        if data.get("version") != 1:
            raise ValueError("unsupported import index version {!r}".format(data.get("version")))
        self.roots = [os.path.join(runfiles_root, r) for r in data["roots"]]
        roots = self.roots
        self.records = {r: ([], [], []) for r in roots}
        for name, owners in data["top"].items():
            for i, entries in owners:
                names = self.records[roots[i]][0]
                for entry in entries:
                    names.append((name, entry))
        for owners in data["dists"].values():
            for i, dist_info in owners:
                self.records[roots[i]][1].append(dist_info)
        for name, i in data["pth"]:
            self.records[roots[i]][2].append(name)
        self.merged = {d: [roots[i] for i in owners] for d, owners in data["merged"].items()}
        self.sub = {d: roots[i] for d, i in data.get("sub", {}).items()}
        self.preload = {pkg: [(roots[i], rel) for i, rel in libs] for pkg, libs in data.get("preload", {}).items()}


def _load_per_wheel_prebuilt(roots, runfiles_root):
    """Loads per-wheel `<wheel>.dist_info/index.json` files adjacent to `roots`."""
    prefix = runfiles_root.rstrip("/") + "/" if runfiles_root else ""
    entries = []
    for root in dict.fromkeys(roots):
        wheel_dir = os.path.dirname(root.rstrip("/"))
        idx_path = wheel_dir + ".dist_info/index.json"
        if not os.path.isfile(idx_path):
            continue
        rel_root = root[len(prefix) :] if prefix and root.startswith(prefix) else root
        entries.append((rel_root, _read_json(idx_path)))
    if not entries:
        return None
    return _Prebuilt(merge_wheel_indexes(entries), runfiles_root)


class _Index:
    """The top-level entries of every wheel root, prebuilt or listed."""

    def __init__(self, roots, prebuilt=None):
        self.roots = []
        self.indexed = []
        self.unscanned = []
        self.top = {}
        self.entries = {}
        self.dist_entries = {}
        self.pth = {}
        self.merged = prebuilt.merged if prebuilt else {}
        self.sub = prebuilt.sub if prebuilt else {}
        self.preload = dict(prebuilt.preload) if prebuilt else {}
        self._parent_dirs = {}
        self._dists_by_name = None

        records = prebuilt.records if prebuilt else {}
        for root in dict.fromkeys(roots):
            record = records.get(root)
            if record is not None:
                self.indexed.append(root)
            else:
                try:
                    record = _scan_root(root)
                except OSError:
                    self.unscanned.append(root)
                    continue
            self.roots.append(root)
            names, dists, pths = record
            for name, entry in names:
                owners = self.top.setdefault(name, [])
                if not owners or owners[-1] != root:
                    owners.append(root)
                self.entries.setdefault((name, root), []).append(entry)
            if dists:
                self.dist_entries[root] = dists
            for name in pths:
                self.pth.setdefault(name, root)
        self.root_set = frozenset(self.roots)

    def merged_dirs(self, name, parents):
        """The `name` directories below `parents`, per the prebuilt index."""
        if not self.merged:
            return None
        parent = name.rpartition(".")[0]
        parent_roots = self.merged.get(parent)
        if parent_roots is None:
            return None
        known = self._parent_dirs.get(parent)
        if known is None:
            parts = parent.split(".")
            known = {os.path.join(r, *parts): r for r in parent_roots}
            self._parent_dirs[parent] = known
        roots = []
        for p in parents:
            root = known.get(p) if isinstance(p, str) else None
            if root is None:
                return None
            roots.append(root)
        owners = self.merged.get(name)
        if not owners:
            owner = self.sub.get(name)
            owners = (owner,) if owner is not None else ()
        if not owners:
            return []
        parts = name.split(".")
        return [os.path.join(r, *parts) for r in roots if r in owners]

    def dists_by_name(self):
        """Normalized distribution name -> [(root, dist-info path), ...]."""
        if self._dists_by_name is None:
            by_name = {}
            for root in self.roots:
                for n in self.dist_entries.get(root, ()):
                    name = n.lower().rpartition(".")[0].partition("-")[0]
                    by_name.setdefault(_normalize_dist_name(name), []).append((root, os.path.join(root, n)))
            self._dists_by_name = by_name
        return self._dists_by_name


def _verify(roots, prebuilt):
    """Compares a prebuilt index with a fresh listing of the roots it covers."""
    problems = []
    covered = [r for r in dict.fromkeys(roots) if r in prebuilt.records]

    def diff(what, root, scanned, indexed):
        scanned, indexed = sorted(scanned), sorted(indexed)
        if scanned != indexed:
            problems.append(
                "{} of {}: only on disk: {}; only in the index: {}".format(
                    what,
                    root,
                    [x for x in scanned if x not in indexed],
                    [x for x in indexed if x not in scanned],
                )
            )

    for root in covered:
        try:
            names, dists, pths = _scan_root(root)
        except OSError as e:
            problems.append("can't list {}: {}".format(root, e))
            continue
        indexed_names, indexed_dists, indexed_pths = prebuilt.records[root]
        diff("top-level entries", root, names, indexed_names)
        dist_info = sorted(d for d in dists if d.endswith(".dist-info") and os.path.isdir(os.path.join(root, d)))[:1]
        diff(".dist-info", root, dist_info, indexed_dists)
        diff(".pth files", root, pths, indexed_pths)

    owners = {}
    for root in covered:
        try:
            for d in _walk_dirs(root):
                owners.setdefault(d, []).append(root)
        except OSError:
            pass
    scanned_merged = {d: rs for d, rs in owners.items() if len(rs) > 1}
    covered_set = set(covered)
    indexed_merged = {}
    for d, rs in prebuilt.merged.items():
        rs = [r for r in rs if r in covered_set]
        if len(rs) > 1:
            indexed_merged[d] = rs
    for d in sorted(set(scanned_merged) | set(indexed_merged)):
        if scanned_merged.get(d) != indexed_merged.get(d):
            problems.append(
                "merged directory {}: on disk in {}, in the index in {}".format(
                    d, scanned_merged.get(d, []), indexed_merged.get(d, [])
                )
            )
    if prebuilt.sub:
        scanned_sub = {d: rs[0] for d, rs in owners.items() if len(rs) == 1 and d.rpartition(".")[0] in scanned_merged}
        indexed_sub = {
            d: r for d, r in prebuilt.sub.items() if r in covered_set and d.rpartition(".")[0] in indexed_merged
        }
        for d in sorted(set(scanned_sub) | set(indexed_sub)):
            if scanned_sub.get(d) != indexed_sub.get(d):
                problems.append(
                    "sub-directory {}: on disk in {!r}, in the index in {!r}".format(
                        d, scanned_sub.get(d), indexed_sub.get(d)
                    )
                )
    return problems


def _spec(fullname, path, loader_class, search_locations=None):
    return spec_from_file_location(
        fullname,
        path,
        loader=loader_class(fullname, path),
        submodule_search_locations=search_locations,
    )


def _single_owner_spec(fullname, root, entries):
    """FileFinder's resolution for one directory whose listing is known."""
    if fullname in entries:
        d = os.path.join(root, fullname)
        for suffix, loader_class in _LOADERS:
            init = os.path.join(d, "__init__" + suffix)
            if os.path.isfile(init):
                return _spec(fullname, init, loader_class, [d])
    for suffix, loader_class in _LOADERS:
        if fullname + suffix in entries:
            return _spec(fullname, os.path.join(root, fullname + suffix), loader_class)
    if fullname in entries:
        spec = _machinery.ModuleSpec(fullname, None, is_package=True)
        spec.submodule_search_locations = [os.path.join(root, fullname)]
        return spec
    return None


def _merged_subdir_spec(fullname, dirs):
    """Resolves a package directory `fullname` whose directories are `dirs`."""
    for d in dirs:
        for suffix, loader_class in _LOADERS:
            init = os.path.join(d, "__init__" + suffix)
            if os.path.isfile(init):
                return _spec(fullname, init, loader_class, [d])
    spec = _machinery.ModuleSpec(fullname, None, is_package=True)
    spec.submodule_search_locations = list(dirs)
    return spec


def _preload_native(fullname, libs):
    """Preloads cross-wheel shared libraries required by `fullname`."""
    import ctypes

    for root, rel in libs:
        path = os.path.join(root, rel)
        try:
            ctypes.CDLL(path)
            if _DEBUG:
                _log("preload", fullname, "->", path)
        except OSError as e:
            if _DEBUG:
                _log("preload failed", fullname, path, e)


def _is_namespace_spec(spec):
    """Whether `spec` is a PEP 420 namespace package spec.

    In Python 3.11+, PathFinder.find_spec sets `spec.loader` to a
    `_NamespaceLoader` instance while leaving `spec.origin` as `None`.
    """
    return spec.origin is None and spec.submodule_search_locations is not None


def _merge(spec, name, parents, dirs=None):
    """Merge `name` like a directory shared by all of `parents`."""
    if spec is None or spec.submodule_search_locations is None:
        return spec
    if _is_namespace_spec(spec):
        if len(spec.submodule_search_locations) > 1:
            _MERGED.add(name)
        return spec
    if dirs is None and _INDEX is not None:
        dirs = _INDEX.merged_dirs(name, parents)
    if dirs is None:
        tail = name.rpartition(".")[2]
        dirs = []
        for p in parents:
            if isinstance(p, str):
                d = os.path.join(p, tail)
                if os.path.isdir(d):
                    dirs.append(d)
    if len(dirs) > 1:
        primary = list(spec.submodule_search_locations)
        spec.submodule_search_locations = primary + [d for d in dirs if d not in primary]
        _MERGED.add(name)
        if _DEBUG:
            _log(
                "merged",
                repr(name),
                "across",
                len(spec.submodule_search_locations),
                "directories",
            )
    return spec


def _split(search_path):
    """Splits `search_path` around the wheel set."""
    global _SPLIT
    key = tuple(search_path)
    cached = _SPLIT
    if cached[0] == key:
        return cached[1], cached[2], cached[3]
    roots = _INDEX.root_set
    pre, post, active = [], [], set()
    for p in key:
        if isinstance(p, str) and p in roots:
            active.add(p)
        elif active:
            post.append(p)
        else:
            pre.append(p)
    active = frozenset(active)
    _SPLIT = (key, pre, post, active)
    return pre, post, active


def _describe(spec):
    if spec is None:
        return "not found"
    if _is_namespace_spec(spec):
        return "namespace package, portions: {}".format(list(spec.submodule_search_locations))
    if spec.submodule_search_locations:
        return "{} (package dirs: {})".format(spec.origin, list(spec.submodule_search_locations))
    return str(spec.origin)


class PathFinder(_machinery.PathFinder):
    """`importlib.machinery.PathFinder` with the wheel set resolved from the index."""

    @classmethod
    def find_spec(cls, fullname, path=None, target=None):
        if path is not None or _INDEX is None:
            parent = fullname.rpartition(".")[0] if _INDEX is not None else ""
            if parent and parent in _MERGED:
                dirs = _INDEX.merged_dirs(fullname, path)
                if dirs:
                    spec = _merged_subdir_spec(fullname, dirs)
                else:
                    spec = super().find_spec(fullname, path, target)
                return _merge(spec, fullname, path, dirs)
            return super().find_spec(fullname, path, target)

        spec = cls._find_top_level(fullname, sys.path, target)
        if spec is not None and _is_namespace_spec(spec) and _NamespacePath is not None:
            spec.submodule_search_locations = _NamespacePath(
                fullname, list(spec.submodule_search_locations), cls._find_top_level
            )
        if spec is not None and fullname in _INDEX.preload:
            _preload_native(fullname, _INDEX.preload.pop(fullname))
        return spec

    @classmethod
    def _find_top_level(cls, fullname, search_path, target=None):
        pre, post, active = _split(search_path)
        portions = []
        for where in ("pre", "wheels", "post"):
            if where == "wheels":
                spec = cls._find_in_wheels(fullname, active, target)
            else:
                entries = pre if where == "pre" else post
                spec = super().find_spec(fullname, entries, target) if entries else None
            if spec is None:
                continue
            if not _is_namespace_spec(spec):
                if portions and spec.submodule_search_locations is not None:
                    locs = list(portions)
                    for loc in spec.submodule_search_locations:
                        if loc not in locs:
                            locs.append(loc)
                    spec.submodule_search_locations = locs
                    _MERGED.add(fullname)
                if _DEBUG:
                    _log("find_spec({!r}) -> {}: {}".format(fullname, where, _describe(spec)))
                return spec
            for portion in spec.submodule_search_locations:
                if portion not in portions:
                    portions.append(portion)
        if portions:
            spec = _machinery.ModuleSpec(fullname, None, is_package=True)
            spec.submodule_search_locations = portions
            if len(portions) > 1:
                _MERGED.add(fullname)
        else:
            spec = None
        if _DEBUG:
            _log("find_spec({!r}) -> {}".format(fullname, _describe(spec)))
        return spec

    @classmethod
    def _find_in_wheels(cls, fullname, active, target):
        owners = _INDEX.top.get(fullname)
        if not owners:
            return None
        if len(active) != len(_INDEX.root_set):
            owners = [r for r in owners if r in active]
            if not owners:
                return None
        if len(owners) == 1:
            spec = _single_owner_spec(fullname, owners[0], _INDEX.entries[(fullname, owners[0])])
            if spec is not None:
                return spec
            return super().find_spec(fullname, owners, target)
        spec = None
        portions = []
        for r in owners:
            s = _single_owner_spec(fullname, r, _INDEX.entries[(fullname, r)])
            if s is None:
                s = super().find_spec(fullname, [r], target)
                if s is None:
                    continue
            if not _is_namespace_spec(s):
                spec = s
                break
            portions.extend(s.submodule_search_locations)
        if spec is None and portions:
            spec = _machinery.ModuleSpec(fullname, None, is_package=True)
            spec.submodule_search_locations = portions
        dirs = [os.path.join(r, fullname) for r in owners if fullname in _INDEX.entries[(fullname, r)]]
        return _merge(spec, fullname, owners, dirs)

    @classmethod
    def find_distributions(cls, context=None):
        """Finds distributions, looking up the wheel roots' from the index."""
        from importlib import metadata

        if context is None:
            context = metadata.DistributionFinder.Context()
        name = context.name
        backport = _backport_metadata_finder_active()
        if backport and not name:
            return
        if _INDEX is None:
            if not backport:
                yield from metadata.MetadataPathFinder.find_distributions(context)
            return
        roots = _INDEX.root_set
        pre, wheel_roots, post = [], {}, []
        for p in context.path:
            if isinstance(p, str) and p in roots:
                wheel_roots.setdefault(p, len(wheel_roots))
            elif wheel_roots:
                post.append(p)
            else:
                pre.append(p)
        if not backport:
            yield from metadata.MetadataPathFinder.find_distributions(
                metadata.DistributionFinder.Context(name=name, path=pre)
            )
        if name:
            prepared = getattr(metadata, "Prepared", None)
            key = prepared(name).normalized if prepared else _normalize_dist_name(name)
            found = sorted(
                (wheel_roots[root], path) for root, path in _INDEX.dists_by_name().get(key, ()) if root in wheel_roots
            )
            paths = [path for _, path in found]
        else:
            paths = [os.path.join(root, n) for root in wheel_roots for n in _INDEX.dist_entries.get(root, ())]
        if paths:
            import pathlib

            dist_cls = _cached_distribution_cls(metadata.PathDistribution)
            for path in paths:
                yield dist_cls(pathlib.Path(path))
        if not backport:
            yield from metadata.MetadataPathFinder.find_distributions(
                metadata.DistributionFinder.Context(name=name, path=post)
            )


def _cached_distribution_cls(base):
    """Subclasses `PathDistribution` to memoize immutable metadata files."""
    cls = _CACHED_DIST_CLS.get(base)
    if cls is None:

        class _PathDistribution(base):
            def read_text(self, filename):
                if filename not in _CACHED_METADATA_FILES:
                    return super().read_text(filename)
                key = (os.fspath(self._path), filename)
                try:
                    return _METADATA_TEXT[key]
                except KeyError:
                    text = super().read_text(filename)
                    _METADATA_TEXT[key] = text
                    return text

        _PathDistribution.__name__ = base.__name__
        _PathDistribution.__qualname__ = base.__qualname__
        cls = _CACHED_DIST_CLS[base] = _PathDistribution
    return cls


def _backport_metadata_finder_active():
    for finder in sys.meta_path:
        module = getattr(type(finder), "__module__", None) or ""
        if module.partition(".")[0] == "importlib_metadata":
            return True
    return False


def install(roots, debug=False, mode="scan", index_path=None, runfiles_root=""):
    """Installs the finder for the given wheel roots."""
    global _DEBUG, _INDEX
    _DEBUG = debug
    if _INDEX is not None:
        if debug:
            _log("already installed")
        return False
    for i, finder in enumerate(sys.meta_path):
        if finder is _machinery.PathFinder:
            break
    else:
        if debug:
            _log("importlib.machinery.PathFinder isn't on sys.meta_path; not installing")
        return False

    if debug:
        import time

        start = time.perf_counter()
    prebuilt = None
    if mode in ("prebuilt", "verify"):
        if index_path:
            try:
                prebuilt = _Prebuilt(index_path, runfiles_root)
            except (OSError, ValueError, LookupError, TypeError) as e:
                if mode == "verify":
                    raise SystemExit("{} verify failed: can't load {}: {}".format(_LOG_PREFIX, index_path, e))
                _log("can't load {} ({}); listing every root".format(index_path, e))
        else:
            try:
                prebuilt = _load_per_wheel_prebuilt(roots, runfiles_root)
            except (OSError, ValueError, LookupError, TypeError) as e:
                if mode == "verify":
                    raise SystemExit("{} verify failed: can't load per-wheel indexes: {}".format(_LOG_PREFIX, e))
                _log("can't load per-wheel indexes ({}); listing every root".format(e))
            if prebuilt is None:
                if mode == "verify":
                    _log("verify: this binary has no prebuilt index; listing every root")
                elif debug:
                    _log("no prebuilt index; listing every root")
    if mode == "verify" and prebuilt is not None:
        problems = _verify(roots, prebuilt)
        if problems:
            _log("the prebuilt index {} doesn't match its roots:".format(prebuilt.path))
            for problem in problems:
                _log("  " + problem)
            raise SystemExit("{} verify failed: {} differences (see above)".format(_LOG_PREFIX, len(problems)))
        if debug:
            _log("verified", prebuilt.path)

    index = _Index(roots, prebuilt)
    if not index.roots:
        if debug:
            _log("no wheel roots could be listed; not installing")
        return False
    _INDEX = index
    sys.meta_path[i] = PathFinder

    if index.pth:
        import site

        known_paths = {os.path.normcase(p) for p in sys.path if isinstance(p, str)}
        for name in sorted(index.pth):
            if not name.startswith("."):
                site.addpackage(index.pth[name], name, known_paths)

    if debug:
        elapsed = (time.perf_counter() - start) * 1000
        multi = sorted(n for n, owners in index.top.items() if len(owners) > 1)
        _log(
            "indexed {} wheel roots ({} from the prebuilt index, {} listed) in "
            "{:.1f} ms: {} top-level names, {} distributions, {} .pth files".format(
                len(index.roots),
                len(index.indexed),
                len(index.roots) - len(index.indexed),
                elapsed,
                len(index.top),
                sum(len(v) for v in index.dist_entries.values()),
                len(index.pth),
            )
        )
        if multi:
            _log("names in several wheel roots:", ", ".join(multi))
        for root in index.unscanned:
            _log("couldn't list", root, "(left to PathFinder)")
    return True


def auto_install():
    """Installs the finder at startup when triggered by pycross_import_index.pth."""
    if os.name == "nt" or _INDEX is not None:
        return False
    default_mode = _DEFAULT_MODE if _DEFAULT_MODE in ("off", "scan", "prebuilt") else "off"
    if default_mode == "off":
        return False
    debug = bool(os.environ.get("RULES_PYTHON_IMPORT_INDEX_DEBUG"))
    mode = os.environ.get("RULES_PYTHON_IMPORT_INDEX") or default_mode
    if mode not in ("off", "scan", "prebuilt", "verify"):
        _log("ignoring unknown RULES_PYTHON_IMPORT_INDEX={!r}".format(mode))
        mode = default_mode
    if mode == "off":
        if debug:
            _log("disabled by RULES_PYTHON_IMPORT_INDEX=off")
        return False

    site_init = sys.modules.get("_bazel_site_init")
    runfiles_root = getattr(site_init, "_RUNFILES_ROOT", "") if site_init else ""
    imports_str = getattr(site_init, "_IMPORTS_STR", "") if site_init else ""
    if runfiles_root and imports_str:
        roots = [
            os.path.join(runfiles_root, rel_path)
            for rel_path in imports_str.split(":")
            if os.path.basename(rel_path.rstrip("/")) == "site-packages"
        ]
    else:
        here = os.path.normcase(os.path.abspath(os.path.dirname(__file__)))
        roots = [
            p
            for p in sys.path
            if isinstance(p, str)
            and os.path.basename(p.rstrip("/")) == "site-packages"
            and os.path.normcase(os.path.abspath(p)) != here
        ]
    if not roots:
        if debug:
            _log("no wheel roots")
        return False

    index_path = None
    if mode in ("prebuilt", "verify") and (mode == "verify" or os.path.isdir(roots[0])):
        candidate = os.path.join(os.path.dirname(__file__), "_bazel_import_index.json")
        if os.path.isfile(candidate):
            index_path = candidate

    return install(
        roots,
        debug=debug,
        mode=mode,
        index_path=index_path,
        runfiles_root=runfiles_root,
    )
