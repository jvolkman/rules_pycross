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
_SUPPORTED_VERSION = 2

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
_PRELOADED = set()
_IN_PRELOAD = False
_ORIG_CTYPES_DLOPEN = None
_IS_MUSL = None
_HOOK_MODULES = frozenset(("_ctypes", "ctypes", "_cffi_backend"))
NATIVE_CONSUMER_FILENAME = ".pycross-native-consumer.json"
NATIVE_PROVIDER_FILENAME = ".pycross-native.json"


def _log(*args):
    print(_LOG_PREFIX, *args, file=sys.stderr, flush=True)


def _normalize_dist_name(name):
    """importlib.metadata's Prepared.normalize()."""
    import re

    return re.sub(r"[-_.]+", "-", name).lower().replace("-", "_")


def _own_origin_dirs(so_dir, entries):
    dirs = set()
    for entry in entries:
        if entry in ("$ORIGIN", "${ORIGIN}"):
            dirs.add(so_dir)
            continue
        for token in ("$ORIGIN/", "${ORIGIN}/"):
            if entry.startswith(token):
                after = entry[len(token) :]
                break
        else:
            continue
        if not after:
            dirs.add(so_dir)
            continue
        norm = posixpath.normpath(posixpath.join(so_dir, after) if so_dir else after)
        if norm == ".":
            dirs.add("")
        elif not norm.startswith(".."):
            dirs.add(norm)
    return frozenset(dirs) if dirs else None


def _is_abi_tagged_ext(filename):
    """Whether `filename` has a Python extension ABI tag (.cpython-*, .abi3*, .pypy*, .graalpy*)."""
    if not filename.endswith(".so"):
        return False
    base = filename[:-3]
    _, dot, tag = base.partition(".")
    if not dot or not tag:
        return False
    return tag.startswith(("cpython-", "abi3", "pypy", "graalpy"))


def _elf_matches_process_class(path):
    """Checks whether `path` is an ELF file matching the current process's 32/64-bit class."""
    try:
        with open(path, "rb") as fh:
            ident = fh.read(5)
    except OSError:
        return False
    if len(ident) < 5:
        return False
    if ident[:4] != b"\x7fELF":
        # Non-ELF file (e.g. a linker script or empty test fixture on disk).
        return True
    expected_class = 2 if sys.maxsize > (1 << 32) else 1
    return ident[4] == expected_class


def _ld_library_path_provides(soname, ld_dirs=None):
    if not soname:
        return False
    if ld_dirs is None:
        if _INDEX is not None:
            ld_dirs = _INDEX._ld_library_path_dirs
        else:
            ld_env = os.environ.get("LD_LIBRARY_PATH", "")
            ld_dirs = tuple(d for d in ld_env.split(":") if d) if ld_env else ()
    if not ld_dirs:
        return False
    base = soname.rpartition("/")[2] if "/" in soname else soname
    for d in ld_dirs:
        cand = os.path.join(d, base)
        if os.path.isfile(cand) and _elf_matches_process_class(cand):
            return True
    return False


def _preload_trigger_keys(wheel_idx, idx, rel_so, merged, sub):
    top = idx.get("top", {})
    first_seg = rel_so.split("/", 1)[0] if "/" in rel_so else rel_so.split(".", 1)[0]
    if first_seg in top or first_seg in idx.get("dirs", ()):
        if merged and first_seg in merged and sub:
            matched = [
                d
                for d, owner in sub.items()
                if owner == wheel_idx
                and (rel_so == d.replace(".", "/") or rel_so.startswith(d.replace(".", "/") + "/"))
            ]
            if matched:
                return matched
            wheel_subs = [d for d, owner in sub.items() if owner == wheel_idx and d.startswith(first_seg + ".")]
            if wheel_subs and "/" not in rel_so[len(first_seg) + 1 :]:
                return [first_seg] + wheel_subs
            if wheel_subs:
                return wheel_subs
        return [first_seg]
    keys = []
    for name in sorted(top):
        if merged and name in merged and sub:
            wheel_subs = [d for d, owner in sub.items() if owner == wheel_idx and d.startswith(name + ".")]
            if wheel_subs:
                keys.extend(wheel_subs)
                continue
        keys.append(name)
    return keys or [first_seg.partition(".")[0]]


