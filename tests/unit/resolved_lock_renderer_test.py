import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from pycross.private.tools import resolved_lock_renderer
from pycross.private.tools.lock_model import EnvironmentReference
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


if __name__ == "__main__":
    unittest.main()
