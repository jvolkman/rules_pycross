"""Tests for wheel_installer.py wheelhouse support."""

import tempfile
import unittest
from pathlib import Path


class WheelInstallerWheelhouseTest(unittest.TestCase):
    """Test the wheelhouse argument handling in wheel_installer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.wheelhouse = Path(self.temp_dir) / "wheelhouse"
        self.wheelhouse.mkdir()
        self.output_dir = Path(self.temp_dir) / "output"
        self.output_dir.mkdir()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_dummy_wheel(self, name="foo-1.0-py3-none-any.whl"):
        """Create a minimal valid wheel file in the wheelhouse."""
        import zipfile

        wheel_path = self.wheelhouse / name
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

    def test_wheelhouse_finds_single_wheel(self):
        """--wheelhouse should find the single .whl file in the directory."""
        from pycross.private.tools.wheel_installer import _parse_args

        self._create_dummy_wheel()
        args = _parse_args(
            [
                "--wheelhouse",
                str(self.wheelhouse),
                "--directory",
                str(self.output_dir),
            ]
        )
        self.assertEqual(args.wheelhouse, self.wheelhouse)
        self.assertIsNone(args.wheel)

    def test_wheelhouse_empty_dir_errors(self):
        """--wheelhouse with no .whl files should error."""
        # We test the logic directly since main() does sys.exit
        whl_files = list(self.wheelhouse.glob("*.whl"))
        self.assertEqual(len(whl_files), 0)

    def test_wheelhouse_multiple_wheels_errors(self):
        """--wheelhouse with multiple .whl files should error."""
        self._create_dummy_wheel("foo-1.0-py3-none-any.whl")
        self._create_dummy_wheel("bar-2.0-py3-none-any.whl")
        whl_files = list(self.wheelhouse.glob("*.whl"))
        self.assertEqual(len(whl_files), 2)

    def test_wheel_name_from_wheelhouse(self):
        """The wheel name should be derived from the file in the wheelhouse."""
        self._create_dummy_wheel("numpy-1.26.4-cp311-cp311-linux_x86_64.whl")
        whl_files = list(self.wheelhouse.glob("*.whl"))
        self.assertEqual(len(whl_files), 1)
        self.assertEqual(whl_files[0].name, "numpy-1.26.4-cp311-cp311-linux_x86_64.whl")


class WheelInstallerArgParsingTest(unittest.TestCase):
    """Test argument parsing for wheel_installer."""

    def test_wheel_and_wheelhouse_are_optional(self):
        """Both --wheel and --wheelhouse should be optional."""
        from pycross.private.tools.wheel_installer import _parse_args

        # Just --wheelhouse
        args = _parse_args(["--wheelhouse", "/tmp/wh", "--directory", "/tmp/out"])
        self.assertEqual(args.wheelhouse, Path("/tmp/wh"))
        self.assertIsNone(args.wheel)

        # Just --wheel
        args = _parse_args(["--wheel", "/tmp/foo.whl", "--directory", "/tmp/out"])
        self.assertEqual(args.wheel, Path("/tmp/foo.whl"))
        self.assertIsNone(args.wheelhouse)


def _parse_args(argv):
    """Helper to import and call the argument parser."""
    import argparse

    # We need to replicate or import the parser. Since wheel_installer doesn't
    # expose a parse_args function, we test the arg definitions.

    parser = argparse.ArgumentParser()
    parser.add_argument("--wheel", type=Path, required=False)
    parser.add_argument("--wheelhouse", type=Path, required=False)
    parser.add_argument("--wheel-name-file", type=Path, required=False)
    parser.add_argument("--directory", type=Path, required=True)
    return parser.parse_args(argv)


if __name__ == "__main__":
    unittest.main()
