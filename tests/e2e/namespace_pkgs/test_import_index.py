"""Import semantics that need rules_python's import index (--venv_import_index).

Run with run_import_index.sh. With one sys.path entry per wheel and no index, the split package,
plugin and .pth checks fail; that is expected.
"""

import glob
import importlib
import importlib.metadata
import os
import sys
import unittest

NVIDIA_COMPONENTS = ("cublas", "cudnn", "nccl")

VERSIONS = {
    "azfixture-core": "1.0",
    "azfixture-core-tracing-plugin": "1.0",
    "enumfixture": "1.0",
    "nvidia-fixture-cublas": "12.0",
    "nvidia-fixture-cudnn": "12.0",
    "nvidia-fixture-nccl": "12.0",
    "pthfixture": "1.0",
    "rpathfixture": "1.0",
}


class ImportIndexTest(unittest.TestCase):
    def test_split_regular_package(self):
        # Every nvidia-fixture wheel ships an empty nvidia/__init__.py, so without merging,
        # `nvidia` binds to the first wheel on sys.path and the other components are missing.
        for component in NVIDIA_COMPONENTS:
            module = importlib.import_module("nvidia.fixture_" + component)
            self.assertTrue(module.__file__.endswith(os.path.join("fixture_" + component, "__init__.py")))

    def test_torch_style_glob_over_sys_path(self):
        # torch's _preload_cuda_deps globs every sys.path entry for nvidia/<lib>/lib/<name>.so.*,
        # so each wheel root must stay on sys.path.
        for component in NVIDIA_COMPONENTS:
            matches = [
                match
                for entry in sys.path
                for match in glob.glob(os.path.join(entry, "nvidia", "fixture_" + component, "lib", "lib*.so.*"))
            ]
            self.assertEqual(len(matches), 1, (component, matches))

    def test_plugin_under_another_wheels_regular_package(self):
        from azfixture.core.tracing.ext import fixture_span

        self.assertTrue(fixture_span.SPAN)

    def test_pth_path_and_import_lines(self):
        import pthfixture_extramod  # Importable through the .pth path line.

        self.assertTrue(pthfixture_extramod.EXTRA)
        self.assertTrue(getattr(sys, "_pthfixture_ran", False), "the .pth import line didn't run")

    def test_stdlib_not_shadowed(self):
        import enum

        self.assertFalse(hasattr(enum, "SHADOW"), enum.__file__)
        self.assertTrue(hasattr(enum, "IntFlag"))

    def test_first_party_py_library_and_shared_namespace(self):
        import first_party_mod
        from azfixture import first_party_ns
        from azfixture.core.tracing.ext import fixture_span

        self.assertTrue(first_party_mod.FIRST_PARTY)
        self.assertTrue(first_party_ns.FIRST_PARTY_NS)
        self.assertTrue(fixture_span.SPAN)

    def test_premerged_index_file_when_expected(self):
        if not os.environ.get("EXPECT_PREMERGED_INDEX_FILE"):
            return
        finder_mod = sys.modules.get("_bazel_import_index")
        self.assertIsNotNone(finder_mod)
        index_json = os.path.join(os.path.dirname(finder_mod.__file__), "_bazel_import_index.json")
        self.assertTrue(os.path.isfile(index_json), index_json)

    def test_metadata(self):
        for distribution, version in VERSIONS.items():
            self.assertEqual(importlib.metadata.version(distribution), version)
        names = [d.metadata["Name"] for d in importlib.metadata.distributions()]
        for distribution in VERSIONS:
            self.assertEqual(names.count(distribution), 1, distribution)

    @unittest.skipUnless(
        sys.platform == "linux" and os.uname().machine == "x86_64",
        "prebuilt ELF fixture is x86_64 Linux",
    )
    def test_cross_wheel_origin_rpath_without_preload(self):
        # rpathfixture/libuser.so has DT_NEEDED libfixture_cublas.so.12 and dlopens
        # libfixture_cudnn.so.12 by SONAME via $ORIGIN/../nvidia/fixture_{cublas,cudnn}/lib.
        # In prebuilt mode, PyMakeVenvIndex resolves those cross-wheel $ORIGIN paths from the
        # per-wheel "native" metadata and records "preload" entries that the finder loads via
        # ctypes.CDLL when importing rpathfixture.
        finder_mod = sys.modules.get("_bazel_import_index")
        if finder_mod is not None and getattr(finder_mod, "_INDEX", None) is not None:
            if not finder_mod._INDEX.indexed:
                self.skipTest("cross-wheel native preloading requires the prebuilt import index")
        import rpathfixture

        self.assertEqual(rpathfixture.load_and_call(), (12, 9))


if __name__ == "__main__":
    unittest.main()
