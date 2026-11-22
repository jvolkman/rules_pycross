import sys
import tarfile
import unittest
import zipfile
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
        self.assertEqual(derive_default_output(Path("foo_bar-2.0.zip")), "foo-bar@2.0.lock")
        self.assertEqual(derive_default_output(Path("foo.tar")), "Cargo.lock")

    @patch("subprocess.run")
    def test_main(self, mock_run):
        # We simulate cargo generate-lockfile creating the lockfile.
        def side_effect(*args, **kwargs):
            cwd = kwargs.get("cwd")

            # check_output calls run and passes stdout.
            # If it's a locate-project call, mock the output.
            if len(args) > 0 and "locate-project" in args[0]:
                mock = MagicMock()
                mock.stdout = str(cwd / "Cargo.toml")
                return mock

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
        def side_effect(*args, **kwargs):
            cwd = kwargs.get("cwd")

            if len(args) > 0 and "locate-project" in args[0]:
                mock = MagicMock()
                mock.stdout = str(cwd / "Cargo.toml")
                return mock

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

    @patch("subprocess.run")
    def test_main_zip_and_setuptools_rust(self, mock_run):
        captured_cwds = []

        def side_effect(*args, **kwargs):
            cwd = kwargs.get("cwd")
            captured_cwds.append(cwd)
            if len(args) > 0 and "locate-project" in args[0]:
                mock = MagicMock()
                mock.stdout = str(cwd / "Cargo.toml")
                return mock
            (cwd / "Cargo.lock").write_text("setuptools-rust lock")
            return MagicMock()

        mock_run.side_effect = side_effect

        sdist = self.temp_path / "cryptopkg-1.0.zip"
        with zipfile.ZipFile(sdist, "w") as zf:
            zf.writestr(
                "cryptopkg-1.0/pyproject.toml",
                '[[tool.setuptools-rust.ext-modules]]\ntarget = "cryptopkg._rust"\npath = "src/rust/Cargo.toml"\n',
            )
            zf.writestr("cryptopkg-1.0/src/rust/Cargo.toml", "[package]\nname = 'cryptopkg'\n")

        output_lock = self.temp_path / "cryptopkg@1.0.lock"
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
        self.assertEqual(output_lock.read_text(), "setuptools-rust lock")
        self.assertTrue(any(p.parts[-2:] == ("src", "rust") for p in captured_cwds))

    @patch("subprocess.run")
    def test_main_preserves_cargo_symlink_with_abspath(self, mock_run):
        import os

        captured_cmds = []

        def side_effect(*args, **kwargs):
            cwd = kwargs.get("cwd")
            captured_cmds.append(args[0])
            if len(args) > 0 and "locate-project" in args[0]:
                mock = MagicMock()
                mock.stdout = str(cwd / "Cargo.toml")
                return mock
            (cwd / "Cargo.lock").write_text("symlink lock")
            return MagicMock()

        mock_run.side_effect = side_effect

        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir()
        rustup = bin_dir / "rustup"
        rustup.write_text("#!/bin/sh\n")
        cargo_link = bin_dir / "cargo"
        cargo_link.symlink_to(rustup)

        sdist = self.create_sdist("mypkg-1.0.tar.gz", {"mypkg-1.0/Cargo.toml": "[package]\nname='a'\n"})
        output_lock = self.temp_path / "mypkg@1.0.lock"

        orig_cwd = Path.cwd()
        try:
            os.chdir(self.temp_path)
            test_args = [
                "generate_cargo_lock.py",
                "--sdist",
                str(sdist),
                "--output",
                str(output_lock),
                "--cargo",
                "./bin/cargo",
            ]
            with patch.object(sys, "argv", test_args):
                main()
        finally:
            os.chdir(orig_cwd)

        self.assertTrue(captured_cmds)
        # Must be resolved to an absolute path without dereferencing cargo -> rustup.
        self.assertEqual(captured_cmds[0][0], os.path.abspath(str(cargo_link)))
        self.assertTrue(captured_cmds[0][0].endswith("cargo"))


if __name__ == "__main__":
    unittest.main()