def _compute_native(wheel_indexes, merged=None, sub=None, ld_dirs=None):
    if not any(idx.get("native") for idx in wheel_indexes):
        return {}, {}, {}

    own_by_soname_per_wheel = []
    ordered_native_per_wheel = []
    libs_by_dir = {}
    dir_sonames = {}
    by_soname = {}
    meta_by_key = {}
    so_dir_by_key = {}

    for i, idx in enumerate(wheel_indexes):
        own_by_soname = {}
        native = idx.get("native", {})
        ordered_native = sorted(native.items())
        ordered_native_per_wheel.append(ordered_native)
        for rel_so, meta in ordered_native:
            so_dir, _, basename = rel_so.rpartition("/")
            key = (i, rel_so)
            meta_by_key[key] = meta
            so_dir_by_key[key] = so_dir
            soname = meta.get("soname")
            is_ext = _is_abi_tagged_ext(basename)
            first_seg = rel_so.split("/", 1)[0] if "/" in rel_so else ""
            is_shared_lib = bool(soname) or (
                not is_ext and (basename.startswith("lib") or ".so." in basename or first_seg.endswith(".libs"))
            )
            effective_soname = soname or (basename if is_shared_lib else None)
            if effective_soname:
                if basename == effective_soname and (
                    effective_soname not in own_by_soname
                    or own_by_soname[effective_soname][1].rpartition("/")[2] != effective_soname
                ):
                    own_by_soname[effective_soname] = key
                else:
                    own_by_soname.setdefault(effective_soname, key)
                if basename == effective_soname and (
                    effective_soname not in by_soname
                    or by_soname[effective_soname][1].rpartition("/")[2] != effective_soname
                ):
                    by_soname[effective_soname] = key
                else:
                    by_soname.setdefault(effective_soname, key)
                if not is_ext and basename != effective_soname and not basename.endswith(".so"):
                    own_by_soname.setdefault(basename, key)
                    by_soname.setdefault(basename, key)
            if is_shared_lib:
                dedup_name = soname or basename
                seen = dir_sonames.setdefault((i, so_dir), set())
                if dedup_name not in seen:
                    seen.add(dedup_name)
                    libs_by_dir.setdefault(so_dir, []).append(key)
        own_by_soname_per_wheel.append(own_by_soname)

    escaping_cache = {}
    own_rpath_cache = {}
    escaping_by_key = {key: () for key in meta_by_key}
    escaping_sonames_by_key = {}

    for i, idx in enumerate(wheel_indexes):
        for rel_so, esc_info in (idx.get("escaping") or {}).items():
            key = (i, rel_so)
            if key not in meta_by_key:
                continue
            runpath_dirs = esc_info.get("runpath") or ()
            rpath_dirs = esc_info.get("rpath") or ()
            is_runpath = bool(runpath_dirs)
            cand_dirs = tuple(runpath_dirs) if is_runpath else tuple(rpath_dirs)
            if not cand_dirs:
                continue
            esc_key = (i, is_runpath, cand_dirs)
            cached_esc = escaping_cache.get(esc_key)
            if cached_esc is None:
                targets = []
                esc_by_soname = {}
                for cand_dir in cand_dirs:
                    for dep_key in libs_by_dir.get(cand_dir, ()):
                        if dep_key[0] == i or dep_key in targets:
                            continue
                        dep_meta = meta_by_key[dep_key]
                        dep_basename = dep_key[1].rpartition("/")[2]
                        dep_soname = dep_meta.get("soname") or dep_basename
                        if is_runpath and _ld_library_path_provides(dep_soname, ld_dirs):
                            continue
                        targets.append(dep_key)
                        esc_by_soname.setdefault(dep_soname, dep_key)
                        if dep_basename != dep_soname:
                            esc_by_soname.setdefault(dep_basename, dep_key)
                cached_esc = (tuple(targets), esc_by_soname)
                escaping_cache[esc_key] = cached_esc
            escaping_by_key[key] = cached_esc[0]
            escaping_sonames_by_key[key] = cached_esc[1]

    needed_by_key = {}
    for key, meta in meta_by_key.items():
        needed = meta.get("needed")
        if not needed:
            needed_by_key[key] = ()
            continue
        wheel_idx = key[0]
        own_by_soname = own_by_soname_per_wheel[wheel_idx]
        esc_by_soname = escaping_sonames_by_key.get(key)
        runpath = meta.get("runpath")
        rpath = meta.get("rpath")
        is_runpath = bool(runpath)
        active_rpaths = tuple(runpath) if is_runpath else tuple(rpath or ())
        own_reached = None
        if active_rpaths and own_by_soname:
            so_dir = so_dir_by_key[key]
            own_key = (so_dir, active_rpaths)
            if own_key in own_rpath_cache:
                own_reached = own_rpath_cache[own_key]
            else:
                own_reached = _own_origin_dirs(so_dir, active_rpaths)
                own_rpath_cache[own_key] = own_reached
        deps = []
        for needed_name in needed:
            dep_key = None
            own_dep = own_by_soname.get(needed_name)
            if own_dep is not None and own_reached is not None and so_dir_by_key[own_dep] in own_reached:
                if not (is_runpath and _ld_library_path_provides(needed_name, ld_dirs)):
                    dep_key = own_dep
            elif esc_by_soname:
                dep_key = esc_by_soname.get(needed_name)
            if dep_key is not None and dep_key != key and dep_key not in deps:
                deps.append(dep_key)
        needed_by_key[key] = tuple(deps)

    def resolve_closure(seeds, include_escaping=True):
        ordered = []
        visited = set()

        def visit(key):
            if key in visited:
                return
            visited.add(key)
            for dep_key in needed_by_key[key]:
                if dep_key not in visited:
                    visit(dep_key)
            if include_escaping:
                for dep_key in escaping_by_key[key]:
                    if dep_key not in visited:
                        visit(dep_key)
            ordered.append([key[0], key[1]])

        for seed in seeds:
            if seed not in visited:
                visit(seed)
        return ordered

    canonical_shared_keys = set(by_soname.values())
    for own_by_soname in own_by_soname_per_wheel:
        canonical_shared_keys.update(own_by_soname.values())
    trigger_cache = {}
    needed_closure_cache = {}
    pkg_roots = {}
    pkg_roots_sets = {}
    native_deps = {}
    for i, idx in enumerate(wheel_indexes):
        for rel_so, _ in ordered_native_per_wheel[i]:
            key = (i, rel_so)
            esc_targets = escaping_by_key[key]
            if esc_targets:
                so_dir = so_dir_by_key[key]
                trig_cache_key = (i, so_dir if so_dir else rel_so)
                tkeys = trigger_cache.get(trig_cache_key)
                if tkeys is None:
                    tkeys = _preload_trigger_keys(i, idx, rel_so, merged, sub)
                    trigger_cache[trig_cache_key] = tkeys
                for trigger_key in tkeys:
                    seeds = pkg_roots.setdefault(trigger_key, [])
                    seen_seeds = pkg_roots_sets.setdefault(trigger_key, set())
                    for t in esc_targets:
                        if t not in seen_seeds:
                            seen_seeds.add(t)
                            seeds.append(t)
            if key not in canonical_shared_keys:
                continue
            lib_seeds = needed_by_key[key]
            if lib_seeds:
                deps = needed_closure_cache.get(lib_seeds)
                if deps is None:
                    deps = resolve_closure(lib_seeds, include_escaping=False)
                    needed_closure_cache[lib_seeds] = deps
                self_entry = [i, rel_so]
                if self_entry in deps:
                    deps = [d for d in deps if d != self_entry]
                if any(d[0] != i for d in deps):
                    native_deps["{}:{}".format(i, rel_so)] = deps

    preload = {}
    for pkg_key, seeds in sorted(pkg_roots.items()):
        ordered = resolve_closure(seeds, include_escaping=True)
        if ordered:
            preload[pkg_key] = ordered

    sonames = {name: [key[0], key[1]] for name, key in sorted(by_soname.items())}
    return preload, sonames, native_deps


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


