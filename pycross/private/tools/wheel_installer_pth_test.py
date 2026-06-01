import os
import pathlib
import shutil
import sys
import tempfile
import unittest

from pycross.private.tools.wheel_installer import process_pth_files


class InstallationFixture:
    def __init__(self) -> None:
        self.path = pathlib.Path(tempfile.mkdtemp())

    def mkdir(self, relative_path: str) -> pathlib.Path:
        d = self.path / relative_path
        d.mkdir(parents=True, exist_ok=True)
        return d

    def write(self, relative_path: str, content: str) -> None:
        f = self.path / relative_path
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(content, encoding="utf-8")

    def touch(self, relative_path: str) -> None:
        f = self.path / relative_path
        f.parent.mkdir(parents=True, exist_ok=True)
        f.touch()

    def remove(self) -> None:
        shutil.rmtree(self.path)


class TestProcessPthFiles(unittest.TestCase):
    def setUp(self) -> None:
        self.installation_dir = InstallationFixture()

    def tearDown(self) -> None:
        self.installation_dir.remove()

    def test_creates_symlinks_for_pth_declared_subdir(self) -> None:
        self.installation_dir.mkdir("outer_pkg/inner_module")
        self.installation_dir.touch("outer_pkg/inner_module/__init__.py")
        self.installation_dir.write("outer_pkg.pth", "outer_pkg\n")

        process_pth_files(self.installation_dir.path)

        link = self.installation_dir.path / "inner_module"
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), os.path.join("outer_pkg", "inner_module"))

    def test_does_not_overwrite_existing_entry(self) -> None:
        self.installation_dir.mkdir("outer_pkg/inner_module")
        self.installation_dir.mkdir("inner_module")
        self.installation_dir.write("outer_pkg.pth", "outer_pkg\n")

        process_pth_files(self.installation_dir.path)

        self.assertFalse((self.installation_dir.path / "inner_module").is_symlink())

    def test_ignores_import_statement_lines(self) -> None:
        self.installation_dir.mkdir("outer_pkg/inner_module")
        self.installation_dir.write("outer_pkg.pth", "import sys; sys.path.append('/tmp')\n")

        process_pth_files(self.installation_dir.path)

        self.assertFalse((self.installation_dir.path / "inner_module").exists())
        self.assertFalse("/tmp" in sys.path)

    def test_ignores_absolute_paths(self) -> None:
        self.installation_dir.mkdir("outer_pkg/inner_module")
        abs_path = str(self.installation_dir.path / "outer_pkg")
        self.installation_dir.write("abs.pth", abs_path + "\n")

        process_pth_files(self.installation_dir.path)

        self.assertFalse((self.installation_dir.path / "inner_module").exists())

    def test_ignores_nonexistent_directory(self) -> None:
        self.installation_dir.write("missing.pth", "nonexistent\n")

        process_pth_files(self.installation_dir.path)

        self.assertFalse((self.installation_dir.path / "nonexistent").exists())

    def test_skips_dist_info_and_pycache(self) -> None:
        self.installation_dir.mkdir("pkg/some_pkg-1.0.dist-info")
        self.installation_dir.mkdir("pkg/__pycache__")
        self.installation_dir.mkdir("pkg/real_module")
        self.installation_dir.write("pkg.pth", "pkg\n")

        process_pth_files(self.installation_dir.path)

        self.assertFalse((self.installation_dir.path / "some_pkg-1.0.dist-info").exists())
        self.assertFalse((self.installation_dir.path / "__pycache__").is_symlink())
        self.assertTrue((self.installation_dir.path / "real_module").is_symlink())

    def test_multiple_pth_files(self) -> None:
        self.installation_dir.mkdir("pkg_a/module_a")
        self.installation_dir.mkdir("pkg_b/module_b")
        self.installation_dir.write("a.pth", "pkg_a\n")
        self.installation_dir.write("b.pth", "pkg_b\n")

        process_pth_files(self.installation_dir.path)

        self.assertTrue((self.installation_dir.path / "module_a").is_symlink())
        self.assertTrue((self.installation_dir.path / "module_b").is_symlink())

    def test_no_pth_files_does_nothing(self) -> None:
        self.installation_dir.mkdir("some_package")
        before = set(self.installation_dir.path.iterdir())

        process_pth_files(self.installation_dir.path)

        self.assertEqual(set(self.installation_dir.path.iterdir()), before)


if __name__ == "__main__":
    unittest.main()
