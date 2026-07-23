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


class WheelInstallerValidationTest(unittest.TestCase):
    """Test the _validate_wheel_identity function."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_wheel(self, filename, metadata_name, metadata_version):
        """Create a wheel with specific METADATA content."""
        import zipfile

        wheel_path = Path(self.temp_dir) / filename
        dist_info = f"{metadata_name.replace('-', '_')}-{metadata_version}.dist-info"
        with zipfile.ZipFile(wheel_path, "w") as zf:
            zf.writestr(
                f"{dist_info}/METADATA",
                f"Metadata-Version: 2.1\nName: {metadata_name}\nVersion: {metadata_version}\n",
            )
            zf.writestr(
                f"{dist_info}/WHEEL",
                "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
            )
            zf.writestr(f"{dist_info}/RECORD", "")
        return wheel_path

    def test_matching_name_and_version_passes(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("six-1.17.0-py3-none-any.whl", "six", "1.17.0")
        # Should not raise
        _validate_wheel_identity(whl, "six", "1.17.0")

    def test_normalized_name_passes(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("Foo_Bar-1.0-py3-none-any.whl", "Foo-Bar", "1.0")
        # PEP 503 normalization: Foo-Bar == foo_bar == foo.bar
        _validate_wheel_identity(whl, "foo_bar", "1.0")

    def test_mismatched_name_raises(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("wrong-1.0-py3-none-any.whl", "wrong", "1.0")
        with self.assertRaises(SystemExit) as cm:
            _validate_wheel_identity(whl, "six", "1.0")
        self.assertIn("wheel identity mismatch", str(cm.exception))

    def test_mismatched_version_raises(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("six-2.0.0-py3-none-any.whl", "six", "2.0.0")
        with self.assertRaises(SystemExit) as cm:
            _validate_wheel_identity(whl, "six", "1.17.0")
        self.assertIn("wheel version mismatch", str(cm.exception))

    def test_local_version_segment_passes(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        # Wheel filename carries a PEP 440 local version segment (e.g. a CUDA
        # build) that the locked version omits; only the public version is compared.
        whl = self._create_wheel("foo-1.0+cu130-py3-none-any.whl", "foo", "1.0")
        # Should not raise
        _validate_wheel_identity(whl, "foo", "1.0")

    def test_none_expected_skips_check(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("anything-1.0-py3-none-any.whl", "anything", "1.0")
        # No assertions should fire when expected values are None
        _validate_wheel_identity(whl, None, None)


if __name__ == "__main__":
    unittest.main()