def _scan_root_with_native(root):
    """Lists a wheel root like the per-wheel index (version 1) and detects any native dotfile."""
    names = []
    dists = []
    pths = []
    native_file = None
    with os.scandir(root) as it:
        for e in it:
            n = e.name
            if n.startswith("."):
                if n == NATIVE_CONSUMER_FILENAME:
                    native_file = NATIVE_CONSUMER_FILENAME
                elif n == NATIVE_PROVIDER_FILENAME and native_file is None:
                    native_file = NATIVE_PROVIDER_FILENAME
                continue
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
    return names, dists, pths, native_file


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
    array_hook = None
    parse_float = float
    parse_int = int
    parse_constant = None
    memo = {}


try:
    from _json import make_scanner as _make_json_scanner

    _JSON_SCANNER = _make_json_scanner(_JsonContext)
except Exception:  # pragma: no cover
    _JSON_SCANNER = None


def _read_json(path):
    with open(path, "rb") as f:
        text = f.read().decode("utf-8")
    if _JSON_SCANNER is not None:
        try:
            value, _ = _JSON_SCANNER(text.lstrip(), 0)
            _JsonContext.memo.clear()
            return value
        except Exception:  # pragma: no cover
            _JsonContext.memo.clear()
    import json

    return json.loads(text)


class _Index:
    """The top-level entries of every wheel root."""

    def __init__(self, roots, mode="prebuilt"):
        self.roots = []
        self.unscanned = []
        self.top = {}
        self.entries = {}
        self.dist_entries = {}
        self.pth = {}
        self.preload = {}
        self.sonames = {}
        self.native_deps = {}
        self.mode = mode
        self.native_files = {}
        self.consumer_roots = []
        self._wheel_native = None
        self._native_loaded = False
        ld_env = os.environ.get("LD_LIBRARY_PATH", "")
        self._ld_library_path_dirs = tuple(d for d in ld_env.split(":") if d) if ld_env else ()
        self._dists_by_name = None

        for root in dict.fromkeys(roots):
            try:
                names, dists, pths, native_file = _scan_root_with_native(root)
            except OSError:
                self.unscanned.append(root)
                continue
            self.roots.append(root)
            if mode in ("prebuilt", "verify") and native_file is not None:
                self.native_files[root] = os.path.join(root, native_file)
                if native_file == NATIVE_CONSUMER_FILENAME:
                    self.consumer_roots.append(root)
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
        self._norm_roots = tuple((r, os.path.normpath(os.path.abspath(r)).rstrip("/")) for r in self.roots)
        if mode in ("prebuilt", "verify"):
            if self.consumer_roots:
                self.ensure_native_loaded()
            elif not self.native_files:
                self._native_loaded = True

    def ensure_native_loaded(self):
        """Loads native dotfiles to populate `preload`, `sonames`, and `native_deps`."""
        if self._native_loaded:
            return
        self._native_loaded = True
        if not self.native_files or self.mode not in ("prebuilt", "verify"):
            return
        native_roots = []
        wheel_indexes = []
        dir_owners = {}
        for root in self.roots:
            dotfile = self.native_files.get(root)
            if not dotfile:
                continue
            try:
                idx = _read_json(dotfile)
            except (OSError, ValueError, LookupError, TypeError) as e:
                if self.mode == "verify":
                    raise SystemExit("{} verify failed: can't load {}: {}".format(_LOG_PREFIX, dotfile, e))
                if _DEBUG:
                    _log("can't load {} ({})".format(dotfile, e))
                continue
            version = idx.get("version")
            if version != _SUPPORTED_VERSION:
                if self.mode == "verify":
                    raise SystemExit(
                        "{} verify failed: {}: unsupported version {!r}".format(_LOG_PREFIX, dotfile, version)
                    )
                continue
            i = len(native_roots)
            native_roots.append(root)
            wheel_indexes.append(idx)
            for d in idx.get("dirs") or ():
                dir_owners.setdefault(d.replace("/", "."), []).append(i)
        if not wheel_indexes:
            return
        merged = {d: owners for d, owners in sorted(dir_owners.items()) if len(owners) > 1}
        for i, idx in enumerate(wheel_indexes):
            for t in idx.get("top") or ():
                if len(self.top.get(t, ())) > 1 and t not in merged:
                    merged[t] = dir_owners.get(t, [i])
        native_root_set = frozenset(native_roots)
        sub = {}
        for d, owners in sorted(dir_owners.items()):
            if len(owners) == 1 and d.rpartition(".")[0] in merged:
                top_seg = d.partition(".")[0]
                rel_d = d.replace(".", os.sep)
                if not any(
                    r not in native_root_set and os.path.isdir(os.path.join(r, rel_d))
                    for r in self.top.get(top_seg, ())
                ):
                    sub[d] = owners[0]
        preload, sonames, native_deps = _compute_native(wheel_indexes, merged, sub, ld_dirs=self._ld_library_path_dirs)
        self._wheel_native = {native_roots[i]: idx.get("native") or {} for i, idx in enumerate(wheel_indexes)}
        self.preload = {pkg: [(native_roots[i], rel) for i, rel in libs] for pkg, libs in preload.items()}
        self.sonames = {name: (native_roots[i], rel) for name, (i, rel) in sonames.items()}
        self.native_deps = {}
        for k, deps in native_deps.items():
            i_str, _, rel = k.partition(":")
            self.native_deps[(native_roots[int(i_str)], rel)] = [(native_roots[di], drel) for di, drel in deps]

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


