"""Tests for wheel_transformer.py wheelhouse support."""

import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch, MagicMock


class WheelTransformerArgsTest(unittest.TestCase):
    """Test argument parsing for wheel_transformer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.in_wheelhouse = Path(self.temp_dir) / "in_wheelhouse"
        self.in_wheelhouse.mkdir()
        self.out_wheelhouse = Path(self.temp_dir) / "out_wheelhouse"

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def _create_dummy_wheel(self, directory, name="foo-1.0-py3-none-any.whl"):
        wheel_path = directory / name
        with zipfile.ZipFile(wheel_path, "w") as zf:
            zf.writestr("foo-1.0.dist-info/METADATA", "Name: foo\nVersion: 1.0\n")
            zf.writestr("foo-1.0.dist-info/WHEEL", "Wheel-Version: 1.0\n")
            zf.writestr("foo-1.0.dist-info/RECORD", "")
            zf.writestr("foo/__init__.py", "")
        return wheel_path

    @patch("subprocess.check_call")
    def test_in_wheelhouse_sets_env(self, mock_check_call):
        """--in-wheelhouse should find the wheel and set PYCROSS_WHEEL_FILE."""
        self._create_dummy_wheel(self.in_wheelhouse)

        from pycross.private.build.tools.wheel_transformer import main
        with patch("sys.argv", [
            "wheel_transformer",
            "--in-wheelhouse", str(self.in_wheelhouse),
            "--out-wheelhouse", str(self.out_wheelhouse),
            "--tool", "/bin/true",
        ]):
            # main() will call subprocess.check_call then look for output
            # We need to create output in out_wheelhouse before glob runs
            def create_output(*args, **kwargs):
                self.out_wheelhouse.mkdir(exist_ok=True)
                self._create_dummy_wheel(self.out_wheelhouse, "foo-1.0-py3-none-any.whl")

            mock_check_call.side_effect = create_output
            main()

            # Verify subprocess was called with proper env
            call_args = mock_check_call.call_args
            env = call_args[1]["env"]
            self.assertIn("PYCROSS_WHEEL_FILE", env)
            self.assertTrue(env["PYCROSS_WHEEL_FILE"].endswith(".whl"))
            self.assertEqual(env["PYCROSS_WHEEL_OUTPUT_ROOT"], str(self.out_wheelhouse))

    def test_missing_in_wheelhouse_errors(self):
        """--in-wheelhouse is required; missing it should error."""
        from pycross.private.build.tools.wheel_transformer import main
        with patch("sys.argv", [
            "wheel_transformer",
            "--out-wheelhouse", str(self.out_wheelhouse),
            "--tool", "/bin/true",
        ]):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertNotEqual(cm.exception.code, 0)

    def test_empty_wheelhouse_errors(self):
        """--in-wheelhouse with no .whl files should error."""
        from pycross.private.build.tools.wheel_transformer import main
        with patch("sys.argv", [
            "wheel_transformer",
            "--in-wheelhouse", str(self.in_wheelhouse),
            "--out-wheelhouse", str(self.out_wheelhouse),
            "--tool", "/bin/true",
        ]):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertNotEqual(cm.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
