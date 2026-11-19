import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from pycross.private.build.tools.utils import context


class BuildContextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.prefix = Path(self.tmp.name)
        self.config_path = self.prefix / "config.json"

    def _load(self, platform, sdist_root, source_dir=None):
        self.config_path.write_text(
            json.dumps(
                {
                    "sdist": "pkg.tar.gz",
                    "exec_python": "python",
                    "target_python": "python",
                    "wheel_dir": "wheels",
                    "source_dir": source_dir,
                }
            )
        )
        env = {"PYCROSS_BUILD_ROOT": "scratch", "PYCROSS_SDIST_DIR": str(sdist_root)}
        # Replace the module's OS view without changing pathlib's host platform.
        platform_os = SimpleNamespace(name=platform, environ=env, path=os.path)
        with patch.object(context, "os", platform_os), patch.object(context.Path, "cwd", return_value=self.prefix):
            return context.load_build_context(str(self.config_path))

    def test_windows_root_is_short_stable_and_inside_execroot(self):
        original = "bazel-out/" + "long-package-name/" * 30 + "sdist"
        first = self._load("nt", original)
        second = self._load("nt", original)

        self.assertEqual(first.sdist_root_dir, second.sdist_root_dir)
        self.assertEqual(first.sdist_root_dir.parent, self.prefix / "._ps")
        self.assertLess(len(str(first.sdist_root_dir.relative_to(self.prefix))), 64)
        self.assertEqual(first.sdist_dir, first.sdist_root_dir)
        self.assertEqual(first.temp_dir, self.prefix / "scratch")
        self.assertEqual(first.wheel_dir, self.prefix / "wheels")

    def test_windows_roots_distinguish_build_configurations(self):
        first = self._load("nt", "bazel-out/config-a/bin/pkg/sdist")
        second = self._load("nt", "bazel-out/config-b/bin/pkg/sdist")
        self.assertNotEqual(first.sdist_root_dir, second.sdist_root_dir)

    def test_source_dir_is_relative_to_selected_root(self):
        for platform in ["nt", "posix"]:
            with self.subTest(platform=platform):
                ctx = self._load(platform, "bazel-out/pkg/sdist", source_dir="project/src")
                self.assertEqual(ctx.sdist_dir, ctx.sdist_root_dir / "project" / "src")

    def test_non_windows_preserves_configured_root(self):
        for original in [Path("bazel-out/pkg/sdist"), self.prefix / "absolute-sdist"]:
            with self.subTest(original=original):
                ctx = self._load("posix", original)
                self.assertEqual(ctx.sdist_root_dir, (self.prefix / original).absolute())
                self.assertEqual(ctx.sdist_dir, ctx.sdist_root_dir)


if __name__ == "__main__":
    unittest.main()