def _verify(index):
    """Verifies scanned root entries and native dotfiles against disk."""
    problems = []
    for root in index.roots:
        try:
            names, dists, pths, _ = _scan_root_with_native(root)
        except OSError as e:
            problems.append("can't scan {}: {}".format(root, e))
            continue

        indexed_names = sorted(
            (name, entry)
            for name, owners in index.top.items()
            if root in owners
            for entry in index.entries.get((name, root), ())
        )
        if sorted(names) != indexed_names:
            problems.append(
                "{}: top-level entries mismatch (disk={}, index={})".format(root, sorted(names), indexed_names)
            )
        if sorted(dists) != sorted(index.dist_entries.get(root, ())):
            problems.append(
                "{}: .dist-info mismatch (disk={}, index={})".format(
                    root, sorted(dists), sorted(index.dist_entries.get(root, ()))
                )
            )
        indexed_pths = sorted(name for name, owner in index.pth.items() if owner == root)
        if sorted(pths) != indexed_pths:
            problems.append("{}: .pth mismatch (disk={}, index={})".format(root, sorted(pths), indexed_pths))

        present_dotfiles = [
            fn for fn in (NATIVE_CONSUMER_FILENAME, NATIVE_PROVIDER_FILENAME) if os.path.exists(os.path.join(root, fn))
        ]
        if len(present_dotfiles) > 1:
            problems.append("{}: multiple native dotfiles {}".format(root, present_dotfiles))
            continue
        if not present_dotfiles:
            if root in index.native_files:
                problems.append("{}: indexed native dotfile {} missing on disk".format(root, index.native_files[root]))
            continue

        expected_fn = present_dotfiles[0]
        dotfile_path = os.path.join(root, expected_fn)
        if index.native_files.get(root) != dotfile_path:
            problems.append(
                "{}: native dotfile mismatch (disk={!r}, index={!r})".format(
                    root, dotfile_path, index.native_files.get(root)
                )
            )
            continue
        try:
            expected_dirs = sorted(d.replace(".", "/") for d in _walk_dirs(root))
            data = _read_json(dotfile_path)
        except Exception as e:
            problems.append("{}: can't verify {}: {}".format(root, expected_fn, e))
            continue
        top_names = sorted({name for name, _ in names})
        if data.get("version") != _SUPPORTED_VERSION:
            problems.append("{}: {}: unsupported version {!r}".format(root, expected_fn, data.get("version")))
        if data.get("top") != top_names:
            problems.append(
                "{}: {}: top mismatch (dotfile={}, disk={})".format(root, expected_fn, data.get("top"), top_names)
            )
        if data.get("dirs") != expected_dirs:
            problems.append(
                "{}: {}: dirs mismatch (dotfile={}, disk={})".format(root, expected_fn, data.get("dirs"), expected_dirs)
            )
        native = data.get("native") or {}
        if not native:
            problems.append("{}: {}: empty native table".format(root, expected_fn))
        for rel_so in sorted(native):
            if not os.path.isfile(os.path.join(root, rel_so)):
                problems.append("{}: {}: missing native file {!r}".format(root, expected_fn, rel_so))
        has_escaping = bool(data.get("escaping"))
        if expected_fn == NATIVE_CONSUMER_FILENAME and not has_escaping:
            problems.append("{}: {}: consumer dotfile has no escaping entries".format(root, expected_fn))
        elif expected_fn == NATIVE_PROVIDER_FILENAME and has_escaping:
            problems.append("{}: {}: provider dotfile has escaping entries".format(root, expected_fn))
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


def _is_comment_only_py(path):
    """Returns True if `path` is a `.py` file containing only comments and whitespace."""
    if not path or not path.endswith(".py"):
        return False
    try:
        with open(path, "rb") as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith(b"#"):
                    return False
        return True
    except OSError:
        return False


def _is_musl():
    global _IS_MUSL
    override = os.environ.get("RULES_PYTHON_IMPORT_INDEX_LIBC")
    if override:
        return override.lower() == "musl"
    if _IS_MUSL is not None:
        return _IS_MUSL
    if sys.platform != "linux":
        _IS_MUSL = False
        return False
    try:
        _IS_MUSL = not os.confstr("CS_GNU_LIBC_VERSION")
    except (ValueError, OSError, AttributeError):
        _IS_MUSL = True
    return _IS_MUSL


