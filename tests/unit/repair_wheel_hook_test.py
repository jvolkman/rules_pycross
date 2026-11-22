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

    def _create_dummy_wheel(self, directory, name="foo-1.0-cp312-cp312-linux_x86_64.whl"):
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

    @patch("subprocess.check_call")
    def test_excludes_passed_through(self, mock_check_call):
        """--exclude arguments should be passed to repairwheel in order."""
        self._create_dummy_wheel(self.wheel_dir)

        def fake_repair(*args, **kwargs):
            cmd = args[0]
            for i, arg in enumerate(cmd):
                if arg == "--output-dir":
                    self._create_dummy_wheel(Path(cmd[i + 1]))
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
                "--exclude",
                "libtorch*.so",
                "--exclude",
                "libc10*.so",
            ],
        ):
            main()

        call_args = mock_check_call.call_args[0][0]
        exclude_indices = [i for i, arg in enumerate(call_args) if arg == "--exclude"]
        self.assertEqual(
            [call_args[i + 1] for i in exclude_indices],
            ["libtorch*.so", "libc10*.so"],
        )

    @patch("subprocess.check_call")
    def test_pure_python_wheel_skips_repairwheel_and_validates_tags(self, mock_check_call):
        """Pure-Python -none-any.whl copies directly without spawning repairwheel, and still checks tags."""
        import io
        import json
        import os

        self._create_dummy_wheel(self.wheel_dir, name="foo-1.0-py3-none-any.whl")
        target_env = Path(self.temp_dir) / "target.json"
        target_env.write_text(json.dumps({"compatibility_tags": ["cp312-cp312-linux_x86_64", "py3-none-any"]}))

        from pycross.private.build.tools.repair_wheel_hook import main

        argv = [
            "repair_wheel_hook",
            "--wheel-dir",
            str(self.wheel_dir),
            "--out-wheel-dir",
            str(self.out_wheel_dir),
            "--target-environment",
            str(target_env),
        ]
        with patch("sys.argv", argv), patch.dict(os.environ, {}, clear=False):
            os.environ.pop("REPAIRWHEEL_PYTHONPATH", None)
            main()

        mock_check_call.assert_not_called()
        out_wheel = self.out_wheel_dir / "foo-1.0-py3-none-any.whl"
        self.assertTrue(out_wheel.is_file())
        with zipfile.ZipFile(out_wheel) as zf:
            record = zf.read("foo-1.0.dist-info/RECORD").decode("utf-8")
            self.assertIn("foo/__init__.py,sha256=", record)
            self.assertEqual(zf.getinfo("foo/__init__.py").date_time, (1980, 1, 1, 0, 0, 0))

        # Incompatible target tags still fail and print sample expected tags.
        target_env.write_text(
            json.dumps(
                {
                    "compatibility_tags": [
                        "cp312-cp312-linux_x86_64",
                        "cp312-abi3-linux_x86_64",
                        "cp312-none-linux_x86_64",
                        "py312-none-linux_x86_64",
                        "py3-none-linux_x86_64",
                        "cp311-abi3-linux_x86_64",
                    ]
                }
            )
        )
        stderr = io.StringIO()
        with patch("sys.argv", argv), patch("sys.stderr", stderr), patch.dict(os.environ, {}, clear=False):
            os.environ.pop("REPAIRWHEEL_PYTHONPATH", None)
            with self.assertRaises(SystemExit) as cm:
                main()
        self.assertNotEqual(cm.exception.code, 0)
        self.assertIn("cp312-cp312-linux_x86_64", stderr.getvalue())
        self.assertIn("6 total", stderr.getvalue())

    @patch("subprocess.check_call")
    def test_pure_python_wheel_runs_repairwheel_with_custom_pythonpath(self, mock_check_call):
        """REPAIRWHEEL_PYTHONPATH disables the pure-Python fast path so custom overrides run."""
        import os

        self._create_dummy_wheel(self.wheel_dir, name="foo-1.0-py3-none-any.whl")

        from pycross.private.build.tools.repair_wheel_hook import main

        argv = [
            "repair_wheel_hook",
            "--wheel-dir",
            str(self.wheel_dir),
            "--out-wheel-dir",
            str(self.out_wheel_dir),
        ]
        with patch("sys.argv", argv), patch.dict(os.environ, {"REPAIRWHEEL_PYTHONPATH": "/custom/site-packages"}):
            main()

        mock_check_call.assert_called_once()


