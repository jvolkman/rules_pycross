import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import _apply_pre_build_patches
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.lifecycle import setup_pkg_config


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

        # Create minimal config JSON
        self.config_path = self.temp_path / "config.json"
        with open(self.config_path, "w") as f:
            json.dump(
                {
                    "sdist": "dummy_sdist.tar.gz",
                    "exec_python": "python3",
                    "target_python": "python3",
                    "wheel_dir": "out_wheel_dir",
                    "layers": [],
                },
                f,
            )

        os.environ["PYCROSS_BUILD_ROOT"] = "build_root"
        os.environ["PYCROSS_SDIST_DIR"] = "sdist_dir"

    def tearDown(self):
        self.temp_dir.cleanup()
        os.environ.pop("PYCROSS_BUILD_ROOT", None)
        os.environ.pop("PYCROSS_SDIST_DIR", None)

    @patch("pycross.private.build.tools.utils.lifecycle.extract_sdist")
    @patch("pycross.private.build.tools.utils.lifecycle.os.chdir")
    @patch("pycross.private.build.tools.utils.lifecycle.setup_path_tools")
    @patch("pycross.private.build.tools.utils.lifecycle.apply_sysconfig_overrides")
    @patch("pycross.private.build.tools.utils.lifecycle.run_pep517_build")
    @patch("pycross.private.build.tools.utils.lifecycle.load_target_sysconfig")
    def test_lifecycle_ordering(
        self, mock_load_sysconfig, mock_pep517, mock_apply_sys, mock_setup_path, mock_chdir, mock_extract
    ):
        call_order = []

        def setup_toolchains(ctx):
            call_order.append("setup_toolchains")

        def setup_venv(ctx):
            call_order.append("setup_venv")

        def pre_build(ctx):
            call_order.append("pre_build")

        def prepare_env(ctx):
            call_order.append("prepare_env")

        strategy = BackendStrategy(
            setup_toolchains=setup_toolchains, setup_venv=setup_venv, pre_build=pre_build, prepare_env=prepare_env
        )

        run_standard_build_lifecycle(str(self.config_path), strategy)

        self.assertEqual(call_order, ["setup_toolchains", "setup_venv", "pre_build", "prepare_env"])


class PreBuildPatchesTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.prefix = Path(self.temp_dir.name)
        self.sdist_dir = self.prefix / "sdist" / "pkg-1.0"
        (self.sdist_dir / "pkg").mkdir(parents=True)
        (self.sdist_dir / "pkg/__init__.py").write_bytes(b"A = 1\n")
        (self.prefix / "patches").mkdir()

    def tearDown(self):
        self.temp_dir.cleanup()

    def _ctx(self, patches):
        return SimpleNamespace(
            prefix=self.prefix, sdist_dir=self.sdist_dir, bazel_config={"pre_build_patches": patches}
        )

    def test_git_style_patch_applies_relative_to_prefix(self):
        (self.prefix / "patches/fix.patch").write_bytes(
            b"--- a/pkg/__init__.py\t2026-06-04 13:22:25 +0000\n"
            b"+++ b/pkg/__init__.py\t2026-06-04 13:23:03 +0000\n"
            b"@@ -1 +1,2 @@\n A = 1\n+PATCHED = True\n"
        )
        _apply_pre_build_patches(self._ctx(["patches/fix.patch"]))
        self.assertEqual((self.sdist_dir / "pkg/__init__.py").read_bytes(), b"A = 1\nPATCHED = True\n")

    def test_unapplicable_patch_exits(self):
        (self.prefix / "patches/bad.patch").write_bytes(
            b"--- a/pkg/missing.py\n+++ b/pkg/missing.py\n@@ -1 +1 @@\n-x\n+y\n"
        )
        with self.assertRaises(SystemExit) as ctx:
            _apply_pre_build_patches(self._ctx(["patches/bad.patch"]))
        self.assertIn("failed to apply patch file", str(ctx.exception))
        self.assertIn("targets non-existent file 'pkg/missing.py'", str(ctx.exception))


class SetupPkgConfigTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.prefix = Path(self.temp_dir.name)
        self.temp_build = self.prefix / "tmp"
        self.temp_build.mkdir()
        self.sdist_dir = self.prefix / "sdist"
        self.sdist_dir.mkdir()

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_materializes_in_temp_dir_and_prepends_pkg_config_path(self):
        pc_src = self.prefix / "foo.pc"
        pc_src.write_text("prefix=$$EXT_BUILD_ROOT$$/libs/foo\nName: foo\n")
        pc_src.chmod(0o444)

        ctx = SimpleNamespace(
            prefix=self.prefix,
            temp_dir=self.temp_build,
            sdist_dir=self.sdist_dir,
            pkg_config_files=[pc_src],
            build_env={"PKG_CONFIG_PATH": "/existing/pc"},
        )

        pc_dir = setup_pkg_config(ctx)
        self.assertEqual(pc_dir, self.temp_build / "pkgconfig")
        self.assertFalse((self.sdist_dir / "pkgconfig").exists())

        dest = pc_dir / "foo.pc"
        self.assertTrue(dest.exists())
        self.assertEqual(dest.read_text(), f"prefix={self.prefix}/libs/foo\nName: foo\n")
        self.assertEqual(
            ctx.build_env["PKG_CONFIG_PATH"],
            f"{pc_dir.resolve().as_posix()}{os.pathsep}/existing/pc",
        )

        # Calling a second time (e.g. from meson_utils after pre-build hooks)
        # preserves hook edits to .pc files and PKG_CONFIG_PATH.
        dest.write_text("prefix=/hook/override\n")
        ctx.build_env.pop("PKG_CONFIG_PATH")
        setup_pkg_config(ctx)
        self.assertEqual(dest.read_text(), "prefix=/hook/override\n")
        self.assertNotIn("PKG_CONFIG_PATH", ctx.build_env)


if __name__ == "__main__":
    unittest.main()