def _make_stub_elf(rpath, needed_name, ei_class=None, ei_data=None, e_machine=None):
    """Builds a minimal ELF64 ET_DYN stub with DT_RPATH and DT_NEEDED (`PF_R | PF_W`).

    Note: Only 64-bit ELF (`ei_class == 2`) is synthesized; 32-bit ELF returns
    `None` so callers fall back to `_raw_dlopen`.
    """
    import struct

    if ei_class is not None and ei_class != 2:
        return None
    if ei_data not in (1, 2):
        ei_data = 1 if sys.byteorder == "little" else 2
    if e_machine is None:
        e_machine = (
            0xB7 if getattr(os, "uname", lambda: None)() and os.uname().machine in ("aarch64", "arm64") else 0x3E
        )
    endian = "<" if ei_data == 1 else ">"

    dynstr = bytearray(b"\x00")
    needed_off = len(dynstr)
    dynstr.extend(os.fsencode(needed_name) + b"\x00")
    rpath_off = len(dynstr)
    dynstr.extend(os.fsencode(rpath) + b"\x00")
    while len(dynstr) % 8:
        dynstr.append(0)

    ehdr_size = 64
    phdr_size = 56
    phnum = 3
    table_off = ehdr_size + phdr_size * phnum
    dynsym_off = table_off
    dynsym = b"\x00" * 24
    hash_off = dynsym_off + len(dynsym)
    elf_hash = struct.pack(endian + "IIII", 1, 1, 0, 0)
    dynstr_off = hash_off + len(elf_hash)
    dyn_off = dynstr_off + len(dynstr)

    dyn_entries = [
        (1, needed_off),  # DT_NEEDED
        (15, rpath_off),  # DT_RPATH
        (5, dynstr_off),  # DT_STRTAB
        (10, len(dynstr)),  # DT_STRSZ
        (6, dynsym_off),  # DT_SYMTAB
        (11, 24),  # DT_SYMENT
        (4, hash_off),  # DT_HASH
        (0, 0),  # DT_NULL
    ]
    dyn = b"".join(struct.pack(endian + "QQ", tag, val) for tag, val in dyn_entries)
    total_size = dyn_off + len(dyn)

    e_ident = struct.pack("4sBBBBB7s", b"\x7fELF", 2, ei_data, 1, 0, 0, b"\x00" * 7)
    ehdr = e_ident + struct.pack(
        endian + "HHIQQQIHHHHHH",
        3,  # ET_DYN
        e_machine,
        1,
        0,
        ehdr_size,
        0,
        0,
        ehdr_size,
        phdr_size,
        phnum,
        64,
        0,
        0,
    )
    phdr_load = struct.pack(endian + "IIQQQQQQ", 1, 6, 0, 0, 0, total_size, total_size, 0x1000)
    phdr_dyn = struct.pack(endian + "IIQQQQQQ", 2, 6, dyn_off, dyn_off, dyn_off, len(dyn), len(dyn), 8)
    phdr_stack = struct.pack(endian + "IIQQQQQQ", 0x6474E551, 6, 0, 0, 0, 0, 0, 16)
    return ehdr + phdr_load + phdr_dyn + phdr_stack + dynsym + elf_hash + bytes(dynstr) + dyn


def _raw_dlopen(path):
    if _ORIG_CTYPES_DLOPEN is not None:
        return _ORIG_CTYPES_DLOPEN(path)
    import ctypes

    return ctypes.CDLL(path)


def _lookup_native_meta(path):
    if _INDEX is None:
        return None
    matched = _match_wheel_relpath(path)
    if matched is None:
        return None
    root, rel_so = matched
    wheel_native = _INDEX._wheel_native
    if wheel_native:
        return wheel_native.get(root, {}).get(rel_so)
    return None


def _dlopen_musl_stub(path):
    dir_path = os.path.dirname(path)
    basename = os.path.basename(path)
    meta = _lookup_native_meta(path) or {}
    soname = meta.get("soname")
    if soname and soname != basename:
        if os.path.exists(os.path.join(dir_path, soname)):
            needed_name = soname
        else:
            if _DEBUG:
                _log("musl stub skipped for", path, "(missing SONAME file", soname, "in dir)")
            return _raw_dlopen(path)
    else:
        needed_name = basename
    stub = _make_stub_elf(
        dir_path,
        needed_name,
        ei_class=meta.get("ei_class"),
        ei_data=meta.get("ei_data"),
        e_machine=meta.get("e_machine"),
    )
    if stub is None:
        return _raw_dlopen(path)
    memfd_create = getattr(os, "memfd_create", None)
    if memfd_create is not None:
        fd = None
        try:
            mfd_cloexec = getattr(os, "MFD_CLOEXEC", 1)
            mfd_noexec_seal = getattr(os, "MFD_NOEXEC_SEAL", 0x0008)
            try:
                fd = memfd_create("pycross_stub", mfd_cloexec | mfd_noexec_seal)
            except OSError:
                fd = memfd_create("pycross_stub", mfd_cloexec)
            os.write(fd, stub)
            return _raw_dlopen("/proc/self/fd/{}".format(fd))
        except OSError:
            pass
        finally:
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
    import tempfile

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(prefix="pycross_stub_", suffix=".so", delete=False) as tf:
            tf.write(stub)
            tmp_path = tf.name
        return _raw_dlopen(tmp_path)
    except OSError:
        return _raw_dlopen(path)
    finally:
        if tmp_path is not None:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def _load_native_path(path, label=""):
    global _IN_PRELOAD
    if path in _PRELOADED:
        return True
    prev = _IN_PRELOAD
    _IN_PRELOAD = True
    try:
        if _is_musl():
            _dlopen_musl_stub(path)
        else:
            _raw_dlopen(path)
        _PRELOADED.add(path)
        if _DEBUG and label:
            _log("preload", label, "->", path)
        return True
    except OSError as e:
        if _DEBUG and label:
            _log("preload failed", label, path, e)
        return False
    finally:
        _IN_PRELOAD = prev


