import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from pycross.private.build.tools.utils.venv_utils import build_crossenv_venv
from pycross.private.build.tools.utils.venv_utils import inject_python_wrapper


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.exec_python = Path("/usr/bin/python3")
        self.env_dir = temp_dir / "env"
        self.python_paths = [Path("/mock/dep/path")]
        self.sdist_dir = temp_dir / "sdist"
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
        self.assertIn('"exec" "/usr/bin/python3"', content)

        # Assert PYTHONPATH
        self.assertIn('os.environ["PYTHONPATH"]', content)
        self.assertIn("site-packages", content)
        self.assertIn(str(ctx.sdist_dir.absolute()), content)

    def test_build_crossenv_venv_writes_site_hooks(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.target_python = Path("/target/bin/python3")
        ctx.build_env = {}
        ctx.bazel_config = {}
        ctx.python_paths = []
        ctx.site_hooks = ["import os; os.environ['FROM_SITE_HOOK'] = '1'"]

        with patch("pycross.private.build.tools.utils.venv_utils.subprocess.check_output") as mock_run:
            build_crossenv_venv(ctx)
            mock_run.assert_called_once()

        hooks_py = ctx.env_dir / "_pycross_hooks.py"
        hooks_pth = ctx.env_dir / "lib" / "python3.10" / "site-packages" / "_pycross_hooks.pth"
        self.assertTrue(hooks_py.exists())
        self.assertTrue(hooks_pth.exists())
        self.assertIn("FROM_SITE_HOOK", hooks_py.read_text())
        self.assertIn("_pycross_hooks", hooks_pth.read_text())


if __name__ == "__main__":
    unittest.main()
