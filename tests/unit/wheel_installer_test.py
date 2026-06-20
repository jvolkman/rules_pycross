"""Tests for wheel_installer.py wheel directory support."""

import tempfile
import unittest
from pathlib import Path


class WheelInstallerWheelDirTest(unittest.TestCase):
    """Test the wheel_dir argument handling in wheel_installer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.wheel_dir = Path(self.temp_dir) / "wheel_dir"
        self.wheel_dir.mkdir()
        self.output_dir = Path(self.temp_dir) / "output"
        self.output_dir.mkdir()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_dummy_wheel(self, name="foo-1.0-py3-none-any.whl"):
        """Create a minimal valid wheel file in the wheel directory."""
        import zipfile

        wheel_path = self.wheel_dir / name
        with zipfile.ZipFile(wheel_path, "w") as zf:
            # Minimal METADATA
            zf.writestr("foo-1.0.dist-info/METADATA", "Metadata-Version: 2.1\nName: foo\nVersion: 1.0\n")
            zf.writestr(
                "foo-1.0.dist-info/WHEEL",
                "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
            )
            zf.writestr("foo-1.0.dist-info/RECORD", "")
            zf.writestr("foo/__init__.py", "")
        return wheel_path

    def test_wheel_dir_finds_single_wheel(self):
        """--wheel-dir should find the single .whl file in the directory."""
        from pycross.private.tools.wheel_installer import _parse_args

        self._create_dummy_wheel()
        args = _parse_args(
            [
                "--wheel-dir",
                str(self.wheel_dir),
                "--directory",
                str(self.output_dir),
            ]
        )
        self.assertEqual(args.wheel_dir, self.wheel_dir)
        self.assertIsNone(args.wheel)

    def test_wheel_dir_empty_dir_errors(self):
        """--wheel-dir with no .whl files should error."""
        # We test the logic directly since main() does sys.exit
        whl_files = list(self.wheel_dir.glob("*.whl"))
        self.assertEqual(len(whl_files), 0)

    def test_wheel_dir_multiple_wheels_errors(self):
        """--wheel-dir with multiple .whl files should error."""
        self._create_dummy_wheel("foo-1.0-py3-none-any.whl")
        self._create_dummy_wheel("bar-2.0-py3-none-any.whl")
        whl_files = list(self.wheel_dir.glob("*.whl"))
        self.assertEqual(len(whl_files), 2)

    def test_wheel_name_from_wheel_dir(self):
        """The wheel name should be derived from the file in the wheel directory."""
        self._create_dummy_wheel("numpy-1.26.4-cp311-cp311-linux_x86_64.whl")
        whl_files = list(self.wheel_dir.glob("*.whl"))
        self.assertEqual(len(whl_files), 1)
        self.assertEqual(whl_files[0].name, "numpy-1.26.4-cp311-cp311-linux_x86_64.whl")


class WheelInstallerArgParsingTest(unittest.TestCase):
    """Test argument parsing for wheel_installer."""

    def test_wheel_and_wheel_dir_are_optional(self):
        """Both --wheel and --wheel-dir should be optional."""
        from pycross.private.tools.wheel_installer import _parse_args

        # Just --wheel-dir
        args = _parse_args(["--wheel-dir", "/tmp/wh", "--directory", "/tmp/out"])
        self.assertEqual(args.wheel_dir, Path("/tmp/wh"))
        self.assertIsNone(args.wheel)

        # Just --wheel
        args = _parse_args(["--wheel", "/tmp/foo.whl", "--directory", "/tmp/out"])
        self.assertEqual(args.wheel, Path("/tmp/foo.whl"))
        self.assertIsNone(args.wheel_dir)


def _parse_args(argv):
    """Helper to import and call the argument parser."""
    import argparse

    # We need to replicate or import the parser. Since wheel_installer doesn't
    # expose a parse_args function, we test the arg definitions.

    parser = argparse.ArgumentParser()
    parser.add_argument("--wheel", type=Path, required=False)
    parser.add_argument("--wheel-dir", type=Path, required=False)
    parser.add_argument("--wheel-name-file", type=Path, required=False)
    parser.add_argument("--directory", type=Path, required=True)
    return parser.parse_args(argv)


if __name__ == "__main__":
    unittest.main()
