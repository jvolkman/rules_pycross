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

from pycross.private.tools import import_index
from pycross.private.tools import venv_import_index_merger

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
        merged = venv_import_index_merger.merge(entries)
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
        # Write `<wheel>.dist_info/index.json` next to each `<wheel>/site-packages`
        # and verify `index_path=None` in `prebuilt` mode merges them in memory
        # with zero os.scandir calls.
        per_wheel_files = []
        for root in self.roots.values():
            idx_path = os.path.dirname(root) + ".dist_info/index.json"
            _write(idx_path, json.dumps(_wheel_index(root)))
            per_wheel_files.append(idx_path)
        try:
            finder = self.probe_index("prebuilt", None, forbid_scandir=True)
            self.assertTrue(finder["_installed"])
            self.assertEqual(finder["_indexed"], len(self.roots))
            self.assertEqual(self.oracle_keys(finder), self.results["merged"])
            self.assertEqual(finder["_isdir_calls"], 0)
        finally:
            for p in per_wheel_files:
                shutil.rmtree(os.path.dirname(p), ignore_errors=True)

    def test_merge_preload_and_finder_preloads_on_import(self):
        def wheel(**fields):
            return dict(
                {"version": 1, "top": {}, "pth": [], "dirs": [], "dist_info": None},
                **fields,
            )

        merged = venv_import_index_merger.merge(
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

    def test_preload_soname_dt_needed_without_rpath_and_dot_libs(self):
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
                        # symlink should win without duplicate preload entries.
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
        merged = venv_import_index_merger.merge(entries)
        self.assertEqual(
            merged["preload"]["onnxruntime"],
            [
                [0, "nvidia/cublas/lib/libcublas.so.12"],
                [0, "nvidia/cublas/lib/libnosoname.so"],
            ],
        )
        self.assertEqual(
            merged["sonames"]["libcublas.so.12"],
            [0, "nvidia/cublas/lib/libcublas.so.12"],
        )
        self.assertEqual(
            merged["sonames"]["libnosoname.so"],
            [0, "nvidia/cublas/lib/libnosoname.so"],
        )
        self.assertNotIn("_ext.cpython-312-x86_64-linux-gnu.so", merged["sonames"])

        with mock.patch.dict(os.environ, {"RULES_PYTHON_IMPORT_INDEX_SONAME_PRELOAD": "0"}):
            merged_disabled = venv_import_index_merger.merge(entries)
        self.assertNotIn("preload", merged_disabled)

    def test_stub_elf_and_read_elf_needed_roundtrip(self):
        stub_bytes = import_index._make_stub_elf("/tmp/wheel/lib", "libcublas.so.12")
        self.assertIsNotNone(stub_bytes)
        self.assertTrue(stub_bytes.startswith(b"\x7fELF"))
        with tempfile.NamedTemporaryFile(suffix=".so") as tf:
            tf.write(stub_bytes)
            tf.flush()
            self.assertEqual(import_index._read_elf_needed(tf.name), ["libcublas.so.12"])

    def test_runtime_dlopen_find_library_cffi_and_extension_needed(self):
        with tempfile.TemporaryDirectory() as tmp:
            cublas_root = os.path.join(tmp, "cublas", "site-packages")
            cudnn_root = os.path.join(tmp, "cudnn", "site-packages")
            torch_root = os.path.join(tmp, "torch", "site-packages")
            nvcc_root = os.path.join(tmp, "nvcc", "site-packages")
            fp_root = os.path.join(tmp, "first_party")

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

            # First-party native extension with DT_NEEDED on libcudnn.so.9.
            fp_ext_path = os.path.join(fp_root, "fp_ext.so")
            os.makedirs(fp_root, exist_ok=True)
            with open(fp_ext_path, "wb") as fh:
                fh.write(import_index._make_stub_elf("/unused", "libcudnn.so.9"))

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

                    # Item 5c: ctypes.util.find_library wrapper.
                    import ctypes.util

                    import_index._hook_ctypes_util_module(ctypes.util)
                    self.assertEqual(ctypes.util.find_library("cublas"), cublas_so)
                    self.assertEqual(ctypes.util.find_library("libcudnn.so.9"), cudnn_so)

                    # Item 5b: _cffi_backend wrapper (load_library and FFI.dlopen).
                    class FakeFFI:
                        def dlopen(self, name=None, flags=0):
                            return (name, flags)

                    class FakeCffiBackend:
                        FFI = FakeFFI

                        @staticmethod
                        def load_library(name=None, flags=0):
                            return (name, flags)

                    import_index._hook_cffi_backend_module(FakeCffiBackend)
                    self.assertEqual(FakeCffiBackend.load_library("cublas", 2), (cublas_so, 2))
                    self.assertEqual(FakeCffiBackend.FFI().dlopen("libcudnn.so.9", 1), (cudnn_so, 1))

                    # Item 6: First-party ExtensionFileLoader DT_NEEDED preloading.
                    preloaded_calls.clear()
                    import_index._PRELOADED.clear()
                    import_index._CHECKED_EXTENSIONS.clear()
                    fp_spec = import_index._spec(
                        "fp_ext",
                        fp_ext_path,
                        import_index._machinery.ExtensionFileLoader,
                    )
                    import_index._finalize_spec("fp_ext", fp_spec)
                    self.assertEqual(preloaded_calls, [cublas_lt_so, cublas_so, cudnn_so])
            finally:
                import_index._INDEX = prev_index
                import_index._PRELOADED.clear()
                import_index._CHECKED_EXTENSIONS.clear()
                sys.meta_path[:] = prev_meta


if __name__ == "__main__":
    unittest.main()