class AuditwheelPlatTest(unittest.TestCase):
    def test_prefers_highest_musllinux(self):
        from pycross.private.build.tools.repair_wheel_hook import auditwheel_plat_from_tags

        tags = [
            "cp314-cp314-musllinux_1_2_x86_64",
            "cp314-cp314-musllinux_1_0_x86_64",
            "cp314-cp314-musllinux_1_1_x86_64",
            "cp314-abi3-musllinux_1_2_x86_64",
            "py3-none-any",
        ]
        self.assertEqual(auditwheel_plat_from_tags(tags), "musllinux_1_2_x86_64")

    def test_manylinux(self):
        from pycross.private.build.tools.repair_wheel_hook import auditwheel_plat_from_tags

        tags = ["cp314-cp314-manylinux_2_17_x86_64", "cp314-cp314-manylinux_2_28_x86_64", "py3-none-any"]
        self.assertEqual(auditwheel_plat_from_tags(tags), "manylinux_2_28_x86_64")

    def test_non_linux(self):
        from pycross.private.build.tools.repair_wheel_hook import auditwheel_plat_from_tags

        self.assertIsNone(auditwheel_plat_from_tags(["cp314-cp314-macosx_14_0_arm64", "py3-none-any"]))
        self.assertIsNone(auditwheel_plat_from_tags([]))

    @patch("subprocess.check_call")
    def test_target_environment_sets_auditwheel_plat(self, mock_check_call):
        """AUDITWHEEL_PLAT comes from the target tags and is set before repairwheel runs."""
        import json
        import os

        temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, temp_dir)
        wheel_dir = temp_dir / "in"
        wheel_dir.mkdir()
        out_dir = temp_dir / "out"
        out_dir.mkdir()
        wheel_name = "foo-1.0-cp314-cp314-musllinux_1_2_x86_64.whl"
        (wheel_dir / wheel_name).write_bytes(b"")
        target_env = temp_dir / "target.json"
        target_env.write_text(
            json.dumps({"compatibility_tags": ["cp314-cp314-musllinux_1_1_x86_64", "cp314-cp314-musllinux_1_2_x86_64"]})
        )

        seen_env = {}

        def fake_repair(cmd, env):
            seen_env.update(env)
            (out_dir / wheel_name).write_bytes(b"")

        mock_check_call.side_effect = fake_repair

        from pycross.private.build.tools.repair_wheel_hook import main

        argv = [
            "repair_wheel_hook",
            "--wheel-dir",
            str(wheel_dir),
            "--out-wheel-dir",
            str(out_dir),
            "--target-environment",
            str(target_env),
        ]
        with patch("sys.argv", argv), patch.dict(os.environ, {}, clear=False):
            os.environ.pop("AUDITWHEEL_PLAT", None)
            main()
        self.assertEqual(seen_env.get("AUDITWHEEL_PLAT"), "musllinux_1_2_x86_64")

        # An explicit AUDITWHEEL_PLAT wins.
        seen_env.clear()
        with patch("sys.argv", argv), patch.dict(os.environ, {"AUDITWHEEL_PLAT": "musllinux_1_1_x86_64"}):
            main()
        self.assertEqual(seen_env.get("AUDITWHEEL_PLAT"), "musllinux_1_1_x86_64")


if __name__ == "__main__":
    unittest.main()
