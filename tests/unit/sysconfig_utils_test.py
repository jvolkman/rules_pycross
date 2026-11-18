import os
import sys
import sysconfig
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from pycross.private.build.tools.utils.env import make_clean_env
from pycross.private.build.tools.utils.sysconfig_utils import _query_interpreter
from pycross.private.build.tools.utils.sysconfig_utils import determine_target_path_from_exec
from pycross.private.build.tools.utils.sysconfig_utils import load_target_sysconfig
from pycross.private.build.tools.utils.venv_utils import write_base_prefix_pth


class QueryInterpreterTest(unittest.TestCase):
    def test_query_current_interpreter(self):
        """Querying the running interpreter should succeed and return installed_base."""
        result = _query_interpreter(Path(sys.executable))
        self.assertIsNotNone(result)
        self.assertIn("installed_base", result)
        self.assertIn("installed_platbase", result)
        # installed_base should be a non-empty path
        self.assertTrue(result["installed_base"])
        self.assertTrue(result["installed_platbase"])

    def test_query_nonexistent_interpreter(self):
        """Querying a missing interpreter should return None with a warning, not raise."""
        result = _query_interpreter(Path("/nonexistent/python3"))
        self.assertIsNone(result)

    def test_query_returns_sysconfig_vars(self):
        """The result should include standard sysconfig build_time_vars."""
        result = _query_interpreter(Path(sys.executable))
        self.assertIsNotNone(result)
        # These are standard sysconfig vars that should always be present on Linux/macOS
        if sys.platform != "win32":
            self.assertIn("EXT_SUFFIX", result)


class LoadTargetSysconfigTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.orig_cwd = Path.cwd()

    def tearDown(self):
        os.chdir(self.orig_cwd)
        self.temp_dir.cleanup()

    @unittest.skipIf(sys.platform == "win32", "POSIX shell wrapper test")
    def test_primary_probe_preserves_env_and_isolates_imports(self):
        """Primary probe forwards build_env while ignoring PYTHONPATH and sdist cwd."""
        sdist_dir = self.temp_path / "sdist"
        sdist_dir.mkdir()
        (sdist_dir / "json.py").write_text('raise RuntimeError("poisoned cwd json")\n')

        poison_pp = self.temp_path / "poison_pp"
        poison_pp.mkdir()
        (poison_pp / "json.py").write_text('raise RuntimeError("poisoned PYTHONPATH json")\n')

        wrapper = self.temp_path / "target_python.sh"
        wrapper.write_text(
            "#!/bin/sh\n"
            'test "$MY_TOOLCHAIN_VAR" = "expected" || exit 1\n'
            'test -z "$PYTHONPATH" || exit 1\n'
            'test "$PYTHONSAFEPATH" = "1" || exit 1\n'
            f'exec "{sys.executable}" "$@"\n'
        )
        wrapper.chmod(0o755)

        build_env = make_clean_env()
        build_env["MY_TOOLCHAIN_VAR"] = "expected"
        build_env["PYTHONPATH"] = str(poison_pp)
        ctx = SimpleNamespace(
            target_python=wrapper,
            exec_python=Path(sys.executable),
            build_env=build_env,
        )

        os.chdir(sdist_dir)
        result = load_target_sysconfig(ctx)

        self.assertIn("installed_base", result)
        # ctx.build_env itself must not be mutated.
        self.assertEqual(ctx.build_env["PYTHONPATH"], str(poison_pp))
        self.assertNotIn("PYTHONSAFEPATH", ctx.build_env)

    def _make_fake_target_layout(self) -> tuple[Path, Path]:
        """Mirror the running Python's executable/stdlib layout under a temp root."""
        real_exec = Path(sys.executable).resolve()
        real_stdlib = Path(sysconfig.get_path("stdlib")).resolve()
        common = Path(os.path.commonpath([real_exec, real_stdlib]))

        target_root = self.temp_path / "target_py"
        target_exe = target_root / real_exec.relative_to(common)
        target_exe.parent.mkdir(parents=True, exist_ok=True)
        target_exe.write_text("not an executable binary\n")

        target_stdlib = target_root / real_stdlib.relative_to(common)
        target_stdlib.mkdir(parents=True, exist_ok=True)
        return target_exe, target_stdlib

    def test_fallback_probe_ignores_pythonpath_and_cwd(self):
        """When target_python cannot run, fallback maps exec sys.path cleanly."""
        sdist_dir = self.temp_path / "sdist"
        sdist_dir.mkdir()
        (sdist_dir / "json.py").write_text('raise RuntimeError("poisoned cwd json")\n')

        poison_pp = self.temp_path / "poison_pp"
        poison_pp.mkdir()
        (poison_pp / "json.py").write_text('raise RuntimeError("poisoned PYTHONPATH json")\n')

        target_exe, target_stdlib = self._make_fake_target_layout()
        (target_stdlib / "_sysconfigdata__test.py").write_text('build_time_vars = {"EXT_SUFFIX": ".fake-target.so"}\n')

        build_env = make_clean_env()
        build_env["PYTHONPATH"] = str(poison_pp)
        ctx = SimpleNamespace(
            target_python=target_exe,
            exec_python=Path(sys.executable),
            build_env=build_env,
        )

        os.chdir(sdist_dir)
        result = load_target_sysconfig(ctx)

        self.assertEqual(result, {"EXT_SUFFIX": ".fake-target.so"})
        self.assertEqual(ctx.build_env["PYTHONPATH"], str(poison_pp))
        self.assertNotIn("PYTHONSAFEPATH", ctx.build_env)

    def test_determine_target_path_from_exec_excludes_cwd(self):
        """Direct calls without PYTHONSAFEPATH still isolate cwd and omit empty entries."""
        sdist_dir = self.temp_path / "sdist"
        sdist_dir.mkdir()
        (sdist_dir / "json.py").write_text('raise RuntimeError("poisoned cwd json")\n')

        target_exe, target_stdlib = self._make_fake_target_layout()
        os.chdir(sdist_dir)
        paths = determine_target_path_from_exec(Path(sys.executable), target_exe, make_clean_env())

        self.assertIn(target_stdlib.resolve(), paths)
        self.assertNotIn(sdist_dir.resolve(), paths)


