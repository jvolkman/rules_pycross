import io
import tarfile
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.tools.inspect_package import PEP517_DEFAULT_BACKEND
from pycross.private.tools.inspect_package import PEP517_DEFAULT_REQUIRES
from pycross.private.tools.inspect_package import inspect_sdist
from pycross.private.tools.inspect_package import inspect_wheel
from pycross.private.tools.inspect_package import validate_requirements


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

    def test_inspect_sdist_no_pyproject_and_no_setup(self):
        sdist_path = self.create_tarball("pkg-1.0.tar.gz", {"pkg-1.0/": ""})
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["build_backend"], PEP517_DEFAULT_BACKEND)
        self.assertEqual(result["build_requires"], PEP517_DEFAULT_REQUIRES)

    def test_inspect_sdist_no_build_backend(self):
        toml_content = """
        [build-system]
        requires = ["setuptools>=40"]
        """
        sdist_path = self.create_tarball("pkg-1.0.tar.gz", {"pkg-1.0/pyproject.toml": toml_content})
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["build_backend"], PEP517_DEFAULT_BACKEND)
        self.assertEqual(result["build_requires"], ["setuptools>=40"])

    def test_inspect_sdist_requires_extras(self):
        toml_content = """
        [build-system]
        requires = ["setuptools[ssl]>=40"]
        """
        sdist_path = self.create_tarball("pkg-1.0.tar.gz", {"pkg-1.0/pyproject.toml": toml_content})
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["build_requires"], ["setuptools[ssl]>=40"])

    def test_inspect_wheel_with_entry_points(self):
        entry_points = """
        [console_scripts]
        foo = pkg.foo:main
        bar = pkg.bar:main
        """
        wheel_path = self.create_zip("pkg-1.0-py3-none-any.whl", {"pkg-1.0.dist-info/entry_points.txt": entry_points})
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["console_scripts"], ["foo", "bar"])

    def test_inspect_wheel_no_entry_points(self):
        wheel_path = self.create_zip("pkg-1.0-py3-none-any.whl", {"pkg-1.0.dist-info/WHEEL": ""})
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["console_scripts"], [])

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

        # Extra markers ignored or parsed gracefully
        warnings = validate_requirements(
            requires=["foo; python_version >= '3.8'"],
            package_versions={"foo": "1.0"},
            pkg_name="my_pkg",
        )
        self.assertEqual(len(warnings), 0)

    def _create_tarball_with_dirs(self, filename, files):
        """Create a tarball with proper directory entries.

        Args:
            filename: Name of the tar.gz file.
            files: Dict of {arcname: content_or_None}. If content is None,
                   a directory entry is created.
        """
        path = self.temp_path / filename
        with tarfile.open(path, "w:gz") as tar:
            # Collect directories implicitly from file paths
            dirs_added = set()
            for name, content in files.items():
                if content is None:
                    # Explicit directory entry
                    info = tarfile.TarInfo(name=name.rstrip("/") + "/")
                    info.type = tarfile.DIRTYPE
                    tar.addfile(info)
                    dirs_added.add(name.rstrip("/") + "/")
                else:
                    # Add implicit parent directories
                    parts = name.split("/")
                    for i in range(1, len(parts)):
                        dir_name = "/".join(parts[:i]) + "/"
                        if dir_name not in dirs_added:
                            info = tarfile.TarInfo(name=dir_name)
                            info.type = tarfile.DIRTYPE
                            tar.addfile(info)
                            dirs_added.add(dir_name)
                    # Add the file
                    data = content.encode("utf-8")
                    info = tarfile.TarInfo(name=name)
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))
        return path

    def test_wheel_top_level_paths(self):
        wheel_path = self.create_zip(
            "numpy-1.0-py3-none-any.whl",
            {
                "numpy/__init__.py": "",
                "numpy/core.py": "# core module",
                "numpy-1.0.dist-info/METADATA": "Name: numpy",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["top_level_paths"], ["numpy"])

    def test_wheel_top_level_paths_single_file(self):
        wheel_path = self.create_zip(
            "six-1.0-py3-none-any.whl",
            {
                "six.py": "# six module",
                "six-1.0.dist-info/METADATA": "Name: six",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["top_level_paths"], ["six.py"])

    def test_wheel_top_level_paths_pth(self):
        wheel_path = self.create_zip(
            "rerun_sdk-1.0-py3-none-any.whl",
            {
                "rerun_sdk.pth": "import rerun_sdk",
                "rerun_sdk/__init__.py": "",
                "rerun_sdk-1.0.dist-info/METADATA": "Name: rerun-sdk",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["top_level_paths"], ["rerun_sdk", "rerun_sdk.pth"])

    def test_sdist_standard_layout(self):
        sdist_path = self._create_tarball_with_dirs(
            "mypackage-1.0.tar.gz",
            {
                "mypackage-1.0/mypackage/__init__.py": "",
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], ["mypackage"])

    def test_sdist_src_layout(self):
        sdist_path = self._create_tarball_with_dirs(
            "mypackage-1.0.tar.gz",
            {
                "mypackage-1.0/src/mypackage/__init__.py": "",
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], ["mypackage"])

    def test_sdist_excluded_dirs(self):
        sdist_path = self._create_tarball_with_dirs(
            "pkg-1.0.tar.gz",
            {
                "pkg-1.0/tests/__init__.py": "",
                "pkg-1.0/docs/__init__.py": "",
                "pkg-1.0/mylib/__init__.py": "",
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], ["mylib"])

    def test_sdist_no_init_py(self):
        sdist_path = self._create_tarball_with_dirs(
            "pkg-1.0.tar.gz",
            {
                "pkg-1.0/nopackage/": None,  # directory only, no __init__.py
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], [])

    def test_sdist_top_level_paths_pth(self):
        sdist_path = self._create_tarball_with_dirs(
            "rerun_sdk-1.0.tar.gz",
            {
                "rerun_sdk-1.0/rerun_sdk.pth": "import rerun_sdk",
                "rerun_sdk-1.0/rerun_sdk/__init__.py": "",
                "rerun_sdk-1.0/pyproject.toml": '[build-system]\nrequires = ["setuptools"]\nbuild-backend = "setuptools.build_meta"',
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], ["rerun_sdk", "rerun_sdk.pth"])

    def test_wheel_excludes_dist_info(self):
        wheel_path = self.create_zip(
            "pkg-1.0-py3-none-any.whl",
            {
                "pkg-1.0.dist-info/METADATA": "Name: pkg",
                "pkg-1.0.dist-info/RECORD": "",
                "pkg/__init__.py": "",
                "pkg/module.py": "",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["top_level_paths"], ["pkg"])

    # -- Namespace package (PEP 420) tests --

    def test_wheel_namespace_package(self):
        """google-cloud-storage style: google/ has no __init__.py."""
        wheel_path = self.create_zip(
            "google_cloud_storage-2.0-py3-none-any.whl",
            {
                "google/cloud/storage/__init__.py": "",
                "google/cloud/storage/blob.py": "",
                "google/cloud/storage/bucket.py": "",
                "google_cloud_storage-2.0.dist-info/METADATA": "Name: google-cloud-storage",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(result["top_level_paths"], ["google/cloud/storage"])

    def test_wheel_namespace_package_multiple_concrete(self):
        """A wheel that provides multiple concrete packages under one namespace."""
        wheel_path = self.create_zip(
            "google_cloud_all-1.0-py3-none-any.whl",
            {
                "google/cloud/storage/__init__.py": "",
                "google/cloud/storage/blob.py": "",
                "google/cloud/bigquery/__init__.py": "",
                "google/cloud/bigquery/client.py": "",
                "google_cloud_all-1.0.dist-info/METADATA": "Name: google-cloud-all",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(
            result["top_level_paths"],
            ["google/cloud/bigquery", "google/cloud/storage"],
        )

    def test_wheel_namespace_with_mid_level_init(self):
        """google/cloud has __init__.py but google/ does not."""
        wheel_path = self.create_zip(
            "google_cloud_core-1.0-py3-none-any.whl",
            {
                "google/cloud/__init__.py": "",
                "google/cloud/client.py": "",
                "google_cloud_core-1.0.dist-info/METADATA": "Name: google-cloud-core",
            },
        )
        result = inspect_wheel(wheel_path)
        # Should stop at google/cloud since it has __init__.py
        self.assertEqual(result["top_level_paths"], ["google/cloud"])

    def test_wheel_mixed_regular_and_namespace(self):
        """A wheel with both a regular package and a namespace package."""
        wheel_path = self.create_zip(
            "mixed-1.0-py3-none-any.whl",
            {
                "regular_pkg/__init__.py": "",
                "regular_pkg/module.py": "",
                "namespace/sub/concrete/__init__.py": "",
                "namespace/sub/concrete/stuff.py": "",
                "mixed-1.0.dist-info/METADATA": "Name: mixed",
            },
        )
        result = inspect_wheel(wheel_path)
        self.assertEqual(
            result["top_level_paths"],
            ["namespace/sub/concrete", "regular_pkg"],
        )

    def test_wheel_namespace_skips_subpackages(self):
        """Shallowest concrete package should subsume deeper ones."""
        wheel_path = self.create_zip(
            "deep-1.0-py3-none-any.whl",
            {
                "ns/mid/__init__.py": "",
                "ns/mid/deep/__init__.py": "",
                "ns/mid/deep/deeper/__init__.py": "",
                "deep-1.0.dist-info/METADATA": "Name: deep",
            },
        )
        result = inspect_wheel(wheel_path)
        # ns/mid has __init__.py, so it's the shallowest — deeper ones are subpackages
        self.assertEqual(result["top_level_paths"], ["ns/mid"])

    def test_sdist_namespace_package(self):
        """Namespace package in an sdist (standard layout)."""
        sdist_path = self._create_tarball_with_dirs(
            "google-cloud-storage-2.0.tar.gz",
            {
                "google-cloud-storage-2.0/google/cloud/storage/__init__.py": "",
                "google-cloud-storage-2.0/google/cloud/storage/blob.py": "",
                "google-cloud-storage-2.0/pyproject.toml": '[build-system]\nrequires = ["setuptools"]\nbuild-backend = "setuptools.build_meta"',
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], ["google/cloud/storage"])

    def test_sdist_namespace_src_layout(self):
        """Namespace package in an sdist with src-layout."""
        sdist_path = self._create_tarball_with_dirs(
            "google-cloud-storage-2.0.tar.gz",
            {
                "google-cloud-storage-2.0/src/google/cloud/storage/__init__.py": "",
                "google-cloud-storage-2.0/src/google/cloud/storage/blob.py": "",
                "google-cloud-storage-2.0/pyproject.toml": '[build-system]\nrequires = ["setuptools"]\nbuild-backend = "setuptools.build_meta"',
            },
        )
        result = inspect_sdist(sdist_path)
        self.assertEqual(result["top_level_paths"], ["google/cloud/storage"])


if __name__ == "__main__":
    unittest.main()
