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
    "sonamefixture": "1.0",
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
        # In prebuilt mode, merge_wheel_indexes resolves those cross-wheel $ORIGIN paths from the
        # per-wheel "native" metadata and records "preload" entries that the finder loads via
        # ctypes.CDLL when importing rpathfixture.
        finder_mod = sys.modules.get("_bazel_import_index")
        if finder_mod is not None and getattr(finder_mod, "_INDEX", None) is not None:
            if not finder_mod._INDEX.indexed:
                self.skipTest("cross-wheel native preloading requires the prebuilt import index")
        import rpathfixture

        self.assertEqual(rpathfixture.load_and_call(), (12, 9))

    @unittest.skipUnless(
        sys.platform == "linux" and os.uname().machine == "x86_64",
        "prebuilt ELF fixture is x86_64 Linux",
    )
    def test_cross_wheel_soname_dt_needed_and_dlopen_hooks(self):
        finder_mod = sys.modules.get("_bazel_import_index")
        if finder_mod is not None and getattr(finder_mod, "_INDEX", None) is not None:
            if not finder_mod._INDEX.indexed:
                self.skipTest("cross-wheel native preloading requires the prebuilt import index")
        import sonamefixture

        self.assertEqual(
            sonamefixture.load_and_call(),
            (12, 9, 9, "libfixture_cublas.so.12"),
        )

        # Also verify lazy retry-on-failure in a clean subprocess with 0 consumer wheels
        # (filtering out rpathfixture so no .pycross-native-consumer.json wheel is present),
        # for both a first-party ExtensionFileLoader and a wheel ctypes.CDLL load.
        if finder_mod is not None:
            import subprocess

            import first_party_mod

            non_consumer_roots = [
                r
                for r in finder_mod._INDEX.roots
                if os.path.basename(os.path.dirname(r))
                in ("nvidia_fixture_cublas", "nvidia_fixture_cudnn", "sonamefixture")
            ]
            finder_dir = os.path.dirname(finder_mod.__file__)
            fp_dir = os.path.dirname(first_party_mod.__file__)
            code = "\n".join(
                [
                    "import os, sys, unittest.mock as mock",
                    "sys.path[:0] = {!r} + [{!r}, {!r}]".format(non_consumer_roots, finder_dir, fp_dir),
                    "import _bazel_import_index as bi",
                    "bi.install({!r}, mode='prebuilt')".format(non_consumer_roots),
                    "assert not bi._INDEX._native_loaded, 'expected 0 consumers at startup'",
                    "fp_spec = bi._spec('fp_native_ext', os.path.join({!r}, 'fp_native_ext.so'), bi._machinery.ExtensionFileLoader)".format(
                        fp_dir
                    ),
                    "bi._finalize_spec('fp_native_ext', fp_spec)",
                    "assert not bi._INDEX._native_loaded, 'wrapping first-party extension must not load native dotfiles'",
                    "calls = []",
                    "def fake_create(self, spec):",
                    "    calls.append(1)",
                    "    if len(calls) == 1:",
                    "        raise ImportError('libfixture_cudnn.so.12: cannot open shared object file: No such file or directory')",
                    "    return 'fp_ok'",
                    "with mock.patch.object(bi._machinery.ExtensionFileLoader, 'create_module', new=fake_create):",
                    "    assert fp_spec.loader.create_module(fp_spec) == 'fp_ok'",
                    "assert bi._INDEX._native_loaded and 'libfixture_cudnn.so.12' in bi._PRELOADED_SONAMES",
                    "bi._INDEX._native_loaded = False",
                    "bi._INDEX.sonames.clear()",
                    "bi._INDEX.native_deps.clear()",
                    "bi._PRELOADED.clear()",
                    "bi._PRELOADED_SONAMES.clear()",
                    "import sonamefixture",
                    "assert not bi._INDEX._native_loaded, 'pure-Python import should not load native dotfiles'",
                    "assert sonamefixture.load_and_call() == (12, 9, 9, 'libfixture_cublas.so.12')",
                    "assert bi._INDEX._native_loaded, 'expected lazy native load on dlopen failure'",
                ]
            )
            subprocess.run([sys.executable, "-S", "-c", code], check=True)


if __name__ == "__main__":
    unittest.main()
