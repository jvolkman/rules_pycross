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
"""Tests for the import index finder and merger (pycross/private/tools/import_index.py)."""

import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from pycross.private.tools import elf_tools
from pycross.private.tools import import_index

_FINDER_DIR = os.path.dirname(os.path.abspath(import_index.__file__))

_EXTEND_PATH = "__path__ = __import__('pkgutil').extend_path(__path__, __name__)\n"

# Runs in a fresh interpreter: python -S -E -s -c _PROBE <mode> <config json>
_PROBE = r"""
import glob, importlib, json, os, sys

mode, cfg = sys.argv[1], json.loads(sys.argv[2])
if mode == "merged":
    import site

    sys.path.append(cfg["merged"])
    site.addsitedir(cfg["merged"])
else:
    sys.path.extend(cfg["roots"])
sys.path.append(cfg["fp_root"])
if mode == "finder":
    sys.path.insert(0, cfg["finder_dir"])
    import import_index

    sys.path.pop(0)
    real_scandir = os.scandir
    if cfg.get("forbid_scandir"):
        def _no_scandir(*args, **kwargs):
            raise AssertionError("os.scandir{!r} while installing".format(args))

        os.scandir = _no_scandir
    try:
        installed = import_index.install(
            cfg["roots"],
            debug=cfg.get("debug", False),
            mode=cfg.get("index_mode", "scan"),
            index_path=cfg.get("index"),
            runfiles_root=cfg.get("runfiles_root", ""),
        )
    finally:
        os.scandir = real_scandir

out = {}
bases = cfg["roots"] + [cfg["merged"], cfg["fp_root"]] + cfg.get("extra_bases", [])


def where(module):
    f = module.__file__
    if f is None:
        return "namespace"
    for base in bases:
        if f.startswith(base + os.sep):
            return os.path.relpath(f, base)
    return f


isdir_calls = [0]
root_listdir_calls = [0]
real_isdir = os.path.isdir
real_listdir = os.listdir
root_set = set(cfg["roots"])


def _counting_isdir(path):
    isdir_calls[0] += 1
    return real_isdir(path)


def _counting_listdir(path="."):
    if path in root_set:
        root_listdir_calls[0] += 1
    return real_listdir(path)


os.path.isdir = _counting_isdir
os.listdir = _counting_listdir
for name in cfg["modules"]:
    try:
        out[name] = where(importlib.import_module(name))
    except ImportError as e:
        out[name] = "ImportError: " + str(e)
os.path.isdir = real_isdir
os.listdir = real_listdir

import importlib.metadata as md

import colorsys
import xmlrpc

out["colorsys is stdlib"] = not hasattr(colorsys, "SHADOW")
out["xmlrpc is stdlib"] = not hasattr(xmlrpc, "SHADOW")
import enum

out["enum is stdlib"] = hasattr(enum, "IntFlag") and not hasattr(enum, "SHADOW")
out[".pth import line ran"] = getattr(sys, "_pthpkg_ran", False)
out["torch-style nvidia glob"] = all(
    any(glob.glob(os.path.join(p, "nvidia", c, "lib", "lib*.so.*")) for p in sys.path)
    for c in ("cublas", "cudnn", "nccl")
)


def version(name):
    try:
        return md.version(name)
    except md.PackageNotFoundError:
        return "PackageNotFoundError"


out["version(nvidia-cudnn-cu12)"] = version("nvidia-cudnn-cu12")
out["version(Azure.Core) (unnormalized name)"] = version("Azure.Core")
out["version(not-installed)"] = version("not-installed")
names = sorted(d.metadata["Name"] for d in md.distributions())
out["distributions"] = names
out["distributions unique"] = len(names) == len(set(names))
eps = md.entry_points()
out["entry point groups"] = sorted(eps.groups if hasattr(eps, "groups") else eps)

for step in cfg.get("then", []):
    exec(step)
if mode == "finder":
    out["_installed"] = installed
    out["_indexed"] = len(import_index._INDEX.indexed) if import_index._INDEX else 0
    out["_isdir_calls"] = isdir_calls[0]
    out["_root_listdir_calls"] = root_listdir_calls[0]
    out["_meta_path"] = [
        getattr(f, "__module__", "") + "." + getattr(f, "__name__", type(f).__name__)
        for f in sys.meta_path
    ]
    out["_roots_on_sys_path"] = all(r in sys.path for r in cfg["roots"])
print(json.dumps(out))
"""

_MODULES = [
    "requests",
    "six",
    "nvidia",
    "nvidia.cublas",
    "nvidia.cudnn",
    "nvidia.nccl",
    "azure.core.tracing.ext.opentelemetry_span",
    "google.protobuf",
    "google.api",
    "backports.tarfile",
    "backports.entry_points_selectable",
    "extramod",
    "app",
    "dup",
    "nsonly.sub",
]


def _write(path, content=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)


_EXTENSION_MODULE_RE = re.compile(r"^([^.]+)(?:\.[^.]+)?\.(?:so|pyd)$")


def _module_name(filename):
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


def _wheel_index(root):
    """A per-wheel index (version 1), as rules_pycross's PycrossWheelInstall writes it."""
    top, pth, dirs = {}, [], []
    dist_info = None

    def walk(rel):
        dirs.append(rel)
        for e in sorted(os.scandir(os.path.join(root, rel)), key=lambda e: e.name):
            if e.is_dir() and e.name.isidentifier() and e.name != "__pycache__":
                walk(rel + "/" + e.name)

    for e in sorted(os.scandir(root), key=lambda e: e.name):
        if e.is_dir():
            if e.name.endswith(".dist-info"):
                dist_info = dist_info or e.name
            elif e.name.isidentifier() and e.name != "__pycache__":
                top.setdefault(e.name, []).append(e.name)
                walk(e.name)
        elif e.name.endswith(".pth"):
            pth.append(e.name)
        else:
            mod = _module_name(e.name)
            if mod:
                top.setdefault(mod, []).append(e.name)
    distribution = {"name": None, "version": None}
    if dist_info:
        with open(os.path.join(root, dist_info, "METADATA")) as f:
            for line in f:
                key, _, value = line.partition(":")
                if key.lower() in distribution:
                    distribution[key.lower()] = value.strip()
    return {
        "version": 1,
        "distribution": distribution,
        "dist_info": dist_info,
        "top": {k: sorted(v) for k, v in sorted(top.items())},
        "pth": sorted(pth),
        "dirs": sorted(dirs),
        "namespaces": {},
    }


class ImportIndexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="import_index_", dir=os.environ.get("TEST_TMPDIR"))
        cls.roots = {}

        def wheel(name, version, files, dist_name=None):
            root = os.path.join(cls.tmp, "wheels", name, "site-packages")
            for rel, content in files.items():
                _write(os.path.join(root, rel), content)
            dist_name = dist_name or name
            di = os.path.join(root, "{}-{}.dist-info".format(dist_name.replace("-", "_"), version))
            _write(
                os.path.join(di, "METADATA"),
                "Metadata-Version: 2.1\nName: {}\nVersion: {}\n".format(dist_name, version),
            )
            cls.roots[name] = root
            return root

        wheel("requests", "2.32.3", {"requests/__init__.py": ""})
        wheel("six", "1.16.0", {"six.py": ""})
        for c in ("cublas", "cudnn", "nccl"):
            wheel(
                "nvidia_{}_cu12".format(c),
                "12.0",
                {
                    "nvidia/__init__.py": "",
                    "nvidia/{}/__init__.py".format(c): "",
                    "nvidia/{}/lib/lib{}.so.12".format(c, c): "",
                },
                dist_name="nvidia-{}-cu12".format(c),
            )
        wheel(
            "azure_core",
            "1.30.0",
            {
                "azure/core/__init__.py": "",
                "azure/core/tracing/__init__.py": "",
                "azure/core/tracing/ext/__init__.py": "",
            },
            dist_name="azure-core",
        )
        wheel(
            "azure_core_tracing_opentelemetry",
            "1.0.0b11",
            {"azure/core/tracing/ext/opentelemetry_span/__init__.py": ""},
            dist_name="azure-core-tracing-opentelemetry",
        )
        wheel("protobuf", "5.28.0", {"google/protobuf/__init__.py": ""})
        wheel("googleapis_common_protos", "1.65.0", {"google/api/__init__.py": ""})
        wheel(
            "backports_tarfile",
            "1.2.0",
            {
                "backports/__init__.py": _EXTEND_PATH,
                "backports/tarfile/__init__.py": "",
            },
        )
        wheel(
            "backports_entry_points_selectable",
            "1.3.0",
            {
                "backports/__init__.py": _EXTEND_PATH,
                "backports/entry_points_selectable/__init__.py": "",
            },
        )
        wheel(
            "shadows",
            "1.0",
            {
                "enum/__init__.py": "SHADOW = True\n",
                "colorsys.py": "SHADOW = True\n",
                "xmlrpc/__init__.py": "SHADOW = True\n",
            },
        )
        wheel(
            "pthpkg",
            "1.0",
            {
                "pthpkg.pth": "extra_dir\nimport sys; sys._pthpkg_ran = True\n",
                "extra_dir/extramod.py": "",
            },
        )
        wheel("dup", "1.0", {"dup/__init__.py": "", "dup.py": ""})
        wheel("nsonly", "1.0", {"nsonly/sub/__init__.py": ""})
        _write(
            os.path.join(cls.roots["six"], "six-1.16.0.dist-info", "entry_points.txt"),
            "[console_scripts]\nsix-tool = six:main\n",
        )

        cls.fp_root = os.path.join(cls.tmp, "runfiles", "_main")
        _write(os.path.join(cls.fp_root, "app", "__init__.py"))

        cls.merged = os.path.join(cls.tmp, "merged", "site-packages")
        for root in cls.roots.values():
            shutil.copytree(root, cls.merged, dirs_exist_ok=True)

        cls.results = {mode: cls.probe(mode) for mode in ("plain", "merged", "finder")}

    _counter = itertools.count()

    @classmethod
    def write_index(cls, names=None, tamper=None):
        entries = [
            (os.path.relpath(root, cls.tmp), _wheel_index(root))
            for name, root in cls.roots.items()
            if names is None or name in names
        ]
        merged = import_index.merge_wheel_indexes(entries)
        if tamper:
            tamper(merged)
        path = os.path.join(cls.tmp, "index{}.json".format(next(cls._counter)))
        with open(path, "w") as f:
            json.dump(merged, f)
        return path

    @classmethod
    def config(cls, **kwargs):
        cfg = {
            "roots": list(cls.roots.values()),
            "merged": cls.merged,
            "fp_root": cls.fp_root,
            "modules": _MODULES,
            "finder_dir": _FINDER_DIR,
        }
        cfg.update(kwargs)
        return cfg

    @classmethod
    def run_probe(cls, mode, cfg, env=None):
        return subprocess.run(
            [sys.executable, "-S", "-E", "-s", "-c", _PROBE, mode, json.dumps(cfg)],
            capture_output=True,
            text=True,
            env=env,
        )

    @classmethod
    def probe(cls, mode, **kwargs):
        p = cls.run_probe(mode, cls.config(**kwargs))
        if p.returncode:
            raise AssertionError("{} probe failed:\n{}".format(mode, p.stderr))
        return json.loads(p.stdout)

    def check(self, key, expected=None):
        merged = self.results["merged"][key]
        finder = self.results["finder"][key]
        self.assertEqual(
            finder,
            merged,
            "{!r}: finder differs from the pip-merged layout".format(key),
        )
        if expected is not None:
            self.assertEqual(finder, expected)
        return self.results["plain"][key]

    def test_finder_is_installed(self):
        finder = self.results["finder"]
        self.assertTrue(finder["_installed"])
        self.assertIn("import_index.PathFinder", finder["_meta_path"])
        self.assertNotIn("_frozen_importlib_external.PathFinder", finder["_meta_path"])
        self.assertTrue(finder["_roots_on_sys_path"])

    def test_matches_pip_merged_layout(self):
        merged = self.results["merged"]
        finder = {k: v for k, v in self.results["finder"].items() if not k.startswith("_")}
        self.assertEqual(finder, merged)

    def test_split_regular_package(self):
        plain = self.check("nvidia.cudnn", "nvidia/cudnn/__init__.py")
        self.assertTrue(plain.startswith("ImportError"), plain)
        self.check("nvidia.cublas", "nvidia/cublas/__init__.py")
        self.check("nvidia.nccl", "nvidia/nccl/__init__.py")

    def test_plugin_under_another_wheels_regular_package(self):
        name = "azure.core.tracing.ext.opentelemetry_span"
        plain = self.check(name, "azure/core/tracing/ext/opentelemetry_span/__init__.py")
        self.assertTrue(plain.startswith("ImportError"), plain)

    def test_pep420_namespace(self):
        self.check("google.protobuf", "google/protobuf/__init__.py")
        self.check("google.api", "google/api/__init__.py")
        self.check("nsonly.sub", "nsonly/sub/__init__.py")

    def test_first_party_shared_namespace_with_and_without_legacy_init(self):
        fp_ns = os.path.join(self.tmp, "fp_ns")
        _write(os.path.join(fp_ns, "azure", "fp_mod.py"), "FP = 1\n")
        try:
            # 1. Pure PEP 420 namespace in first-party root (both in pre and post).
            finder = self.probe(
                "finder",
                fp_root=fp_ns,
                modules=[
                    "azure.fp_mod",
                    "azure.core.tracing.ext.opentelemetry_span",
                ],
                then=[
                    "sys.path.insert(0, cfg['fp_root'])",
                    "import importlib",
                    "out['azure.fp_mod_pre'] = where(importlib.import_module('azure.fp_mod'))",
                    "out['azure.span_pre'] = where(importlib.import_module('azure.core.tracing.ext.opentelemetry_span'))",
                ],
            )
            self.assertEqual(finder["azure.fp_mod"], "azure/fp_mod.py")
            self.assertEqual(
                finder["azure.core.tracing.ext.opentelemetry_span"],
                "azure/core/tracing/ext/opentelemetry_span/__init__.py",
            )

            # 2. With Bazel legacy_create_init synthesizing azure/__init__.py in fp_root (post).
            _write(os.path.join(fp_ns, "azure", "__init__.py"), "")
            finder_legacy = self.probe(
                "finder",
                fp_root=fp_ns,
                modules=[
                    "azure.fp_mod",
                    "azure.core.tracing.ext.opentelemetry_span",
                ],
            )
            self.assertEqual(finder_legacy["azure.fp_mod"], "azure/fp_mod.py")
            self.assertEqual(
                finder_legacy["azure.core.tracing.ext.opentelemetry_span"],
                "azure/core/tracing/ext/opentelemetry_span/__init__.py",
            )
        finally:
            shutil.rmtree(fp_ns, ignore_errors=True)

    def test_pkgutil_namespace(self):
        self.check("backports.tarfile", "backports/tarfile/__init__.py")
        self.check(
            "backports.entry_points_selectable",
            "backports/entry_points_selectable/__init__.py",
        )

    def test_pth_files(self):
        plain = self.check(".pth import line ran", True)
        self.assertFalse(plain)
        self.check("extramod", "extra_dir/extramod.py")

    def test_stdlib_not_shadowed(self):
        self.check("enum is stdlib", True)
        self.check("colorsys is stdlib", True)
        self.check("xmlrpc is stdlib", True)

    def test_package_beats_module(self):
        self.check("dup", "dup/__init__.py")

    def test_sys_path_glob(self):
        self.check("torch-style nvidia glob", True)

    def test_metadata(self):
        self.check("version(nvidia-cudnn-cu12)", "12.0")
        self.check(
            "version(Azure.Core) (unnormalized name)",
            "1.30.0" if sys.version_info >= (3, 10) else "PackageNotFoundError",
        )
        self.check("version(not-installed)", "PackageNotFoundError")
        self.check("distributions unique", True)
        self.check("distributions")
        self.assertEqual(len(self.results["finder"]["distributions"]), len(self.roots))
        self.check("entry point groups", ["console_scripts"])

    def oracle_keys(self, result):
        return {k: v for k, v in result.items() if not k.startswith("_")}

    def probe_index(self, mode, index, **kwargs):
        return self.probe(
            "finder",
            index_mode=mode,
            index=index,
            runfiles_root=self.tmp,
            **kwargs,
        )

    def test_prebuilt_matches_pip_merged_layout(self):
        finder = self.probe_index("prebuilt", self.write_index(), forbid_scandir=True)
        self.assertTrue(finder["_installed"])
        self.assertEqual(finder["_indexed"], len(self.roots))
        self.assertEqual(self.oracle_keys(finder), self.results["merged"])
        self.assertEqual(finder["_isdir_calls"], 0)
        self.assertEqual(finder["_root_listdir_calls"], 0)

    def test_per_wheel_prebuilt_fallback_without_merged_file(self):
        # Split-file hybrid (`index_path=None`, `mode="prebuilt"`):
        # `_scan_root_with_native` scans each wheel root via `os.scandir`, ignores
        # dotfiles as top-level modules or `.pth` files, and records any
        # `.pycross-native.json` / `.pycross-native-consumer.json` dotfiles.
        dotfile_paths = []
        for name, root in self.roots.items():
            if name.startswith("nvidia_"):
                dot_path = os.path.join(root, import_index.NATIVE_PROVIDER_FILENAME)
                _write(
                    dot_path,
                    json.dumps(
                        {
                            "version": 2,
                            "top": ["nvidia"],
                            "dirs": ["nvidia", "nvidia/" + name.split("_")[1], "nvidia/" + name.split("_")[1] + "/lib"],
                            "native": {},
                        }
                    ),
                )
                dotfile_paths.append(dot_path)
        try:
            finder = self.probe_index("prebuilt", None)
            self.assertTrue(finder["_installed"])
            self.assertEqual(finder["_indexed"], len(self.roots))
            self.assertEqual(self.oracle_keys(finder), self.results["merged"])
            self.assertEqual(finder["_root_listdir_calls"], 0)
        finally:
            for p in dotfile_paths:
                if os.path.exists(p):
                    os.unlink(p)

    def test_split_file_hybrid_provider_lazy_vs_consumer_eager_and_verify(self):
        with tempfile.TemporaryDirectory() as tmp:
            cublas_root = os.path.join(tmp, "cublas", "site-packages")
            cudnn_root = os.path.join(tmp, "cudnn", "site-packages")
            pure_root = os.path.join(tmp, "pure", "site-packages")

            cublas_lt_so = os.path.join(cublas_root, "nvidia", "cublas", "lib", "libcublasLt.so.12")
            cublas_so = os.path.join(cublas_root, "nvidia", "cublas", "lib", "libcublas.so.12")
            cudnn_so = os.path.join(cudnn_root, "nvidia", "cudnn", "lib", "libcudnn.so.9")

            os.makedirs(os.path.dirname(cublas_so), exist_ok=True)
            with open(cublas_lt_so, "wb") as fh:
                fh.write(import_index._make_stub_elf("$ORIGIN", "libc.so.6", soname="libcublasLt.so.12"))
            with open(cublas_so, "wb") as fh:
                fh.write(import_index._make_stub_elf("$ORIGIN", "libcublasLt.so.12", soname="libcublas.so.12"))
            _write(os.path.join(cublas_root, "nvidia", "cublas", "__init__.py"), "")

            os.makedirs(os.path.dirname(cudnn_so), exist_ok=True)
            with open(cudnn_so, "wb") as fh:
                fh.write(
                    import_index._make_stub_elf(
                        "$ORIGIN/../../cublas/lib",
                        "libcublas.so.12",
                        soname="libcudnn.so.9",
                    )
                )
            _write(os.path.join(cudnn_root, "nvidia", "cudnn", "__init__.py"), "")
            _write(os.path.join(pure_root, "purepkg", "__init__.py"), "")

            cublas_dot = os.path.join(cublas_root, import_index.NATIVE_PROVIDER_FILENAME)
            cudnn_dot = os.path.join(cudnn_root, import_index.NATIVE_CONSUMER_FILENAME)
            e_machine = 62
            cublas_meta = {
                "version": 2,
                "top": ["nvidia"],
                "dirs": ["nvidia", "nvidia/cublas", "nvidia/cublas/lib"],
                "native": {
                    "nvidia/cublas/lib/libcublas.so.12": {
                        "soname": "libcublas.so.12",
                        "needed": ["libcublasLt.so.12"],
                        "rpath": ["$ORIGIN"],
                        "runpath": [],
                        "ei_class": 2,
                        "ei_data": 1,
                        "e_machine": e_machine,
                    },
                    "nvidia/cublas/lib/libcublasLt.so.12": {
                        "soname": "libcublasLt.so.12",
                        "needed": ["libc.so.6"],
                        "rpath": ["$ORIGIN"],
                        "runpath": [],
                        "ei_class": 2,
                        "ei_data": 1,
                        "e_machine": e_machine,
                    },
                },
            }
            cudnn_meta = {
                "version": 2,
                "top": ["nvidia"],
                "dirs": ["nvidia", "nvidia/cudnn", "nvidia/cudnn/lib"],
                "native": {
                    "nvidia/cudnn/lib/libcudnn.so.9": {
                        "soname": "libcudnn.so.9",
                        "needed": ["libcublas.so.12"],
                        "rpath": ["$ORIGIN/../../cublas/lib"],
                        "runpath": [],
                        "ei_class": 2,
                        "ei_data": 1,
                        "e_machine": e_machine,
                    },
                },
                "escaping": {
                    "nvidia/cudnn/lib/libcudnn.so.9": {
                        "rpath": ["nvidia/cublas/lib", "cublas/lib"],
                        "runpath": [],
                    },
                },
            }
            _write(cublas_dot, json.dumps(cublas_meta))
            _write(cudnn_dot, json.dumps(cudnn_meta))

            prev_index = import_index._INDEX
            prev_meta = list(sys.meta_path)
            try:
                # 1. Provider-only roots ([cublas_root, pure_root]): 0 JSON files read at startup!
                import_index._INDEX = None
                with mock.patch.object(import_index, "_read_json", wraps=import_index._read_json) as spy_json:
                    self.assertTrue(
                        import_index.install(
                            [cublas_root, pure_root],
                            mode="prebuilt",
                            index_path=None,
                            runfiles_root=tmp,
                        )
                    )
                    self.assertEqual(spy_json.call_count, 0)
                    self.assertFalse(import_index._INDEX._native_loaded)
                    self.assertEqual(len(import_index._INDEX.native_files), 1)
                    self.assertEqual(len(import_index._INDEX.consumer_roots), 0)

                    # Bare dlopen that succeeds on the host does NOT trigger lazy JSON loading.
                    class FakeCtypesHostOk:
                        @staticmethod
                        def dlopen(name, *args):
                            if name == "libc.so.6":
                                return ("host", name)
                            if isinstance(name, str) and not os.path.exists(name):
                                raise OSError(name)
                            return ("wheel", name)

                    import_index._hook_ctypes_module(FakeCtypesHostOk)
                    self.assertEqual(FakeCtypesHostOk.dlopen("libc.so.6"), ("host", "libc.so.6"))
                    self.assertEqual(spy_json.call_count, 0)
                    self.assertFalse(import_index._INDEX._native_loaded)

                    # Bare SONAME fallback for "libcublas.so.12" after dlopen miss lazily loads `.pycross-native.json`.
                    with mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: p):
                        self.assertEqual(FakeCtypesHostOk.dlopen("libcublas.so.12"), ("wheel", cublas_so))
                    self.assertEqual(spy_json.call_count, 1)
                    self.assertTrue(import_index._INDEX._native_loaded)

                # 2. Consumer wheel present ([cublas_root, cudnn_root, pure_root]):
                # Eagerly loads both native dotfiles at startup and populates preload table.
                import_index._INDEX = None
                sys.meta_path[:] = prev_meta
                import_index._PRELOADED.clear()
                preloaded = []
                with (
                    mock.patch.object(import_index, "_read_json", wraps=import_index._read_json) as spy_json,
                    mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: preloaded.append(p)),
                ):
                    self.assertTrue(
                        import_index.install(
                            [cublas_root, cudnn_root, pure_root],
                            mode="prebuilt",
                            index_path=None,
                            runfiles_root=tmp,
                        )
                    )
                    self.assertEqual(spy_json.call_count, 2)
                    self.assertTrue(import_index._INDEX._native_loaded)
                    self.assertEqual(
                        list(import_index._INDEX.preload.get("nvidia.cudnn", ())),
                        [
                            (cublas_root, "nvidia/cublas/lib/libcublasLt.so.12"),
                            (cublas_root, "nvidia/cublas/lib/libcublas.so.12"),
                        ],
                    )
                    import_index.PathFinder.find_spec("nvidia.cudnn", [os.path.join(cudnn_root, "nvidia")])
                    self.assertEqual(preloaded, [cublas_lt_so, cublas_so])

                # 3. `verify` mode (`_verify_hybrid`) passes when dotfiles match on-disk ELF files.
                import_index._INDEX = None
                sys.meta_path[:] = prev_meta
                with mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: p):
                    self.assertTrue(
                        import_index.install(
                            [cublas_root, cudnn_root, pure_root],
                            mode="verify",
                            index_path=None,
                            runfiles_root=tmp,
                        )
                    )

                # 4. `verify` mode raises SystemExit when `dirs` in dotfile does not match disk.
                bad_dirs_meta = dict(cudnn_meta, dirs=["nvidia", "nvidia/wrong_dir"])
                _write(cudnn_dot, json.dumps(bad_dirs_meta))
                try:
                    import_index._INDEX = None
                    sys.meta_path[:] = prev_meta
                    with (
                        mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: p),
                        self.assertRaises(SystemExit),
                    ):
                        import_index.install(
                            [cublas_root, cudnn_root, pure_root],
                            mode="verify",
                            index_path=None,
                            runfiles_root=tmp,
                        )
                finally:
                    _write(cudnn_dot, json.dumps(cudnn_meta))

                # 5. `verify` mode raises SystemExit when a consumer wheel is misclassified as provider.
                os.unlink(cudnn_dot)
                wrong_dot = os.path.join(cudnn_root, import_index.NATIVE_PROVIDER_FILENAME)
                _write(wrong_dot, json.dumps(cudnn_meta))
                try:
                    import_index._INDEX = None
                    sys.meta_path[:] = prev_meta
                    with (
                        mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: p),
                        self.assertRaises(SystemExit),
                    ):
                        import_index.install(
                            [cublas_root, cudnn_root, pure_root],
                            mode="verify",
                            index_path=None,
                            runfiles_root=tmp,
                        )
                finally:
                    if os.path.exists(wrong_dot):
                        os.unlink(wrong_dot)
                    _write(cudnn_dot, json.dumps(cudnn_meta))

                # 6. `verify` mode raises SystemExit when a pure-Python wheel has an unexpected dotfile.
                pure_dot = os.path.join(pure_root, import_index.NATIVE_PROVIDER_FILENAME)
                _write(pure_dot, json.dumps({"version": 2, "top": ["purepkg"], "dirs": ["purepkg"], "native": {}}))
                try:
                    import_index._INDEX = None
                    sys.meta_path[:] = prev_meta
                    with (
                        mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: p),
                        self.assertRaises(SystemExit),
                    ):
                        import_index.install(
                            [cublas_root, cudnn_root, pure_root],
                            mode="verify",
                            index_path=None,
                            runfiles_root=tmp,
                        )
                finally:
                    if os.path.exists(pure_dot):
                        os.unlink(pure_dot)
            finally:
                import_index._INDEX = prev_index
                import_index._PRELOADED.clear()
                sys.meta_path[:] = prev_meta

    def test_merge_preload_and_finder_preloads_on_import(self):
        def wheel(**fields):
            return dict(
                {"version": 1, "top": {}, "pth": [], "dirs": [], "dist_info": None},
                **fields,
            )

        merged = import_index.merge_wheel_indexes(
            [
                (
                    "cublas/site-packages",
                    wheel(
                        top={"nvidia": ["nvidia"]},
                        dirs=["nvidia", "nvidia/cublas", "nvidia/cublas/lib"],
                        native={
                            "nvidia/cublas/lib/libcublas.so.12": {
                                "soname": "libcublas.so.12",
                                "needed": ["libcublasLt.so.12"],
                                "rpath": [],
                                "runpath": ["$ORIGIN"],
                            },
                            "nvidia/cublas/lib/libcublasLt.so.12": {
                                "soname": "libcublasLt.so.12",
                                "needed": [],
                                "rpath": [],
                                "runpath": [],
                            },
                        },
                    ),
                ),
                (
                    "cudnn/site-packages",
                    wheel(
                        top={"nvidia": ["nvidia"]},
                        dirs=["nvidia", "nvidia/cudnn", "nvidia/cudnn/lib"],
                        native={
                            "nvidia/cudnn/lib/libcudnn.so.9": {
                                "soname": "libcudnn.so.9",
                                "needed": ["libcublas.so.12"],
                                "rpath": [],
                                "runpath": ["$ORIGIN/../../cublas/lib"],
                            },
                        },
                        escaping={
                            "nvidia/cudnn/lib/libcudnn.so.9": {
                                "rpath": [],
                                "runpath": ["nvidia/cublas/lib"],
                            },
                        },
                    ),
                ),
                (
                    "tf/site-packages",
                    wheel(
                        top={"tf": ["tf"]},
                        dirs=["tf", "tf/python"],
                        native={
                            "tf/python/_pywrap.so": {
                                "soname": None,
                                "needed": ["libcudnn.so.9", "libtf_internal.so"],
                                "rpath": [],
                                "runpath": [
                                    "$ORIGIN",
                                    "$ORIGIN/../../nvidia/cudnn/lib",
                                ],
                            },
                            "tf/python/libtf_internal.so": {
                                "soname": "libtf_internal.so",
                                "needed": [],
                                "rpath": [],
                                "runpath": [],
                            },
                        },
                        escaping={
                            "tf/python/_pywrap.so": {
                                "rpath": [],
                                "runpath": ["nvidia/cudnn/lib"],
                            },
                        },
                    ),
                ),
            ]
        )
        self.assertEqual(
            merged["preload"]["tf"],
            [
                [0, "nvidia/cublas/lib/libcublasLt.so.12"],
                [0, "nvidia/cublas/lib/libcublas.so.12"],
                [1, "nvidia/cudnn/lib/libcudnn.so.9"],
            ],
        )
        self.assertEqual(
            merged["preload"]["nvidia.cudnn"],
            [
                [0, "nvidia/cublas/lib/libcublasLt.so.12"],
                [0, "nvidia/cublas/lib/libcublas.so.12"],
            ],
        )

    def test_no_rpath_dt_needed_recorded_in_sonames_not_eager_preload(self):
        def wheel(**fields):
            return dict(
                {"version": 1, "top": {}, "pth": [], "dirs": [], "dist_info": None},
                **fields,
            )

        entries = [
            (
                "cublas/site-packages",
                wheel(
                    top={"nvidia": ["nvidia"]},
                    dirs=["nvidia", "nvidia/cublas", "nvidia/cublas/lib"],
                    native={
                        # Both symlink and versioned file share DT_SONAME; canonical
                        # symlink should win in `sonames`.
                        "nvidia/cublas/lib/libcublas.so": {
                            "soname": "libcublas.so.12",
                            "needed": [],
                            "rpath": [],
                            "runpath": [],
                        },
                        "nvidia/cublas/lib/libcublas.so.12": {
                            "soname": "libcublas.so.12",
                            "needed": [],
                            "rpath": [],
                            "runpath": [],
                        },
                        "nvidia/cublas/lib/libcublas.so.12.8": {
                            "soname": "libcublas.so.12",
                            "needed": [],
                            "rpath": [],
                            "runpath": [],
                        },
                        # Library without DT_SONAME should fall back to basename,
                        # whereas ABI-tagged Python extension must not.
                        "nvidia/cublas/lib/libnosoname.so": {
                            "soname": None,
                            "needed": [],
                            "rpath": [],
                            "runpath": [],
                        },
                        "nvidia/cublas/_ext.cpython-312-x86_64-linux-gnu.so": {
                            "soname": None,
                            "needed": [],
                            "rpath": [],
                            "runpath": [],
                        },
                    },
                ),
            ),
            (
                "ort/site-packages",
                wheel(
                    top={"onnxruntime": ["onnxruntime"]},
                    dirs=["onnxruntime", "onnxruntime/capi"],
                    native={
                        # No escaping RPATH/RUNPATH, only DT_NEEDED on SONAMEs
                        # from another wheel, plus a .libs/ sibling directory.
                        "onnxruntime.libs/libort_bundled.so.1": {
                            "soname": "libort_bundled.so.1",
                            "needed": ["libcublas.so.12", "libnosoname.so"],
                            "rpath": [],
                            "runpath": [],
                        },
                    },
                ),
            ),
        ]
        merged = import_index.merge_wheel_indexes(entries)
        # Unsatisfied DT_NEEDED without an escaping RPATH is NOT eagerly preloaded;
        # it is resolved lazily via `sonames` if the dynamic linker fails at load time.
        self.assertNotIn("preload", merged)
        self.assertNotIn("native_deps", merged)
        self.assertEqual(
            merged["sonames"]["libcublas.so.12"],
            [0, "nvidia/cublas/lib/libcublas.so.12"],
        )
        self.assertEqual(
            merged["sonames"]["libnosoname.so"],
            [0, "nvidia/cublas/lib/libnosoname.so"],
        )
        self.assertEqual(
            merged["sonames"]["libort_bundled.so.1"],
            [1, "onnxruntime.libs/libort_bundled.so.1"],
        )
        self.assertNotIn("_ext.cpython-312-x86_64-linux-gnu.so", merged["sonames"])

    def test_stub_elf_header_and_dynstr(self):
        self.assertIsNone(import_index._make_stub_elf("/tmp/wheel/lib", "libcublas.so.12", ei_class=1))
        stub_bytes = import_index._make_stub_elf(
            "/tmp/wheel/lib",
            "libcublas.so.12",
            soname="libstub.so.1",
            ei_class=2,
            ei_data=1,
            e_machine=62,
        )
        self.assertIsNotNone(stub_bytes)
        self.assertTrue(stub_bytes.startswith(b"\x7fELF\x02\x01"))
        self.assertIn(b"libcublas.so.12\x00", stub_bytes)
        self.assertIn(b"/tmp/wheel/lib\x00", stub_bytes)

    def test_runtime_dlopen_and_cffi(self):
        with tempfile.TemporaryDirectory() as tmp:
            cublas_root = os.path.join(tmp, "cublas", "site-packages")
            cudnn_root = os.path.join(tmp, "cudnn", "site-packages")
            torch_root = os.path.join(tmp, "torch", "site-packages")
            nvcc_root = os.path.join(tmp, "nvcc", "site-packages")

            cublas_lt_so = os.path.join(cublas_root, "nvidia", "cublas", "lib", "libcublasLt.so.12")
            cublas_so = os.path.join(cublas_root, "nvidia", "cublas", "lib", "libcublas.so.12")
            cudnn_so = os.path.join(cudnn_root, "nvidia", "cudnn", "lib", "libcudnn.so.9")
            torch_init = os.path.join(torch_root, "torch", "__init__.py")
            ptxas_bin = os.path.join(nvcc_root, "nvidia", "cuda_nvcc", "bin", "ptxas")

            _write(cublas_lt_so, "")
            _write(cublas_so, "")
            _write(cudnn_so, "")
            _write(torch_init, "")
            _write(os.path.join(nvcc_root, "nvidia", "cuda_nvcc", "__init__.py"), "")
            _write(ptxas_bin, "")

            def wheel_meta(**fields):
                return dict(
                    {"version": 1, "top": {}, "pth": [], "dirs": [], "dist_info": None},
                    **fields,
                )

            merged = import_index.merge_wheel_indexes(
                [
                    (
                        "cublas/site-packages",
                        wheel_meta(
                            top={"nvidia": ["nvidia"]},
                            dirs=["nvidia", "nvidia/cublas", "nvidia/cublas/lib"],
                            native={
                                "nvidia/cublas/lib/libcublasLt.so.12": {
                                    "soname": "libcublasLt.so.12",
                                    "needed": [],
                                    "rpath": [],
                                    "runpath": [],
                                },
                                "nvidia/cublas/lib/libcublas.so.12": {
                                    "soname": "libcublas.so.12",
                                    "needed": ["libcublasLt.so.12"],
                                    "rpath": [],
                                    "runpath": ["$ORIGIN"],
                                },
                            },
                        ),
                    ),
                    (
                        "cudnn/site-packages",
                        wheel_meta(
                            top={"nvidia": ["nvidia"]},
                            dirs=["nvidia", "nvidia/cudnn", "nvidia/cudnn/lib"],
                            native={
                                "nvidia/cudnn/lib/libcudnn.so.9": {
                                    "soname": "libcudnn.so.9",
                                    "needed": ["libcublas.so.12"],
                                    "rpath": [],
                                    "runpath": ["$ORIGIN/../../cublas/lib"],
                                },
                            },
                            escaping={
                                "nvidia/cudnn/lib/libcudnn.so.9": {
                                    "rpath": [],
                                    "runpath": ["nvidia/cublas/lib"],
                                },
                            },
                        ),
                    ),
                    (
                        "torch/site-packages",
                        wheel_meta(
                            top={"torch": ["torch"]},
                            dirs=["torch"],
                        ),
                    ),
                    (
                        "nvcc/site-packages",
                        wheel_meta(
                            top={"nvidia": ["nvidia"]},
                            dirs=["nvidia", "nvidia/cuda_nvcc"],
                        ),
                    ),
                ]
            )
            idx_file = os.path.join(tmp, "_bazel_import_index.json")
            _write(idx_file, json.dumps(merged))

            roots = [cublas_root, cudnn_root, torch_root, nvcc_root]
            preloaded_calls = []

            def fake_raw_dlopen(path):
                preloaded_calls.append(path)
                return path

            prev_index = import_index._INDEX
            prev_meta = list(sys.meta_path)
            try:
                import_index._INDEX = None
                with (
                    mock.patch.object(import_index, "_raw_dlopen", side_effect=fake_raw_dlopen),
                    mock.patch.dict(
                        os.environ,
                        {"RULES_PYTHON_IMPORT_INDEX_SET_CUDA_ENV": "1", "PATH": "/usr/bin"},
                        clear=False,
                    ),
                ):
                    os.environ.pop("CUDA_HOME", None)
                    os.environ.pop("CUDA_PATH", None)
                    self.assertTrue(
                        import_index.install(
                            roots,
                            mode="prebuilt",
                            index_path=idx_file,
                            runfiles_root=tmp,
                        )
                    )
                    # Item 7: Opt-in CUDA_HOME and PATH setup from nvidia.cuda_nvcc.
                    expected_cuda_home = os.path.join(nvcc_root, "nvidia", "cuda_nvcc")
                    self.assertEqual(os.environ.get("CUDA_HOME"), expected_cuda_home)
                    self.assertTrue(os.environ["PATH"].startswith(os.path.join(expected_cuda_home, "bin") + os.pathsep))

                    # Item 5a: Escaped relative path from torch/__init__.py -> cudnn wheel,
                    # plus transitive preload of libcublasLt.so.12 and libcublas.so.12.
                    escaped = os.path.join(torch_root, "torch", "..", "nvidia", "cudnn", "lib", "libcudnn.so.9")
                    resolved = import_index._resolve_dlopen_arg(escaped)
                    self.assertEqual(resolved, cudnn_so)
                    self.assertEqual(preloaded_calls, [cublas_lt_so, cublas_so])

                    # Item 5a: Bare SONAME resolution.
                    preloaded_calls.clear()
                    import_index._PRELOADED.clear()
                    self.assertEqual(import_index._resolve_dlopen_arg("libcudnn.so.9"), cudnn_so)
                    self.assertEqual(preloaded_calls, [cublas_lt_so, cublas_so])

                    # Item 5b: _cffi_backend wrapper (load_library and FFI.dlopen).
                    class FakeFFI:
                        def dlopen(self, name=None, flags=0):
                            if name is not None and not os.path.exists(name):
                                raise OSError(name)
                            return (name, flags)

                    class FakeCffiBackend:
                        FFI = FakeFFI

                        @staticmethod
                        def load_library(name=None, flags=0):
                            if name is not None and not os.path.exists(name):
                                raise OSError(name)
                            return (name, flags)

                    import_index._hook_cffi_backend_module(FakeCffiBackend)
                    self.assertEqual(FakeCffiBackend.load_library("cublas", 2), (cublas_so, 2))
                    self.assertEqual(FakeCffiBackend.FFI().dlopen("libcudnn.so.9", 1), (cudnn_so, 1))
            finally:
                import_index._INDEX = prev_index
                import_index._PRELOADED.clear()
                sys.meta_path[:] = prev_meta

    def test_original_first_bare_dlopen_and_unrelated_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            wheel_a = os.path.join(tmp, "wheel_a", "site-packages")
            wheel_b = os.path.join(tmp, "wheel_b", "site-packages")

            cudart_so = os.path.join(wheel_a, "nvidia", "cuda_runtime", "lib", "libcudart.so.12")
            cublas_so = os.path.join(wheel_b, "nvidia", "cublas", "lib", "libcublas.so.12")

            for p in (cudart_so, cublas_so):
                _write(p, "")

            def wheel_meta(**fields):
                return dict(
                    {"version": 1, "top": {}, "pth": [], "dirs": [], "dist_info": None},
                    **fields,
                )

            merged = import_index.merge_wheel_indexes(
                [
                    (
                        "wheel_a/site-packages",
                        wheel_meta(
                            top={"nvidia": ["nvidia"]},
                            dirs=["nvidia", "nvidia/cuda_runtime", "nvidia/cuda_runtime/lib"],
                            native={
                                "nvidia/cuda_runtime/lib/libcudart.so.12": {
                                    "soname": "libcudart.so.12",
                                    "needed": ["libc.so.6"],
                                    "rpath": [],
                                    "runpath": ["$ORIGIN"],
                                },
                            },
                        ),
                    ),
                    (
                        "wheel_b/site-packages",
                        wheel_meta(
                            top={"nvidia": ["nvidia"]},
                            dirs=["nvidia", "nvidia/cublas", "nvidia/cublas/lib"],
                            native={
                                "nvidia/cublas/lib/libcublas.so.12": {
                                    "soname": "libcublas.so.12",
                                    "needed": ["libcudart.so.12"],
                                    "rpath": [],
                                    "runpath": ["$ORIGIN"],
                                },
                            },
                        ),
                    ),
                ]
            )
            self.assertIn("libcudart.so.12", merged.get("sonames", {}))
            self.assertIn("libcublas.so.12", merged.get("sonames", {}))
            self.assertNotIn("preload", merged)

            idx_file = os.path.join(tmp, "_bazel_import_index.json")
            _write(idx_file, json.dumps(merged))
            roots = [wheel_a, wheel_b]
            prev_index = import_index._INDEX
            prev_meta = list(sys.meta_path)
            try:
                import_index._INDEX = None
                with mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: p):
                    self.assertTrue(
                        import_index.install(
                            roots,
                            mode="prebuilt",
                            index_path=idx_file,
                            runfiles_root=tmp,
                        )
                    )

                    # (a) Bare-name dlopen / cffi tries original first:
                    # if the original call succeeds for a bare name, it is NOT redirected to the wheel.
                    dlopen_calls = []

                    class FakeCtypesMod:
                        @staticmethod
                        def dlopen(name, *args):
                            dlopen_calls.append(name)
                            if name == "libcublas.so.12":
                                return ("host_hit", name)
                            if isinstance(name, str) and not os.path.exists(name):
                                raise OSError(name)
                            return ("loaded", name)

                    import_index._hook_ctypes_module(FakeCtypesMod)
                    # Host hit on bare "libcublas.so.12" -> not redirected to wheel's cublas_so.
                    self.assertEqual(FakeCtypesMod.dlopen("libcublas.so.12"), ("host_hit", "libcublas.so.12"))
                    self.assertEqual(dlopen_calls, ["libcublas.so.12"])
                    # Host miss on bare "libcudart.so.12" -> falls back to wheel's cudart_so.
                    dlopen_calls.clear()
                    self.assertEqual(FakeCtypesMod.dlopen("libcudart.so.12"), ("loaded", cudart_so))
                    self.assertEqual(dlopen_calls, ["libcudart.so.12", cudart_so])

                    # Same original-first behavior for _cffi_backend:
                    class FakeFFIHostFirst:
                        def dlopen(self, name=None, flags=0):
                            if name == "cublas":
                                return ("host_ffi", name, flags)
                            if name is not None and not os.path.exists(name):
                                raise OSError(name)
                            return ("wheel_ffi", name, flags)

                    class FakeCffiHostFirst:
                        FFI = FakeFFIHostFirst

                        @staticmethod
                        def load_library(name=None, flags=0):
                            if name == "cublas":
                                return ("host_load", name, flags)
                            if name is not None and not os.path.exists(name):
                                raise OSError(name)
                            return ("wheel_load", name, flags)

                    import_index._hook_cffi_backend_module(FakeCffiHostFirst)
                    self.assertEqual(FakeCffiHostFirst.load_library("cublas", 1), ("host_load", "cublas", 1))
                    self.assertEqual(FakeCffiHostFirst.load_library("cudart", 1), ("wheel_load", cudart_so, 1))
                    self.assertEqual(FakeCffiHostFirst.FFI().dlopen("cublas", 2), ("host_ffi", "cublas", 2))
                    self.assertEqual(FakeCffiHostFirst.FFI().dlopen("cudart", 2), ("wheel_ffi", cudart_so, 2))

                    # (b) Unrelated nonexistent /site-packages/ path is NOT redirected and does zero isfile probes.
                    unrelated = "/other/venv/lib/python3.11/site-packages/nvidia/cublas/lib/libcublas.so.12"
                    with mock.patch.object(import_index.os.path, "isfile", wraps=os.path.isfile) as spy_isfile:
                        self.assertIsNone(import_index._extract_escaped_relpath(unrelated))
                        self.assertEqual(import_index._resolve_path_dlopen_arg(unrelated), unrelated)
                        self.assertEqual(spy_isfile.call_count, 0)
            finally:
                import_index._INDEX = prev_index
                import_index._PRELOADED.clear()
                sys.meta_path[:] = prev_meta

    def test_musl_stub_uses_dotfile_metadata_without_reading_target_so(self):
        with tempfile.TemporaryDirectory() as tmp:
            w0 = os.path.join(tmp, "wheel_a", "site-packages")
            lib_dir = os.path.join(w0, "pkg", "lib")
            os.makedirs(lib_dir, exist_ok=True)
            real_file = os.path.join(lib_dir, "libfoo.so.1.2.3")
            soname_file = os.path.join(lib_dir, "libfoo.so.1")
            lib32_file = os.path.join(lib_dir, "libfoo32.so.1")
            _write(os.path.join(w0, "pkg", "__init__.py"), "")
            dotfile = os.path.join(w0, import_index.NATIVE_PROVIDER_FILENAME)
            _write(
                dotfile,
                json.dumps(
                    {
                        "version": 2,
                        "top": ["pkg"],
                        "dirs": ["pkg", "pkg/lib"],
                        "native": {
                            "pkg/lib/libfoo.so.1.2.3": {
                                "soname": "libfoo.so.1",
                                "needed": ["libc.so.6"],
                                "rpath": ["$ORIGIN"],
                                "runpath": [],
                                "ei_class": 2,
                                "ei_data": 1,
                                "e_machine": 62,
                            },
                            "pkg/lib/libfoo32.so.1": {
                                "soname": "libfoo32.so.1",
                                "needed": ["libc.so.6"],
                                "rpath": ["$ORIGIN"],
                                "runpath": [],
                                "ei_class": 1,
                                "ei_data": 1,
                                "e_machine": 3,
                            },
                        },
                    }
                ),
            )

            prev_index = import_index._INDEX
            try:
                import_index._INDEX = import_index._Index([w0], mode="prebuilt")
                import_index._INDEX.ensure_native_loaded()

                # Notice real_file does not even exist on disk: _dlopen_musl_stub never opens it!
                # Case 1: libfoo.so.1 does NOT exist in lib_dir -> _dlopen_musl_stub skips stub creation
                # and falls back directly to _raw_dlopen(real_file).
                with (
                    mock.patch.object(import_index, "_make_stub_elf", wraps=import_index._make_stub_elf) as spy_stub,
                    mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: ("raw", p)) as spy_raw,
                ):
                    res = import_index._dlopen_musl_stub(real_file)
                    self.assertEqual(res, ("raw", real_file))
                    self.assertEqual(spy_stub.call_count, 0)
                    self.assertEqual(spy_raw.call_count, 1)

                # Case 2: libfoo.so.1 DOES exist in lib_dir -> _dlopen_musl_stub builds a stub with
                # DT_NEEDED = "libfoo.so.1" and (ei_class, ei_data, e_machine) from the dotfile.
                _write(soname_file, "")
                with (
                    mock.patch.object(import_index, "_make_stub_elf", wraps=import_index._make_stub_elf) as spy_stub,
                    mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: ("stub_loaded", p)),
                ):
                    res = import_index._dlopen_musl_stub(real_file)
                    self.assertEqual(res[0], "stub_loaded")
                    spy_stub.assert_called_once_with(
                        lib_dir,
                        "libfoo.so.1",
                        ei_class=2,
                        ei_data=1,
                        e_machine=62,
                    )

                # Case 3: 32-bit library (ei_class=1 in dotfile) -> _make_stub_elf returns None
                # and _dlopen_musl_stub falls back to _raw_dlopen(lib32_file).
                with mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: ("raw32", p)) as spy_raw32:
                    res32 = import_index._dlopen_musl_stub(lib32_file)
                    self.assertEqual(res32, ("raw32", lib32_file))
                    self.assertEqual(spy_raw32.call_count, 1)
            finally:
                import_index._INDEX = prev_index

    def test_unnormalized_wheel_roots_and_intra_wheel_duplicate_sonames(self):
        with tempfile.TemporaryDirectory() as tmp:
            rf = os.path.join(tmp, ".", "bazel-bin", "pkg", "bin.runfiles")
            w0 = os.path.join(rf, "_lock", "numpy@2.1.3", "site-packages")
            w1 = os.path.join(rf, "_lock", "scipy@1.16.1", "site-packages")
            ext_so = os.path.join(
                os.path.normpath(w0),
                "numpy",
                "_core",
                "_multiarray_umath.cpython-313-x86_64-linux-gnu.so",
            )
            _write(ext_so, "ELF")

            idx0 = {
                "version": 1,
                "distribution": {"name": "numpy", "version": "2.1.3"},
                "dist_info": "numpy-2.1.3.dist-info",
                "top": {"numpy": ["numpy"], "numpy.libs": ["numpy.libs"]},
                "pth": [],
                "pth_paths": [],
                "dirs": ["numpy", "numpy/_core", "numpy.libs"],
                "namespaces": {},
                "modules": {},
                "native": {
                    "numpy.libs/libgfortran-040039e1-0352e75f.so.5.0.0": {
                        "soname": "libgfortran-040039e1-0352e75f.so.5.0.0",
                        "needed": ["libquadmath-96973f99-934c22de.so.0.0.0", "libc.so.6"],
                        "rpath": ["$ORIGIN"],
                        "runpath": [],
                    },
                    "numpy.libs/libquadmath-96973f99-934c22de.so.0.0.0": {
                        "soname": "libquadmath-96973f99-934c22de.so.0.0.0",
                        "needed": ["libc.so.6"],
                        "rpath": [],
                        "runpath": [],
                    },
                    "numpy/_core/_multiarray_umath.cpython-313-x86_64-linux-gnu.so": {
                        "soname": None,
                        "needed": ["libscipy_openblas64_-ff651d7f.so", "libc.so.6"],
                        "rpath": ["$ORIGIN/../../numpy.libs"],
                        "runpath": [],
                    },
                    "numpy.libs/libscipy_openblas64_-ff651d7f.so": {
                        "soname": "libscipy_openblas64_-ff651d7f.so",
                        "needed": ["libgfortran-040039e1-0352e75f.so.5.0.0", "libc.so.6"],
                        "rpath": ["$ORIGIN"],
                        "runpath": [],
                    },
                },
            }
            idx1 = {
                "version": 1,
                "distribution": {"name": "scipy", "version": "1.16.1"},
                "dist_info": "scipy-1.16.1.dist-info",
                "top": {"scipy": ["scipy"], "scipy.libs": ["scipy.libs"]},
                "pth": [],
                "pth_paths": [],
                "dirs": ["scipy", "scipy.libs"],
                "namespaces": {},
                "modules": {},
                "native": {
                    "scipy.libs/libgfortran-040039e1-0352e75f.so.5.0.0": {
                        "soname": "libgfortran-040039e1-0352e75f.so.5.0.0",
                        "needed": ["libquadmath-96973f99-934c22de.so.0.0.0", "libc.so.6"],
                        "rpath": ["$ORIGIN"],
                        "runpath": [],
                    },
                    "scipy.libs/libquadmath-96973f99-934c22de.so.0.0.0": {
                        "soname": "libquadmath-96973f99-934c22de.so.0.0.0",
                        "needed": ["libc.so.6"],
                        "rpath": [],
                        "runpath": [],
                    },
                    "scipy.libs/libscipy_openblas-68440149.so": {
                        "soname": "libscipy_openblas-68440149.so",
                        "needed": ["libgfortran-040039e1-0352e75f.so.5.0.0", "libc.so.6"],
                        "rpath": ["$ORIGIN"],
                        "runpath": [],
                    },
                },
            }

            merged = import_index.merge_wheel_indexes(
                [
                    ("_lock/numpy@2.1.3/site-packages", idx0),
                    ("_lock/scipy@1.16.1/site-packages", idx1),
                ]
            )
            # scipy.libs/libscipy_openblas-68440149.so resolves libgfortran to its OWN wheel's copy
            # (with $ORIGIN RPATH), so neither preload nor cross-wheel native_deps is emitted.
            self.assertEqual(merged.get("preload", {}), {})
            self.assertEqual(merged.get("native_deps", {}), {})

            prev_index = import_index._INDEX
            try:
                pb = import_index._Prebuilt(merged, rf)
                import_index._INDEX = import_index._Index([w0, w1], pb, rf)
                # Even though w0 contains `/./` in its path, _match_wheel_relpath matches the
                # normalized extension path.
                self.assertEqual(
                    import_index._match_wheel_relpath(ext_so),
                    (w0, "numpy/_core/_multiarray_umath.cpython-313-x86_64-linux-gnu.so"),
                )
            finally:
                import_index._INDEX = prev_index

    def test_nspkg_pth_reconciliation_and_comment_only_init_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            w_ff = os.path.join(tmp, "functions-framework", "site-packages")
            w_gcf = os.path.join(tmp, "google-cloud-functions", "site-packages")

            # functions-framework ships a setuptools *-nspkg.pth for google and google.cloud,
            # plus comment-only __init__.py files under google/cloud/functions{_v1}/.
            _write(
                os.path.join(w_ff, "functions_framework-3.10.2-py3.12-nspkg.pth"),
                "import sys, types, os;p = os.path.join(sys._getframe(1).f_locals['sitedir'], *('ff_google',));"
                "importlib = __import__('importlib.util');__import__('importlib.machinery');"
                "m = sys.modules.setdefault('ff_google', importlib.util.module_from_spec("
                "importlib.machinery.PathFinder.find_spec('ff_google', [os.path.dirname(p)])));"
                "m = m or sys.modules.setdefault('ff_google', types.ModuleType('ff_google'));"
                "mp = (m or []) and m.__dict__.setdefault('__path__',[]);(p not in mp) and mp.append(p)\n"
                "import sys, types, os;p = os.path.join(sys._getframe(1).f_locals['sitedir'], *('ff_google', 'cloud'));"
                "importlib = __import__('importlib.util');__import__('importlib.machinery');"
                "m = sys.modules.setdefault('ff_google.cloud', importlib.util.module_from_spec("
                "importlib.machinery.PathFinder.find_spec('ff_google.cloud', [os.path.dirname(p)])));"
                "m = m or sys.modules.setdefault('ff_google.cloud', types.ModuleType('ff_google.cloud'));"
                "mp = (m or []) and m.__dict__.setdefault('__path__',[]);(p not in mp) and mp.append(p);"
                "m and setattr(sys.modules['ff_google'], 'cloud', m)\n",
            )
            _write(
                os.path.join(w_ff, "ff_google", "cloud", "functions", "__init__.py"),
                "# Copyright 2020 Google LLC\n# Comment-only header.\n",
            )
            _write(
                os.path.join(w_ff, "ff_google", "cloud", "functions", "context.py"),
                "class Context:\n    pass\n",
            )

            # google-cloud-functions is a PEP 420 package (no *-nspkg.pth) and ships a real
            # __init__.py plus submodules under ff_google/cloud/functions/.
            _write(
                os.path.join(w_gcf, "ff_google", "cloud", "functions", "__init__.py"),
                "from ff_google.cloud.functions.client import CloudFunctionsServiceClient\n",
            )
            _write(
                os.path.join(w_gcf, "ff_google", "cloud", "functions", "client.py"),
                "class CloudFunctionsServiceClient:\n    pass\n",
            )

            import importlib

            prev_index = import_index._INDEX
            prev_meta = list(sys.meta_path)
            prev_path = list(sys.path)
            prev_merged = set(import_index._MERGED)
            try:
                import_index._INDEX = None
                import_index._MERGED.clear()
                sys.path[:] = [w_ff, w_gcf] + prev_path
                import_index.install([w_ff, w_gcf], mode="prebuilt")
                mod_fns = importlib.import_module("ff_google.cloud.functions")
                mod_ctx = importlib.import_module("ff_google.cloud.functions.context")
                self.assertTrue(hasattr(mod_fns, "CloudFunctionsServiceClient"))
                self.assertTrue(hasattr(mod_ctx, "Context"))
                self.assertEqual(len(mod_fns.__path__), 2)
            finally:
                import_index._INDEX = prev_index
                import_index._MERGED.clear()
                import_index._MERGED.update(prev_merged)
                sys.meta_path[:] = prev_meta
                sys.path[:] = prev_path
                for k in list(sys.modules):
                    if k == "ff_google" or k.startswith("ff_google."):
                        sys.modules.pop(k, None)

    def test_dt_rpath_vs_ld_library_path_vs_dt_runpath_ordering(self):
        with tempfile.TemporaryDirectory() as tmp:
            ld_dir = os.path.join(tmp, "ld_path")
            os.makedirs(ld_dir, exist_ok=True)
            ld_cudart = os.path.join(ld_dir, "libcudart.so.12")
            with open(ld_cudart, "wb") as fh:
                fh.write(import_index._make_stub_elf("$ORIGIN", "libc.so.6", soname="libcudart.so.12"))

            # Wrong-class (32-bit ELF, ei_class=1) file in LD_LIBRARY_PATH is skipped by
            # _elf_matches_process_class on 64-bit Python, matching glibc.
            ld_wrong_dir = os.path.join(tmp, "ld_wrong_class")
            os.makedirs(ld_wrong_dir, exist_ok=True)
            ld_cudart_32 = os.path.join(ld_wrong_dir, "libcudart.so.12")
            with open(ld_cudart_32, "wb") as fh:
                fh.write(b"\x7fELF\x01\x01\x01" + b"\x00" * 57)

            def make_roots_data(use_rpath):
                return [
                    (
                        "wheel_a/site-packages",
                        {
                            "version": 2,
                            "top": {"nvidia": ["nvidia"]},
                            "pth": [],
                            "dirs": ["nvidia", "nvidia/cuda_runtime", "nvidia/cuda_runtime/lib"],
                            "dist_info": None,
                            "native": {
                                "nvidia/cuda_runtime/lib/libcudart.so.12": {
                                    "soname": "libcudart.so.12",
                                    "needed": ["libc.so.6"],
                                    "rpath": [],
                                    "runpath": [],
                                }
                            },
                        },
                    ),
                    (
                        "wheel_b/site-packages",
                        {
                            "version": 2,
                            "top": {"nvidia": ["nvidia"]},
                            "pth": [],
                            "dirs": ["nvidia", "nvidia/cublas", "nvidia/cublas/lib"],
                            "dist_info": None,
                            "native": {
                                "nvidia/cublas/lib/libcublas.so.12": {
                                    "soname": "libcublas.so.12",
                                    "needed": ["libcudart.so.12"],
                                    "rpath": ["$ORIGIN/../../cuda_runtime/lib"] if use_rpath else [],
                                    "runpath": [] if use_rpath else ["$ORIGIN/../../cuda_runtime/lib"],
                                }
                            },
                            "escaping": {
                                "nvidia/cublas/lib/libcublas.so.12": {
                                    "rpath": ["nvidia/cuda_runtime/lib"] if use_rpath else [],
                                    "runpath": [] if use_rpath else ["nvidia/cuda_runtime/lib"],
                                }
                            },
                        },
                    ),
                ]

            # 1. Escaping $ORIGIN DT_RUNPATH preloads the provider library when LD_LIBRARY_PATH is unset.
            with mock.patch.dict(os.environ, {"LD_LIBRARY_PATH": ""}, clear=False):
                merged = import_index.merge_wheel_indexes(make_roots_data(use_rpath=False))
                self.assertEqual(
                    merged.get("preload", {}).get("nvidia.cublas"),
                    [[0, "nvidia/cuda_runtime/lib/libcudart.so.12"]],
                )

            # 2. LD_LIBRARY_PATH wins over escaping $ORIGIN DT_RUNPATH -> wheel copy NOT preloaded.
            with mock.patch.dict(os.environ, {"LD_LIBRARY_PATH": ld_dir}, clear=False):
                merged = import_index.merge_wheel_indexes(make_roots_data(use_rpath=False))
                self.assertIsNone(merged.get("preload", {}).get("nvidia.cublas"))

            # 3. Wrong-class (32-bit) ELF in LD_LIBRARY_PATH is ignored -> DT_RUNPATH still preloads wheel copy.
            if sys.maxsize > (1 << 32):
                self.assertFalse(import_index._elf_matches_process_class(ld_cudart_32))
                self.assertTrue(import_index._elf_matches_process_class(ld_cudart))
                with mock.patch.dict(os.environ, {"LD_LIBRARY_PATH": ld_wrong_dir}, clear=False):
                    merged = import_index.merge_wheel_indexes(make_roots_data(use_rpath=False))
                    self.assertEqual(
                        merged.get("preload", {}).get("nvidia.cublas"),
                        [[0, "nvidia/cuda_runtime/lib/libcudart.so.12"]],
                    )

            # 4. Escaping $ORIGIN DT_RPATH wins over LD_LIBRARY_PATH -> wheel copy IS preloaded.
            with mock.patch.dict(os.environ, {"LD_LIBRARY_PATH": ld_dir}, clear=False):
                merged = import_index.merge_wheel_indexes(make_roots_data(use_rpath=True))
                self.assertEqual(
                    merged.get("preload", {}).get("nvidia.cublas"),
                    [[0, "nvidia/cuda_runtime/lib/libcudart.so.12"]],
                )

            # 5. LD_LIBRARY_PATH is snapshotted at install() time (matching glibc): mutating
            # os.environ["LD_LIBRARY_PATH"] after install() does not affect lazy ensure_native_loaded().
            w_a = os.path.join(tmp, "wheel_a", "site-packages")
            w_b = os.path.join(tmp, "wheel_b", "site-packages")
            _write(os.path.join(w_a, "nvidia", "cuda_runtime", "__init__.py"), "")
            _write(os.path.join(w_b, "nvidia", "cublas", "__init__.py"), "")
            _write(
                os.path.join(w_a, import_index.NATIVE_PROVIDER_FILENAME),
                json.dumps(make_roots_data(use_rpath=False)[0][1]),
            )
            _write(
                os.path.join(w_b, import_index.NATIVE_PROVIDER_FILENAME),
                json.dumps(make_roots_data(use_rpath=False)[1][1]),
            )
            prev_index = import_index._INDEX
            prev_meta = list(sys.meta_path)
            try:
                import_index._INDEX = None
                with mock.patch.dict(os.environ, {"LD_LIBRARY_PATH": ""}, clear=False):
                    self.assertTrue(import_index.install([w_a, w_b], mode="prebuilt"))
                    self.assertFalse(import_index._INDEX._native_loaded)
                    # Mutate LD_LIBRARY_PATH after install() before lazy ensure_native_loaded():
                    os.environ["LD_LIBRARY_PATH"] = ld_dir
                    import_index._INDEX.ensure_native_loaded()
                    self.assertEqual(
                        import_index._INDEX.preload.get("nvidia.cublas"),
                        [(w_a, "nvidia/cuda_runtime/lib/libcudart.so.12")],
                    )
            finally:
                import_index._INDEX = prev_index
                import_index._PRELOADED.clear()
                sys.meta_path[:] = prev_meta

    def test_no_rpath_dt_needed_missing_on_host_is_not_rescued(self):
        # 1. Consumer classification only triggers on escaping $ORIGIN RPATH/RUNPATH.
        self.assertTrue(
            elf_tools.is_native_consumer(
                {"pkg": ["pkg"]},
                ["pkg", "pkg/lib"],
                {
                    "pkg/lib/liba.so": {
                        "soname": "liba.so",
                        "needed": [],
                        "rpath": [],
                        "runpath": ["$ORIGIN/../../other_pkg/lib"],
                    }
                },
            )
        )
        self.assertFalse(
            elf_tools.is_native_consumer(
                {"pkg": ["pkg"]},
                ["pkg", "pkg.libs"],
                {
                    "pkg/_ext.so": {
                        "soname": None,
                        "needed": ["libcross_wheel_unsatisfied.so.1"],
                        "rpath": ["$ORIGIN/../pkg.libs"],
                        "runpath": ["$ORIGIN"],
                    }
                },
            )
        )

        # 2. No-RPATH DT_NEEDED missing on the host is NOT rescued (matching pip):
        #    neither ExtensionFileLoader nor wheel-path dlopen retries or preloads missing SONAMEs,
        #    while bare-name dlopen fallback still lazily loads dotfiles and resolves SONAMEs.
        with tempfile.TemporaryDirectory() as tmp:
            w_prov = os.path.join(tmp, "wheel_prov", "site-packages")
            w_ext = os.path.join(tmp, "wheel_ext", "site-packages")
            foo_so = os.path.join(w_prov, "prov_pkg", "lib", "libfoo_lazy.so.1")
            ext_suffix = import_index._machinery.EXTENSION_SUFFIXES[0]
            ext_rel = "ext_pkg/_ext" + ext_suffix
            ext_so = os.path.join(w_ext, "ext_pkg", "_ext" + ext_suffix)
            wheel_ctypes_so = os.path.join(w_ext, "ext_pkg", "libuser.so")
            _write(foo_so, "ELF")
            _write(ext_so, "ELF")
            _write(wheel_ctypes_so, "ELF")
            _write(os.path.join(w_ext, "ext_pkg", "__init__.py"), "X = 1\n")

            # Write per-wheel dotfiles: both wheels have .pycross-native.json (NO .pycross-native-consumer.json).
            # Neither libfoo_lazy.so.1 nor _ext.so has an RPATH/RUNPATH.
            _write(
                os.path.join(w_prov, ".pycross-native.json"),
                json.dumps(
                    {
                        "version": 2,
                        "top": ["prov_pkg"],
                        "dirs": ["prov_pkg", "prov_pkg/lib"],
                        "native": {
                            "prov_pkg/lib/libfoo_lazy.so.1": {
                                "soname": "libfoo_lazy.so.1",
                                "needed": ["libc.so.6"],
                                "rpath": [],
                                "runpath": [],
                            },
                        },
                    }
                ),
            )
            _write(
                os.path.join(w_ext, ".pycross-native.json"),
                json.dumps(
                    {
                        "version": 2,
                        "top": ["ext_pkg"],
                        "dirs": ["ext_pkg"],
                        "native": {
                            ext_rel: {
                                "soname": None,
                                "needed": ["libfoo_lazy.so.1", "libc.so.6"],
                                "rpath": [],
                                "runpath": [],
                            },
                            "ext_pkg/libuser.so": {
                                "soname": "libuser.so",
                                "needed": ["libfoo_lazy.so.1", "libc.so.6"],
                                "rpath": [],
                                "runpath": [],
                            },
                        },
                    }
                ),
            )

            prev_index = import_index._INDEX
            prev_meta = list(sys.meta_path)
            prev_path = list(sys.path)
            try:
                import_index._INDEX = None
                import_index._PRELOADED.clear()
                sys.path[:] = [w_prov, w_ext] + prev_path
                preloaded = []

                with mock.patch.object(import_index, "_raw_dlopen", side_effect=lambda p: preloaded.append(p) or p):
                    self.assertTrue(import_index.install([w_prov, w_ext], mode="prebuilt"))
                    # Because neither wheel has .pycross-native-consumer.json, _native_loaded is False at startup!
                    self.assertFalse(import_index._INDEX._native_loaded)

                    # Pure-Python spec lookup does not trigger native dotfile loading.
                    py_spec = import_index.PathFinder.find_spec("ext_pkg")
                    self.assertIsNotNone(py_spec)
                    self.assertFalse(import_index._INDEX._native_loaded)
                    self.assertEqual(preloaded, [])

                    # Extension spec lookup returns stock ExtensionFileLoader without wrapping.
                    ext_spec = import_index.PathFinder.find_spec("ext_pkg._ext", [os.path.join(w_ext, "ext_pkg")])
                    self.assertIsNotNone(ext_spec)
                    self.assertIs(type(ext_spec.loader), import_index._machinery.ExtensionFileLoader)
                    self.assertFalse(import_index._INDEX._native_loaded)

                    # (a) Extension load failing with missing no-RPATH DT_NEEDED is NOT rescued:
                    # ImportError propagates immediately without loading dotfiles or preloading.
                    ext_attempts = []

                    def fake_fail_create(_self, _spec):
                        ext_attempts.append(1)
                        raise ImportError("libfoo_lazy.so.1: cannot open shared object file: No such file or directory")

                    with mock.patch.object(
                        import_index._machinery.ExtensionFileLoader,
                        "create_module",
                        new=fake_fail_create,
                    ):
                        with self.assertRaises(ImportError):
                            ext_spec.loader.create_module(ext_spec)
                    self.assertEqual(len(ext_attempts), 1)
                    self.assertFalse(import_index._INDEX._native_loaded)
                    self.assertEqual(preloaded, [])

                    # (b) Wheel-path dlopen failing with missing no-RPATH DT_NEEDED is NOT rescued:
                    # OSError propagates immediately without retrying or preloading.
                    ctypes_attempts = []

                    class FakeCtypesNoRescue:
                        @staticmethod
                        def dlopen(name, *args):
                            ctypes_attempts.append(name)
                            if name in (wheel_ctypes_so, "libfoo_lazy.so.1"):
                                raise OSError(
                                    "libfoo_lazy.so.1: cannot open shared object file: No such file or directory"
                                )
                            return ("loaded", name)

                    import_index._hook_ctypes_module(FakeCtypesNoRescue)
                    with self.assertRaises(OSError):
                        FakeCtypesNoRescue.dlopen(wheel_ctypes_so)
                    self.assertEqual(ctypes_attempts, [wheel_ctypes_so])
                    self.assertFalse(import_index._INDEX._native_loaded)
                    self.assertEqual(preloaded, [])

                    # (c) Bare-name dlopen("libfoo_lazy.so.1") DOES fall back to wheel SONAME after
                    # the original bare-name dlopen fails, lazily loading dotfiles.
                    ctypes_attempts.clear()
                    self.assertEqual(FakeCtypesNoRescue.dlopen("libfoo_lazy.so.1"), ("loaded", foo_so))
                    self.assertEqual(ctypes_attempts, ["libfoo_lazy.so.1", foo_so])
                    self.assertTrue(import_index._INDEX._native_loaded)
            finally:
                import_index._INDEX = prev_index
                import_index._PRELOADED.clear()
                sys.meta_path[:] = prev_meta
                sys.path[:] = prev_path


if __name__ == "__main__":
    unittest.main()