def _preload_native(fullname, libs):
    """Preloads cross-wheel shared libraries required by `fullname`."""
    for root, rel in libs:
        _load_native_path(os.path.join(root, rel), fullname)


def _match_wheel_relpath(path_str):
    if _INDEX is None:
        return None
    norm = os.path.normpath(os.path.abspath(path_str))
    for r, r_clean in _INDEX._norm_roots:
        prefix = r_clean + "/"
        if norm.startswith(prefix):
            return r, norm[len(prefix) :].replace(os.sep, "/")
    return None


def _strip_leading_dotdot(rel_path):
    norm = posixpath.normpath(rel_path.replace(os.sep, "/"))
    parts = norm.split("/")
    while parts and parts[0] == "..":
        parts.pop(0)
    if parts and parts != ["."]:
        return "/".join(parts)
    return None


def _match_escaped_norm(target_norm, clean_roots):
    for r_clean in clean_roots:
        prefix = r_clean + "/"
        if target_norm.startswith(prefix):
            return target_norm[len(prefix) :].replace(os.sep, "/")
        if os.path.basename(r_clean) == "site-packages":
            parent = os.path.dirname(r_clean)
            parent_prefix = parent + "/"
            if (
                parent
                and target_norm.startswith(parent_prefix)
                and not any(r2 != r_clean and r2.startswith(parent_prefix) for r2 in clean_roots)
            ):
                rel = target_norm[len(parent_prefix) :].replace(os.sep, "/")
                if rel.split("/", 1)[0] in _INDEX.top:
                    return rel
    return None


def _extract_escaped_relpath(path_str):
    if _INDEX is None:
        return None
    abs_raw = os.path.abspath(path_str)
    for r in _INDEX.roots:
        prefix = r.rstrip("/") + "/"
        if abs_raw.startswith(prefix):
            rel = _strip_leading_dotdot(abs_raw[len(prefix) :])
            if rel:
                return rel
    rel = _match_escaped_norm(os.path.normpath(abs_raw), [r_clean for _, r_clean in _INDEX._norm_roots])
    if rel:
        return rel
    real_roots = getattr(_INDEX, "_real_roots", None)
    if real_roots is None:
        real_roots = [os.path.realpath(r).rstrip("/") for r in _INDEX.roots]
        _INDEX._real_roots = real_roots
    try:
        real_norm = os.path.normpath(
            os.path.join(os.path.realpath(os.path.dirname(path_str)), os.path.basename(path_str))
        )
    except OSError:
        return None
    return _match_escaped_norm(real_norm, real_roots)


def _find_owner_for_relpath(rel_so):
    if _INDEX is None or not rel_so:
        return None
    _INDEX.ensure_native_loaded()
    basename = posixpath.basename(rel_so)
    by_name = _INDEX.sonames.get(basename)
    if by_name is not None and by_name[1] == rel_so:
        return by_name
    first_seg = rel_so.split("/", 1)[0]
    for r in _INDEX.top.get(first_seg, ()):
        if os.path.isfile(os.path.join(r, rel_so)):
            return r, rel_so
    return None


def _find_wheel_library(name):
    if _INDEX is None or not name:
        return None
    try:
        s = os.fsdecode(os.fspath(name))
    except TypeError:
        return None
    _INDEX.ensure_native_loaded()
    if not _INDEX.sonames:
        return None
    if s in _INDEX.sonames:
        return _INDEX.sonames[s]
    if s.endswith(".so"):
        prefix = s + "."
        for soname in sorted(_INDEX.sonames):
            if soname.startswith(prefix):
                return _INDEX.sonames[soname]
        return None
    for exact in ("lib" + s + ".so", s + ".so"):
        if exact in _INDEX.sonames:
            return _INDEX.sonames[exact]
    prefixes = ("lib" + s + ".so.", s + ".so.")
    for soname in sorted(_INDEX.sonames):
        if soname.startswith(prefixes):
            return _INDEX.sonames[soname]
    return None


def _prepare_resolved_target(root, rel_so, label="dlopen"):
    deps = _INDEX.native_deps.get((root, rel_so))
    if deps is None:
        canon = _find_wheel_library(rel_so.rpartition("/")[2])
        if canon is not None and canon[0] == root:
            deps = _INDEX.native_deps.get(canon)
    if deps:
        _preload_native(label, deps)
    resolved = os.path.join(root, rel_so)
    if _is_musl():
        _load_native_path(resolved, label)
    return resolved


