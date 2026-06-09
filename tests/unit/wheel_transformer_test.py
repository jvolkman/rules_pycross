"""Tests for wheel_transformer.py wheel directory support."""

import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


class WheelTransformerArgsTest(unittest.TestCase):
    """Test argument parsing for wheel_transformer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.in_wheel_dir = Path(self.temp_dir) / "in_wheel_dir"
        self.in_wheel_dir.mkdir()
        self.out_wheel_dir = Path(self.temp_dir) / "out_wheel_dir"

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
    def test_in_wheel_dir_sets_env(self, mock_check_call):
        """--in-wheel-dir should find the wheel and set PYCROSS_WHEEL_FILE."""
        self._create_dummy_wheel(self.in_wheel_dir)

        from pycross.private.build.tools.wheel_transformer import main

        with patch(
            "sys.argv",
            [
                "wheel_transformer",
                "--in-wheel-dir",
                str(self.in_wheel_dir),
                "--out-wheel-dir",
                str(self.out_wheel_dir),
                "--tool",
                "/bin/true",
            ],
        ):
            # main() will call subprocess.check_call then look for output
            # We need to create output in out_wheel_dir before glob runs
            def create_output(*args, **kwargs):
                self.out_wheel_dir.mkdir(exist_ok=True)
                self._create_dummy_wheel(self.out_wheel_dir, "foo-1.0-py3-none-any.whl")

            mock_check_call.side_effect = create_output
            main()

            # Verify subprocess was called with proper env
            call_args = mock_check_call.call_args
            env = call_args[1]["env"]
            self.assertIn("PYCROSS_WHEEL_FILE", env)
            self.assertTrue(env["PYCROSS_WHEEL_FILE"].endswith(".whl"))
            self.assertEqual(env["PYCROSS_WHEEL_OUTPUT_ROOT"], str(self.out_wheel_dir))

    def test_missing_in_wheel_dir_errors(self):
        """--in-wheel-dir is required; missing it should error."""
        from pycross.private.build.tools.wheel_transformer import main

        with patch(
            "sys.argv",
            [
                "wheel_transformer",
                "--out-wheel-dir",
                str(self.out_wheel_dir),
                "--tool",
                "/bin/true",
            ],
        ):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertNotEqual(cm.exception.code, 0)

    def test_empty_wheel_dir_errors(self):
        """--in-wheel-dir with no .whl files should error."""
        from pycross.private.build.tools.wheel_transformer import main

        with patch(
            "sys.argv",
            [
                "wheel_transformer",
                "--in-wheel-dir",
                str(self.in_wheel_dir),
                "--out-wheel-dir",
                str(self.out_wheel_dir),
                "--tool",
                "/bin/true",
            ],
        ):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertNotEqual(cm.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
