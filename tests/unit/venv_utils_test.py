import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.utils.venv_utils import _build_crossenv_pythonpath
from pycross.private.build.tools.utils.venv_utils import inject_python_wrapper


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.exec_python = Path("/usr/bin/python3")
        self.env_dir = temp_dir / "env"
        self.python_paths = [Path("/mock/dep/path")]
        self.prefix = temp_dir
        self.original_sdist_root = "bazel-out/config-a/bin/pkg/target/sdist"
        self.sdist_dir = temp_dir / "sdist"
        self.sdist_root_dir = self.sdist_dir
        self.build_env = {}
        self.sysconfig_vars = {}

        # Create mocked env dir and lib paths
        bin_dir = self.env_dir / "bin"
        bin_dir.mkdir(parents=True)
        self.python_exe = bin_dir / "python"
        self.python_exe.touch()

        lib_dir = self.env_dir / "lib" / "python3.10" / "site-packages"
        lib_dir.mkdir(parents=True)


class VenvUtilsTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_inject_python_wrapper(self):
        ctx = MockBuildContext(self.temp_path)
        inject_python_wrapper(ctx)

        self.assertTrue(ctx.python_exe.exists())
        content = ctx.python_exe.read_text()

        # Assert shebang
        self.assertTrue(content.startswith("#!/bin/sh"))

        # Assert python exec fallback
        self.assertIn(f'"exec" "{ctx.exec_python.absolute()}"', content)

        # Assert PYTHONPATH
        self.assertIn('os.environ["PYTHONPATH"]', content)
        self.assertIn("site-packages", content)
        self.assertIn(repr(str(ctx.sdist_dir.absolute())), content)

    def test_crossenv_pythonpath_remaps_sdist_and_preserves_other_paths(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.sdist_root_dir = self.temp_path / "bazel-out" / "_pcr" / "0123456789abcdef"
        ctx.build_env["PYTHONPATH"] = ";".join(
            [str(ctx.sdist_root_dir / "project" / "src"), "C:\\external\\dependency"],
        )
        absolute_old_path = str(self.temp_path).replace("/", "\\") + "\\" + ctx.original_sdist_root.replace("/", "\\")

        result = _build_crossenv_pythonpath(
            ctx,
            [absolute_old_path + "\\project\\src", "/mock/dep/path", "/python/stdlib"],
            "/python/stdlib",
            ";",
            True,
        )

        self.assertEqual(
            result.split(";"),
            [
                str(ctx.sdist_root_dir / "project" / "src"),
                "/mock/dep/path",
                str(ctx.sdist_root_dir / "project" / "src"),
                "C:\\external\\dependency",
            ],
        )

    def test_crossenv_pythonpath_preserves_non_windows_entries(self):
        ctx = MockBuildContext(self.temp_path)
        old_path = ctx.original_sdist_root + "/project/src"
        ctx.build_env["PYTHONPATH"] = old_path + os.pathsep + "/external/dependency"

        result = _build_crossenv_pythonpath(ctx, [old_path, "/mock/dep/path"], "/python/stdlib", os.pathsep, False)

        self.assertEqual(result, os.pathsep.join([old_path, "/mock/dep/path", old_path, "/external/dependency"]))

    def test_crossenv_pythonpath_preserves_empty_first_entry(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.build_env["PYTHONPATH"] = "/external/dependency"

        result = _build_crossenv_pythonpath(ctx, ["", "/python/stdlib"], "/python/stdlib", os.pathsep, False)

        self.assertEqual(result, os.pathsep + "/external/dependency")


if __name__ == "__main__":
    unittest.main()