def _resolve_path_dlopen_arg(name):
    if _IN_PRELOAD or _INDEX is None or not name:
        return name
    try:
        raw = os.fspath(name)
    except TypeError:
        return name
    is_bytes = isinstance(raw, bytes)
    s = os.fsdecode(raw)
    if "/" not in s and (os.sep == "/" or os.sep not in s):
        return name
    if os.path.exists(s):
        matched = _match_wheel_relpath(s)
        if matched is not None and _INDEX._native_loaded:
            _prepare_resolved_target(matched[0], matched[1], "dlopen")
        return name
    rel_so = _extract_escaped_relpath(s)
    if rel_so:
        target = _find_owner_for_relpath(rel_so)
        if target is not None:
            resolved = _prepare_resolved_target(target[0], target[1], "dlopen")
            if _DEBUG:
                _log("dlopen rewrite", s, "->", resolved)
            return os.fsencode(resolved) if is_bytes else resolved
    return name


def _resolve_bare_dlopen_arg(name, allow_short_name=False):
    if _IN_PRELOAD or _INDEX is None or not name:
        return name
    try:
        raw = os.fspath(name)
    except TypeError:
        return name
    is_bytes = isinstance(raw, bytes)
    s = os.fsdecode(raw)
    if "/" in s or (os.sep != "/" and os.sep in s):
        return name
    _INDEX.ensure_native_loaded()
    target = _INDEX.sonames.get(s)
    if target is None and (allow_short_name or s.endswith(".so")):
        target = _find_wheel_library(s)
    if target is not None:
        resolved = _prepare_resolved_target(target[0], target[1], "dlopen")
        if _DEBUG:
            _log("dlopen soname", s, "->", resolved)
        return os.fsencode(resolved) if is_bytes else resolved
    return name


def _hook_ctypes_module(mod):
    global _ORIG_CTYPES_DLOPEN
    dlopen = getattr(mod, "dlopen", None)
    if dlopen is None or getattr(dlopen, "_pycross_wrapped", False):
        return
    _ORIG_CTYPES_DLOPEN = dlopen

    def _wrapped_dlopen(name, *args):
        rewritten = _resolve_path_dlopen_arg(name)
        try:
            return dlopen(rewritten, *args)
        except OSError:
            if rewritten == name:
                fallback = _resolve_bare_dlopen_arg(name)
                if fallback != name:
                    return dlopen(fallback, *args)
            raise

    _wrapped_dlopen._pycross_wrapped = True
    _wrapped_dlopen._pycross_orig = dlopen
    try:
        mod.dlopen = _wrapped_dlopen
    except (AttributeError, TypeError):
        pass
    ctypes_pkg = sys.modules.get("ctypes")
    if ctypes_pkg is not None:
        try:
            ctypes_pkg._dlopen = _wrapped_dlopen
        except (AttributeError, TypeError):
            pass


def _hook_ctypes_pkg(mod):
    _ctypes_mod = sys.modules.get("_ctypes")
    if _ctypes_mod is not None:
        _hook_ctypes_module(_ctypes_mod)
        if getattr(_ctypes_mod.dlopen, "_pycross_wrapped", False):
            try:
                mod._dlopen = _ctypes_mod.dlopen
            except (AttributeError, TypeError):
                pass


def _hook_cffi_backend_module(mod):
    orig_load = getattr(mod, "load_library", None)
    if orig_load is not None and not getattr(orig_load, "_pycross_wrapped", False):

        def _wrapped_load_library(name=None, *args):
            if name is None:
                return orig_load(name, *args)
            rewritten = _resolve_path_dlopen_arg(name)
            try:
                return orig_load(rewritten, *args)
            except OSError:
                if rewritten == name:
                    fallback = _resolve_bare_dlopen_arg(name, allow_short_name=True)
                    if fallback != name:
                        return orig_load(fallback, *args)
                raise

        _wrapped_load_library._pycross_wrapped = True
        try:
            mod.load_library = _wrapped_load_library
        except (AttributeError, TypeError):
            pass

    orig_ffi = getattr(mod, "FFI", None)
    if isinstance(orig_ffi, type) and not getattr(orig_ffi, "_pycross_wrapped", False):
        try:

            class _FFI(orig_ffi):
                _pycross_wrapped = True

                def dlopen(self, name=None, *args, **kwargs):
                    if name is None:
                        return super().dlopen(name, *args, **kwargs)
                    rewritten = _resolve_path_dlopen_arg(name)
                    try:
                        return super().dlopen(rewritten, *args, **kwargs)
                    except OSError:
                        if rewritten == name:
                            fallback = _resolve_bare_dlopen_arg(name, allow_short_name=True)
                            if fallback != name:
                                return super().dlopen(fallback, *args, **kwargs)
                        raise

            _FFI.__name__ = orig_ffi.__name__
            _FFI.__qualname__ = orig_ffi.__qualname__
            mod.FFI = _FFI
        except TypeError:
            pass


def _apply_module_hook(fullname, module):
    if fullname == "_ctypes":
        _hook_ctypes_module(module)
    elif fullname == "ctypes":
        _hook_ctypes_pkg(module)
    elif fullname == "_cffi_backend":
        _hook_cffi_backend_module(module)


def _finalize_spec(fullname, spec):
    if spec is None or _INDEX is None:
        return spec
    if fullname in _HOOK_MODULES:
        loader = getattr(spec, "loader", None)
        if loader is not None and hasattr(loader, "exec_module") and not getattr(loader, "_pycross_wrapped", False):

            class _HookedLoader(type(loader)):
                _pycross_wrapped = True

                def exec_module(self, module):
                    super().exec_module(module)
                    _apply_module_hook(fullname, module)

            try:
                loader.__class__ = _HookedLoader
            except TypeError:
                orig_exec = loader.exec_module

                def _exec(module):
                    orig_exec(module)
                    _apply_module_hook(fullname, module)

                try:
                    loader.exec_module = _exec
                    loader._pycross_wrapped = True
                except AttributeError:
                    pass
    return spec


