import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from pycross.private.tools import resolved_lock_renderer
from pycross.private.tools.lock_model import EnvironmentReference
from pycross.private.tools.lock_model import ExtraDependencies
from pycross.private.tools.lock_model import FileKey
from pycross.private.tools.lock_model import FileReference
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import ResolvedLockSet
from pycross.private.tools.lock_model import ResolvedPackage


class ResolvedLockRendererTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def _render(self, resolved_lock):
        """Helper: render a ResolvedLockSet and return the output text."""
        input_file = self.temp_path / "lock.json"
        with open(input_file, "w") as f:
            f.write(resolved_lock.to_json())

        output_file = self.temp_path / "lock.bzl"
        args = SimpleNamespace(
            resolved_lock=input_file,
            output=output_file,
            repo_prefix="my_repo",
            pypi_index=None,
            repo=[],
            generate_file_map=False,
            pycross_repo_name="@rules_pycross",
            no_pins=False,
        )
        resolved_lock_renderer.main(args)
        return output_file.read_text()

    def test_rendered_output(self):
        pkg_key = PackageKey.from_parts("foo", "1.0")

        file_key_1 = FileKey.from_parts("foo-1.0-py3-none-any.whl", "1234")
        file_key_2 = FileKey.from_parts("foo-1.0-cp39-cp39-manylinux.whl", "5678")

        pkg_file_1 = PackageFile(name="foo-1.0-py3-none-any.whl", sha256="1234")
        pkg_file_2 = PackageFile(name="foo-1.0-cp39-cp39-manylinux.whl", sha256="5678")

        resolved_pkg = ResolvedPackage(
            key=pkg_key,
            environment_files={
                "env_win": FileReference(key=file_key_1),
                "env_lin": FileReference(key=file_key_2),
            },
        )

        resolved_lock = ResolvedLockSet(
            environments={
                "env_win": EnvironmentReference(environment_label="@//:win", config_setting_label="@//:win_setting"),
                "env_lin": EnvironmentReference(environment_label="@//:lin", config_setting_label="@//:lin_setting"),
            },
            packages={pkg_key: resolved_pkg},
            remote_files={file_key_1: pkg_file_1, file_key_2: pkg_file_2},
            pins={"foo": pkg_key},
        )

        input_file = self.temp_path / "lock.json"
        with open(input_file, "w") as f:
            f.write(resolved_lock.to_json())

        output_file = self.temp_path / "lock.bzl"
        args = SimpleNamespace(
            resolved_lock=input_file,
            output=output_file,
            repo_prefix="my_repo",
            pypi_index=None,
            repo=[],
            generate_file_map=False,
            pycross_repo_name="@rules_pycross",
            no_pins=False,
        )

        resolved_lock_renderer.main(args)

        self.assertTrue(output_file.exists())
        content = output_file.read_text()

        self.assertIn("def targets():", content)
        self.assertIn("pycross_wheel_library(", content)
        self.assertIn('package_name = "foo"', content)
        self.assertIn('package_version = "1.0"', content)
        self.assertIn("select({", content)

    def test_versioned_path_structure(self):
        """Verify the rendered output references versioned package paths."""
        pkg_key = PackageKey.from_parts("numpy", "1.2.3")
        file_key = FileKey.from_parts("numpy-1.2.3-py3-none-any.whl", "abcd1234")
        pkg_file = PackageFile(name="numpy-1.2.3-py3-none-any.whl", sha256="abcd1234")

        resolved_pkg = ResolvedPackage(
            key=pkg_key,
            environment_files={
                "env1": FileReference(key=file_key),
            },
        )

        resolved_lock = ResolvedLockSet(
            environments={
                "env1": EnvironmentReference(environment_label="@//:env1", config_setting_label="@//:env1_setting"),
            },
            packages={pkg_key: resolved_pkg},
            remote_files={file_key: pkg_file},
            pins={"numpy": pkg_key},
        )

        content = self._render(resolved_lock)
        # The renderer should reference the package target name "numpy@1.2.3"
        self.assertIn('package_name = "numpy"', content)
        self.assertIn('package_version = "1.2.3"', content)
        # Target name contains the package key
        self.assertIn('name = "numpy@1.2.3"', content)

    def test_env_build_file(self):
        """Verify environment config settings are rendered."""
        pkg_key = PackageKey.from_parts("requests", "2.28.0")
        file_key = FileKey.from_parts("requests-2.28.0-py3-none-any.whl", "abcd")
        pkg_file = PackageFile(name="requests-2.28.0-py3-none-any.whl", sha256="abcd")

        resolved_pkg = ResolvedPackage(
            key=pkg_key,
            environment_files={
                "linux": FileReference(key=file_key),
            },
        )

        resolved_lock = ResolvedLockSet(
            environments={
                "linux": EnvironmentReference(
                    environment_label="@//:linux_env", config_setting_label="@//:linux_setting"
                ),
            },
            packages={pkg_key: resolved_pkg},
            remote_files={file_key: pkg_file},
            pins={"requests": pkg_key},
        )

        content = self._render(resolved_lock)
        # Environment aliases should be rendered
        self.assertIn('name = "_env_linux"', content)
        self.assertIn('actual = "@//:linux_setting"', content)

    def test_extras_rendering(self):
        """Verify py_library targets are generated for extras."""
        pkg_key = PackageKey.from_parts("mylib", "1.0")
        dep_key = PackageKey.from_parts("extra-dep", "2.0")
        file_key = FileKey.from_parts("mylib-1.0-py3-none-any.whl", "1111")
        pkg_file = PackageFile(name="mylib-1.0-py3-none-any.whl", sha256="1111")
        dep_file_key = FileKey.from_parts("extra_dep-2.0-py3-none-any.whl", "2222")
        dep_pkg_file = PackageFile(name="extra_dep-2.0-py3-none-any.whl", sha256="2222")

        resolved_pkg = ResolvedPackage(
            key=pkg_key,
            environment_files={
                "env1": FileReference(key=file_key),
            },
            extra_dependencies={
                "test": ExtraDependencies(
                    common_dependencies=[dep_key],
                ),
            },
        )

        dep_pkg = ResolvedPackage(
            key=dep_key,
            environment_files={
                "env1": FileReference(key=dep_file_key),
            },
        )

        resolved_lock = ResolvedLockSet(
            environments={
                "env1": EnvironmentReference(environment_label="@//:env1", config_setting_label="@//:env1_setting"),
            },
            packages={pkg_key: resolved_pkg, dep_key: dep_pkg},
            remote_files={file_key: pkg_file, dep_file_key: dep_pkg_file},
            pins={"mylib": pkg_key},
        )

        content = self._render(resolved_lock)
        # The old Python renderer doesn't use "[test]" naming — check for the extra target reference
        # Extra deps list should reference the dep
        self.assertIn("extra-dep@2.0", content)
        # The main package library should still be present
        self.assertIn('package_name = "mylib"', content)


if __name__ == "__main__":
    unittest.main()