class BasePrefixPthTest(unittest.TestCase):
    """Test the .pth file generation logic for sys.base_prefix/sys.base_exec_prefix."""

    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        # Simulate a venv site-packages directory
        self.site_dir = self.temp_path / "env" / "lib" / "python3.10" / "site-packages"
        self.site_dir.mkdir(parents=True)
        self.pth_file = self.site_dir / "_00_pycross_sys_base_prefix.pth"

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_base_prefix_pth(self, prefix, base_prefix, platbase_prefix, site_dir):
        write_base_prefix_pth(site_dir, prefix, base_prefix, platbase_prefix)

    def test_base_prefix_inside_execroot_uses_relative_path(self):
        """When base_prefix is inside the execroot, .pth should use relative sitedir paths."""
        prefix = self.temp_path
        base_prefix = self.temp_path / "some" / "interpreter"
        platbase_prefix = self.temp_path / "some" / "interpreter"
        self._write_base_prefix_pth(prefix, base_prefix, platbase_prefix, self.site_dir)

        content = self.pth_file.read_text()
        self.assertIn("import os, sys; ", content)
        self.assertIn("os.path.abspath(os.path.join(sitedir,", content)
        self.assertIn("sys.base_prefix", content)
        self.assertIn("sys.base_exec_prefix", content)
        # Should NOT contain absolute paths
        self.assertNotIn(str(self.temp_path), content)

    def test_base_prefix_outside_execroot_uses_absolute_path(self):
        """When base_prefix is outside the execroot, .pth should use absolute paths."""
        prefix = self.temp_path / "sandbox"
        prefix.mkdir()
        base_prefix = Path("/usr/local/python3")
        platbase_prefix = Path("/usr/local/python3")
        self._write_base_prefix_pth(prefix, base_prefix, platbase_prefix, self.site_dir)

        content = self.pth_file.read_text()
        self.assertIn("import sys; ", content)
        self.assertIn('sys.base_prefix = "/usr/local/python3"', content)
        self.assertIn('sys.base_exec_prefix = "/usr/local/python3"', content)

    def test_base_and_platbase_can_differ(self):
        """base_prefix and platbase_prefix can point to different locations."""
        prefix = self.temp_path / "sandbox"
        prefix.mkdir()
        base_prefix = Path("/usr/local/python3")
        platbase_prefix = Path("/usr/local/python3-plat")
        self._write_base_prefix_pth(prefix, base_prefix, platbase_prefix, self.site_dir)

        content = self.pth_file.read_text()
        self.assertIn('sys.base_prefix = "/usr/local/python3"', content)
        self.assertIn('sys.base_exec_prefix = "/usr/local/python3-plat"', content)

    def test_no_pth_written_when_both_none(self):
        """No .pth file should be written when both prefixes are None."""
        self._write_base_prefix_pth(self.temp_path, None, None, self.site_dir)
        self.assertFalse(self.pth_file.exists())

    def test_only_base_prefix_set(self):
        """Only sys.base_prefix should be set when platbase is None."""
        prefix = self.temp_path / "sandbox"
        prefix.mkdir()
        base_prefix = Path("/usr/local/python3")
        self._write_base_prefix_pth(prefix, base_prefix, None, self.site_dir)

        content = self.pth_file.read_text()
        self.assertIn("sys.base_prefix", content)
        self.assertNotIn("sys.base_exec_prefix", content)


if __name__ == "__main__":
    unittest.main()
