import tempfile
import unittest
from pathlib import Path

from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.pdm_translator import translate


class PdmTranslatorTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.project_path = self.temp_path / "pyproject.toml"
        self.lock_path = self.temp_path / "pdm.lock"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_translator(
        self,
        project_content: str,
        lock_content: str,
        default_group: bool = True,
        optional_groups: list[str] | None = None,
        development_groups: list[str] | None = None,
    ):
        self.project_path.write_text(project_content)
        self.lock_path.write_text(lock_content)
        return translate(
            project_file=self.project_path,
            lock_file=self.lock_path,
            default_group=default_group,
            optional_groups=optional_groups or [],
            all_optional_groups=False,
            development_groups=development_groups or [],
            all_development_groups=False,
        )

    def test_minimal_lock(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["requests==2.31.0"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "requests"
version = "2.31.0"
files = [
    { file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:12345" },
]
"""
        result = self.run_translator(project, lock)
        self.assertEqual(len(result.packages), 1)
        req_key = PackageKey.from_parts("requests", "2.31.0")
        self.assertIn(req_key, result.packages)

    def test_package_with_groups(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["requests==2.31.0"]

[dependency-groups]
dev = ["pytest==7.0.0"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "requests"
version = "2.31.0"
files = [{ file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:123" }]

[[package]]
name = "pytest"
version = "7.0.0"
files = [{ file = "pytest-7.0.0-py3-none-any.whl", hash = "sha256:abc" }]
"""
        # Test default group only
        res_default = self.run_translator(project, lock, default_group=True)
        self.assertIn("requests", res_default.pins)
        self.assertNotIn("pytest", res_default.pins)

        # Test dev group included
        res_dev = self.run_translator(project, lock, default_group=True, development_groups=["dev"])
        self.assertIn("requests", res_dev.pins)
        self.assertIn("pytest", res_dev.pins)

    def test_conditional_dependency(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "a"
version = "1.0"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
dependencies = ["b==2.0; python_version >= '3.10'"]

[[package]]
name = "b"
version = "2.0"
files = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        dep_b = pkg_a.dependencies[0]
        self.assertEqual(dep_b.name, "b")
        self.assertEqual(dep_b.marker, 'python_version >= "3.10"')

    def test_cross_platform_files(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "a"
version = "1.0"
files = [
    { file = "a-1.0-cp39-cp39-macosx_10_9_x86_64.whl", hash = "sha256:mac" },
    { file = "a-1.0-cp39-cp39-manylinux1_x86_64.whl", hash = "sha256:lin" }
]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(len(pkg_a.files), 2)
        names = {f.name for f in pkg_a.files}
        self.assertIn("a-1.0-cp39-cp39-macosx_10_9_x86_64.whl", names)

    def test_local_editable_package(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["localpkg"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "localpkg"
version = "1.0"
path = "."
"""
        result = self.run_translator(project, lock)
        # It's marked as is_local, so it should be elided
        self.assertNotIn(PackageKey.from_parts("localpkg", "1.0"), result.packages)

    def test_file_hashes(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "a"
version = "1.0"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:myhash123" }]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(pkg_a.files[0].sha256, "myhash123")

    def test_extras_in_markers(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
[metadata]
lock_version = "4.3"

[[package]]
name = "a"
version = "1.0"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
dependencies = ["b==2.0; extra == 'testing'"]

[[package]]
name = "b"
version = "2.0"
files = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        dep_b = pkg_a.dependencies[0]
        self.assertEqual(dep_b.marker, 'extra == "testing"')


if __name__ == "__main__":
    unittest.main()
