import json
import tarfile
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.tools.inspect_package import (
    PEP517_DEFAULT_BACKEND,
    PEP517_DEFAULT_REQUIRES,
    inspect_sdist,
    inspect_wheel,
    validate_requirements,
)


class InspectPackageTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def create_tarball(self, filename, content_dict):
        path = self.temp_path / filename
        with tarfile.open(path, "w:gz") as tar:
            for name, content in content_dict.items():
                file_path = self.temp_path / "tmp_file"
                with open(file_path, "w") as f:
                    f.write(content)
                tar.add(file_path, arcname=name)
        return path

    def create_zip(self, filename, content_dict):
        path = self.temp_path / filename
        with zipfile.ZipFile(path, "w") as zipf:
            for name, content in content_dict.items():
                zipf.writestr(name, content)
        return path

    def test_inspect_sdist_no_pyproject(self):
        sdist_path = self.create_tarball("pkg-1.0.tar.gz", {"pkg-1.0/setup.py": ""})
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["build_backend"], PEP517_DEFAULT_BACKEND)
        self.assertEqual(result["build_requires"], PEP517_DEFAULT_REQUIRES)

    def test_inspect_sdist_with_pyproject(self):
        toml_content = """
        [build-system]
        requires = ["flit_core >=3.2,<4"]
        build-backend = "flit_core.buildapi"
        """
        sdist_path = self.create_tarball("pkg-1.0.tar.gz", {"pkg-1.0/pyproject.toml": toml_content})
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["build_backend"], "flit_core.buildapi")
        self.assertEqual(result["build_requires"], ["flit_core >=3.2,<4"])

    def test_inspect_wheel_with_entry_points(self):
        entry_points = """
        [console_scripts]
        foo = pkg.foo:main
        bar = pkg.bar:main
        """
        wheel_path = self.create_zip("pkg-1.0-py3-none-any.whl", {"pkg-1.0.dist-info/entry_points.txt": entry_points})
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["console_scripts"], ["foo", "bar"])

    def test_validate_requirements(self):
        # Mismatched version
        warnings = validate_requirements(
            requires=["numpy>=1.20"],
            package_versions={"numpy": "1.19.0"},
            pkg_name="my_pkg",
        )
        self.assertEqual(len(warnings), 1)
        self.assertIn("WARNING:", warnings[0])

        # Matching version
        warnings = validate_requirements(
            requires=["numpy>=1.20"],
            package_versions={"numpy": "1.21.0"},
            pkg_name="my_pkg",
        )
        self.assertEqual(len(warnings), 0)

if __name__ == "__main__":
    unittest.main()
