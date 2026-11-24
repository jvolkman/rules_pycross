import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from pycross.private.build.tools.utils.venv_utils import _build_crossenv_pythonpath
from pycross.private.build.tools.utils.venv_utils import build_crossenv_venv
from pycross.private.build.tools.utils.venv_utils import build_standard_venv
from pycross.private.build.tools.utils.venv_utils import find_site_dir
from pycross.private.build.tools.utils.venv_utils import inject_python_wrapper
from pycross.private.build.tools.utils.venv_utils import venv_python_path


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

    @unittest.skipIf(os.name == "nt", "POSIX shell wrapper")
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

    @unittest.skipIf(os.name == "nt", "POSIX crossenv layout")
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

    @unittest.skipUnless(os.name == "nt", "Windows venv layout")
    def test_build_standard_venv_on_windows(self):
        env_dir = self.temp_path / "new env"
        sdist_dir = self.temp_path / "sdist"
        sdist_dir.mkdir()
        (sdist_dir / "from_sdist.py").touch()
        build_deps = self.temp_path / "build_deps"
        (build_deps / "from_build_deps").mkdir(parents=True)
        (build_deps / "from_build_deps" / "__init__.py").touch()
        extra_pythonpath = self.temp_path / "extra_pythonpath"
        extra_pythonpath.mkdir()
        (extra_pythonpath / "from_pythonpath.py").touch()
        base_prefix = self.temp_path / "users" / "buildpython"
        base_prefix.mkdir(parents=True)
        ctx = SimpleNamespace(
            exec_python=Path(sys.executable),
            target_python=Path(sys.executable),
            prefix=self.temp_path,
            env_dir=env_dir,
            sdist_dir=sdist_dir,
            sysconfig_vars={"installed_base": str(base_prefix), "installed_platbase": sys.base_exec_prefix},
            python_paths=[build_deps],
            site_hooks=["import os; os.environ['FROM_SITE_HOOK'] = '1'"],
            build_env={**os.environ, "PYTHONPATH": str(extra_pythonpath)},
        )
        ctx.build_env.pop("PYTHONHOME", None)
        build_standard_venv(ctx)

        self.assertEqual(venv_python_path(env_dir), env_dir / "Scripts" / "python.exe")
        self.assertEqual(find_site_dir(env_dir), env_dir / "Lib" / "site-packages")
        output = subprocess.check_output(
            [
                str(venv_python_path(env_dir)),
                "-c",
                "import os, sys, from_sdist, from_build_deps, from_pythonpath; "
                "print(sys.prefix); print(sys.base_prefix); print(os.environ['FROM_SITE_HOOK'])",
            ],
            cwd=self.temp_path,
            env=ctx.build_env,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self.assertEqual(output.splitlines(), [str(env_dir), str(base_prefix), "1"])


if __name__ == "__main__":
    unittest.main()