def _maybe_configure_cuda_env(index):
    if os.environ.get("RULES_PYTHON_IMPORT_INDEX_SET_CUDA_ENV", "").lower() not in (
        "1",
        "true",
        "yes",
        "on",
    ):
        return
    for key in ("nvidia.cuda_nvcc", "nvidia.cu13"):
        found = False
        for root in index.top.get("nvidia", ()):
            cuda_dir = os.path.join(root, *key.split("."))
            if not os.path.isdir(cuda_dir):
                continue
            if "CUDA_HOME" not in os.environ and "CUDA_PATH" not in os.environ:
                os.environ["CUDA_HOME"] = cuda_dir
            bin_dir = os.path.join(cuda_dir, "bin")
            if os.path.isdir(bin_dir):
                cur_path = os.environ.get("PATH", "")
                parts = cur_path.split(os.pathsep) if cur_path else []
                if bin_dir not in parts:
                    os.environ["PATH"] = bin_dir + (os.pathsep + cur_path if cur_path else "")
            found = True
            break
        if found:
            break


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
    if dirs is None:
        tail = name.rpartition(".")[2]
        dirs = []
        for p in parents:
            if isinstance(p, str):
                d = os.path.join(p, tail)
                if os.path.isdir(d):
                    dirs.append(d)
    if len(dirs) > 1:
        if _is_comment_only_py(spec.origin):
            for d in dirs:
                for suffix, loader_class in _LOADERS:
                    init = os.path.join(d, "__init__" + suffix)
                    if init != spec.origin and os.path.isfile(init) and not _is_comment_only_py(init):
                        spec = _spec(name, init, loader_class, [d])
                        break
                else:
                    continue
                break
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
            spec = super().find_spec(fullname, path, target)
            parent = fullname.rpartition(".")[0] if _INDEX is not None else ""
            if parent and parent in _MERGED:
                spec = _merge(spec, fullname, path)
            if _INDEX is not None and spec is not None and fullname in _INDEX.preload:
                _preload_native(fullname, _INDEX.preload.pop(fullname))
            return _finalize_spec(fullname, spec)

        spec = cls._find_top_level(fullname, sys.path, target)
        if spec is not None and _is_namespace_spec(spec) and _NamespacePath is not None:
            spec.submodule_search_locations = _NamespacePath(
                fullname, list(spec.submodule_search_locations), cls._find_top_level
            )
        if spec is not None and fullname in _INDEX.preload:
            _preload_native(fullname, _INDEX.preload.pop(fullname))
        return _finalize_spec(fullname, spec)

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


def install(roots, debug=False, mode="scan"):
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

    index = _Index(roots, mode=mode)
    if not index.roots:
        if debug:
            _log("no wheel roots could be listed; not installing")
        return False
    if mode == "verify":
        problems = _verify(index)
        if problems:
            _log("native wheel dotfiles don't match disk:")
            for problem in problems:
                _log("  " + problem)
            raise SystemExit("{} verify failed: {} differences (see above)".format(_LOG_PREFIX, len(problems)))
        if debug:
            _log("verified {} wheel roots ({} native)".format(len(index.roots), len(index.native_files)))
    _PRELOADED.clear()
    _INDEX = index
    sys.meta_path[i] = PathFinder
    for mod_name in ("_ctypes", "ctypes", "_cffi_backend"):
        mod = sys.modules.get(mod_name)
        if mod is not None:
            _apply_module_hook(mod_name, mod)
    _maybe_configure_cuda_env(index)

    if index.pth:
        import site

        before_pth = set(sys.modules)
        known_paths = {os.path.normcase(p) for p in sys.path if isinstance(p, str)}
        for name in sorted(index.pth):
            if not name.startswith("."):
                site.addpackage(index.pth[name], name, known_paths)
        for mod_name in sorted(set(sys.modules) - before_pth, key=lambda s: (s.count("."), s)):
            mod = sys.modules.get(mod_name)
            mod_path = getattr(mod, "__path__", None)
            if mod is None or mod_path is None or getattr(mod, "__file__", None) is not None:
                continue
            if "." in mod_name:
                parent_mod = sys.modules.get(mod_name.rpartition(".")[0])
                parent_path = getattr(parent_mod, "__path__", None) if parent_mod is not None else None
                spec = PathFinder.find_spec(mod_name, parent_path) if parent_path is not None else None
            else:
                spec = PathFinder._find_top_level(mod_name, sys.path)
            if spec is not None and spec.submodule_search_locations is not None:
                merged_locs = list(mod_path)
                for loc in spec.submodule_search_locations:
                    if loc not in merged_locs:
                        merged_locs.append(loc)
                mod.__path__ = merged_locs
                if len(merged_locs) > 1:
                    _MERGED.add(mod_name)

    if debug:
        elapsed = (time.perf_counter() - start) * 1000
        multi = sorted(n for n, owners in index.top.items() if len(owners) > 1)
        _log(
            "indexed {} wheel roots ({} native, {} consumers, native_loaded={}) in "
            "{:.1f} ms: {} top-level names, {} distributions, {} .pth files".format(
                len(index.roots),
                len(index.native_files),
                len(index.consumer_roots),
                index._native_loaded,
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

    return install(
        roots,
        debug=debug,
        mode=mode,
    )
