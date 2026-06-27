import sys
import tarfile
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock
from unittest.mock import patch

from private.tools.generate_cargo_lock import derive_default_output
from private.tools.generate_cargo_lock import main


class GenerateCargoLockTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def create_sdist(self, filename, files):
        path = self.temp_path / filename
        with tarfile.open(path, "w:gz") as tar:
            for name, content in files.items():
                file_path = self.temp_path / "tmp_file"
                with open(file_path, "w") as f:
                    f.write(content)
                tar.add(file_path, arcname=name)
        return path

    def test_derive_default_output(self):
        self.assertEqual(derive_default_output(Path("foo-1.0.tar.gz")), "foo@1.0.lock")
        self.assertEqual(derive_default_output(Path("foo_bar-1.0.tgz")), "foo-bar@1.0.lock")
        self.assertEqual(derive_default_output(Path("foo.tar")), "Cargo.lock")

    @patch("subprocess.run")
    def test_main(self, mock_run):
        # We simulate cargo generate-lockfile creating the lockfile.
        def side_effect(args, cwd, check):
            (cwd / "Cargo.lock").write_text("lockfile contents")
            return MagicMock()

        mock_run.side_effect = side_effect

        sdist = self.create_sdist(
            "mypkg-1.0.tar.gz",
            {
                "mypkg-1.0/Cargo.toml": "...",
                "mypkg-1.0/src/lib.rs": "...",
            },
        )

        output_lock = self.temp_path / "mypkg@1.0.lock"

        test_args = [
            "generate_cargo_lock.py",
            "--sdist",
            str(sdist),
            "--output",
            str(output_lock),
            "--cargo",
            "dummy_cargo",
        ]

        with patch.object(sys, "argv", test_args):
            main()

        self.assertTrue(output_lock.exists())
        self.assertEqual(output_lock.read_text(), "lockfile contents")

    @patch("subprocess.run")
    def test_main_pyproject_manifest_path(self, mock_run):
        # We simulate cargo generate-lockfile creating the lockfile.
        def side_effect(args, cwd, check):
            (cwd / "Cargo.lock").write_text("lockfile contents")
            return MagicMock()

        mock_run.side_effect = side_effect

        sdist = self.create_sdist(
            "mypkg-1.0.tar.gz",
            {
                "mypkg-1.0/pyproject.toml": '[tool.maturin]\nmanifest-path = "rust/Cargo.toml"\n',
                "mypkg-1.0/rust/Cargo.toml": "...",
                "mypkg-1.0/rust/src/lib.rs": "...",
            },
        )

        output_lock = self.temp_path / "mypkg@1.0.lock"

        test_args = [
            "generate_cargo_lock.py",
            "--sdist",
            str(sdist),
            "--output",
            str(output_lock),
            "--cargo",
            "dummy_cargo",
        ]

        with patch.object(sys, "argv", test_args):
            main()

        self.assertTrue(output_lock.exists())
        self.assertEqual(output_lock.read_text(), "lockfile contents")

    @patch("sys.exit")
    def test_main_no_cargo_toml(self, mock_exit):
        sdist = self.create_sdist(
            "mypkg-1.0.tar.gz",
            {
                "mypkg-1.0/README.md": "...",
            },
        )

        output_lock = self.temp_path / "mypkg@1.0.lock"

        test_args = [
            "generate_cargo_lock.py",
            "--sdist",
            str(sdist),
            "--output",
            str(output_lock),
            "--cargo",
            "dummy_cargo",
        ]

        mock_exit.side_effect = SystemExit(1)
        with patch.object(sys, "argv", test_args):
            with self.assertRaises(SystemExit):
                main()

        mock_exit.assert_called_with(1)

    @patch("subprocess.run")
    @patch("sys.exit")
    def test_main_cargo_fails(self, mock_exit, mock_run):
        import subprocess

        mock_run.side_effect = subprocess.CalledProcessError(1, "cargo")

        sdist = self.create_sdist(
            "mypkg-1.0.tar.gz",
            {
                "mypkg-1.0/Cargo.toml": "...",
            },
        )

        output_lock = self.temp_path / "mypkg@1.0.lock"

        test_args = [
            "generate_cargo_lock.py",
            "--sdist",
            str(sdist),
            "--output",
            str(output_lock),
            "--cargo",
            "dummy_cargo",
        ]

        mock_exit.side_effect = SystemExit(1)
        with patch.object(sys, "argv", test_args):
            with self.assertRaises(SystemExit):
                main()

        mock_exit.assert_called_with(1)


if __name__ == "__main__":
    unittest.main()
