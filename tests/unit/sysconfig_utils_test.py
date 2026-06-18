import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.utils.sysconfig_utils import _query_interpreter
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


class BasePrefixPthTest(unittest.TestCase):
    """Test the .pth file generation logic for sys.base_prefix/sys.base_exec_prefix."""

    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        # Simulate a venv site-packages directory
        self.site_dir = self.temp_path / "env" / "lib" / "python3.10" / "site-packages"
        self.site_dir.mkdir(parents=True)
        self.pth_file = self.site_dir / "_pycross_sys_base_prefix.pth"

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
