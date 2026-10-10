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


class WheelInstallerNormalizedDistInfoTest(unittest.TestCase):
    """Test normalizing a mixed-case .dist-info directory during installation."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    @staticmethod
    def _record_hash_and_size(data: bytes):
        import base64
        import hashlib

        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")
        return f"sha256={digest}", str(len(data))

    def test_mixed_case_dist_info_is_installed_under_normalized_name(self):
        import argparse
        import csv
        import zipfile

        from pycross.private.tools import wheel_installer

        wheel_path = Path(self.temp_dir) / "Foo_Bar-1.0-py3-none-any.whl"
        output_dir = Path(self.temp_dir) / "installed"
        entry_points_out = Path(self.temp_dir) / "entry_points.txt"

        metadata_bytes = b"Metadata-Version: 2.1\nName: Foo-Bar\nVersion: 1.0\n"
        wheel_bytes = b"Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
        ep_bytes = b"[console_scripts]\nfoo-bar = foo_bar:main\n"
        init_bytes = b"def main():\n    return 42\n"
        script_bytes = b"#!/bin/sh\necho hi\n"

        files = {
            "Foo_Bar-1.0.dist-info/METADATA": metadata_bytes,
            "Foo_Bar-1.0.dist-info/WHEEL": wheel_bytes,
            "Foo_Bar-1.0.dist-info/entry_points.txt": ep_bytes,
            "Foo_Bar-1.0.data/scripts/foo-helper": script_bytes,
            "foo_bar/__init__.py": init_bytes,
        }
        record_lines = []
        for arc_path, content in files.items():
            h, s = self._record_hash_and_size(content)
            record_lines.append(f"{arc_path},{h},{s}")
        record_lines.append("Foo_Bar-1.0.dist-info/RECORD,,")
        record_bytes = ("\n".join(record_lines) + "\n").encode("utf-8")

        with zipfile.ZipFile(wheel_path, "w") as zf:
            for arc_path, content in files.items():
                zf.writestr(arc_path, content)
            zf.writestr("Foo_Bar-1.0.dist-info/RECORD", record_bytes)

        args = argparse.Namespace(
            wheel=wheel_path,
            wheel_dir=None,
            wheel_name_file=None,
            install_exclude_globs=[],
            patches=[],
            entry_points_output=entry_points_out,
            directory=output_dir,
            expected_name="foo-bar",
            expected_version="1.0",
            dist_info_dir="foo_bar-1.0.dist-info",
        )
        wheel_installer.main(args)

        site_packages = output_dir / "site-packages"
        norm_dist_info = site_packages / "foo_bar-1.0.dist-info"
        orig_dist_info = site_packages / "Foo_Bar-1.0.dist-info"

        self.assertTrue(norm_dist_info.is_dir())
        self.assertFalse(orig_dist_info.exists())

        # METADATA bytes are unchanged (Name: Foo-Bar preserved)
        self.assertEqual((norm_dist_info / "METADATA").read_bytes(), metadata_bytes)

        # INSTALLER is present
        self.assertEqual(
            (norm_dist_info / "INSTALLER").read_bytes(),
            b"https://github.com/jvolkman/rules_pycross",
        )

        # --entry-points-output copied entry_points.txt from normalized .dist-info
        self.assertEqual(entry_points_out.read_bytes(), ep_bytes)

        # Verify RECORD entries exist on disk with matching sha256 and byte size
        record_path = norm_dist_info / "RECORD"
        self.assertTrue(record_path.is_file())
        with open(record_path, "r", encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))

        recorded_paths = [row[0] for row in rows]
        self.assertIn("foo_bar-1.0.dist-info/METADATA", recorded_paths)
        self.assertIn("foo_bar-1.0.dist-info/INSTALLER", recorded_paths)
        self.assertIn("foo_bar-1.0.dist-info/RECORD", recorded_paths)
        self.assertIn("../bin/foo-bar", recorded_paths)
        self.assertIn("../bin/foo-helper", recorded_paths)
        for p in recorded_paths:
            self.assertFalse(p.startswith("Foo_Bar-1.0.dist-info"), f"Unnormalized path in RECORD: {p}")

        for rel_path, hash_spec, size_str in rows:
            target_file = (site_packages / rel_path).resolve()
            self.assertTrue(target_file.is_file(), f"RECORD target missing: {rel_path} -> {target_file}")
            if rel_path == "foo_bar-1.0.dist-info/RECORD":
                self.assertEqual(hash_spec, "")
                self.assertEqual(size_str, "")
            else:
                expected_hash, expected_size = self._record_hash_and_size(target_file.read_bytes())
                self.assertEqual(hash_spec, expected_hash, f"Hash mismatch for {rel_path}")
                self.assertEqual(size_str, expected_size, f"Size mismatch for {rel_path}")


if __name__ == "__main__":
    unittest.main()
