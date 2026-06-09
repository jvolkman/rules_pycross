"""Tests for repair_wheel_hook.py wheel directory support."""

import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


class RepairWheelHookArgsTest(unittest.TestCase):
    """Test the wheel_dir-based repair_wheel_hook."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.wheel_dir = Path(self.temp_dir) / "wheel_dir"
        self.wheel_dir.mkdir()
        self.out_wheel_dir = Path(self.temp_dir) / "out_wheel_dir"
        self.out_wheel_dir.mkdir()

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def _create_dummy_wheel(self, directory, name="foo-1.0-py3-none-any.whl"):
        wheel_path = directory / name
        with zipfile.ZipFile(wheel_path, "w") as zf:
            zf.writestr("foo-1.0.dist-info/METADATA", "Name: foo\nVersion: 1.0\n")
            zf.writestr("foo-1.0.dist-info/WHEEL", "Wheel-Version: 1.0\nTag: py3-none-any\n")
            zf.writestr("foo-1.0.dist-info/RECORD", "")
            zf.writestr("foo/__init__.py", "")
        return wheel_path

    @patch("subprocess.check_call")
    def test_wheel_dir_input_finds_wheel(self, mock_check_call):
        """--wheel-dir should find the .whl file and pass it to repairwheel."""
        self._create_dummy_wheel(self.wheel_dir)

        # repairwheel creates output in --output-dir
        def fake_repair(*args, **kwargs):
            cmd = args[0]
            # Find --output-dir in the command
            for i, arg in enumerate(cmd):
                if arg == "--output-dir":
                    out_dir = Path(cmd[i + 1])
                    out_dir.mkdir(parents=True, exist_ok=True)
                    self._create_dummy_wheel(out_dir)
                    break

        mock_check_call.side_effect = fake_repair

        from pycross.private.build.tools.repair_wheel_hook import main

        with patch(
            "sys.argv",
            [
                "repair_wheel_hook",
                "--wheel-dir",
                str(self.wheel_dir),
                "--out-wheel-dir",
                str(self.out_wheel_dir),
            ],
        ):
            main()

        # Verify repairwheel was called with the wheel file
        call_args = mock_check_call.call_args[0][0]
        wheel_arg = call_args[3]  # repairwheel <wheel_file> --output-dir ...
        self.assertTrue(wheel_arg.endswith(".whl"))

    def test_empty_wheel_dir_errors(self):
        """--wheel-dir with no .whl files should exit with error."""
        from pycross.private.build.tools.repair_wheel_hook import main

        with patch(
            "sys.argv",
            [
                "repair_wheel_hook",
                "--wheel-dir",
                str(self.wheel_dir),
                "--out-wheel-dir",
                str(self.out_wheel_dir),
            ],
        ):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertNotEqual(cm.exception.code, 0)

    @patch("subprocess.check_call")
    def test_lib_dirs_passed_through(self, mock_check_call):
        """--lib-dir arguments should be passed to repairwheel."""
        self._create_dummy_wheel(self.wheel_dir)

        def fake_repair(*args, **kwargs):
            cmd = args[0]
            for i, arg in enumerate(cmd):
                if arg == "--output-dir":
                    out_dir = Path(cmd[i + 1])
                    out_dir.mkdir(parents=True, exist_ok=True)
                    self._create_dummy_wheel(out_dir)
                    break

        mock_check_call.side_effect = fake_repair

        from pycross.private.build.tools.repair_wheel_hook import main

        with patch(
            "sys.argv",
            [
                "repair_wheel_hook",
                "--wheel-dir",
                str(self.wheel_dir),
                "--out-wheel-dir",
                str(self.out_wheel_dir),
                "--lib-dir",
                "/usr/lib",
                "--lib-dir",
                "/opt/lib",
            ],
        ):
            main()

        call_args = mock_check_call.call_args[0][0]
        # Check --lib-dir flags are present
        lib_dir_indices = [i for i, a in enumerate(call_args) if a == "--lib-dir"]
        self.assertEqual(len(lib_dir_indices), 2)


if __name__ == "__main__":
    unittest.main()
