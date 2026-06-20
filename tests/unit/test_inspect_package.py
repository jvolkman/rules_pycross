import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

import pycross.private.tools.inspect_package as ip


class TestInspectPackage(unittest.TestCase):
    def test_get_archive_file_content_zip(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "test.zip"
            with zipfile.ZipFile(p, "w") as zf:
                zf.writestr("test/pyproject.toml", "content")

            content = ip._get_archive_file_content(p, "pyproject.toml")
            self.assertEqual(content, "content")

    def test_get_archive_file_content_tar(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "test.tar.gz"
            with tarfile.open(p, "w:gz") as tf:
                import io

                info = tarfile.TarInfo("test/pyproject.toml")
                data = b"tar_content"
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))

            content = ip._get_archive_file_content(p, "pyproject.toml")
            self.assertEqual(content, "tar_content")

    def test_inspect_sdist(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "test-1.0.tar.gz"
            with tarfile.open(p, "w:gz") as tf:
                import io

                info = tarfile.TarInfo("test-1.0/pyproject.toml")
                data = b'[build-system]\nrequires = ["hatchling"]\nbuild-backend = "hatchling.build"\n'
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))

            result = ip.inspect_sdist(p)
            self.assertEqual(result["build_backend"], "hatchling.build")
            self.assertEqual(result["build_requires"], ["hatchling"])

    def test_inspect_wheel(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "test-1.0-py3-none-any.whl"
            with zipfile.ZipFile(p, "w") as zf:
                zf.writestr("test-1.0.dist-info/entry_points.txt", "[console_scripts]\nfoo = foo.bar:main\n")

            result = ip.inspect_wheel(p)
            self.assertEqual(result["console_scripts"], ["foo"])

    def test_validate_requirements(self):
        try:
            from packaging.requirements import Requirement  # noqa: F401
        except ImportError:
            self.fail("packaging module could not be imported!")

        requires = ["numpy>=1.20"]
        package_versions = {"numpy": "1.21.0"}
        warnings = ip.validate_requirements(requires, package_versions, "testpkg")
        self.assertEqual(warnings, [])

        requires2 = ["numpy>=1.20"]
        package_versions2 = {"numpy": "1.19.0"}
        warnings2 = ip.validate_requirements(requires2, package_versions2, "testpkg")
        self.assertEqual(len(warnings2), 1)
        self.assertIn("WARNING: The lock file provides 'numpy==1.19.0'", warnings2[0])


if __name__ == "__main__":
    unittest.main()
