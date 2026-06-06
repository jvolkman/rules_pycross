import tempfile
import unittest
from pathlib import Path

from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.poetry_translator import translate


class PoetryTranslatorTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.project_path = self.temp_path / "pyproject.toml"
        self.lock_path = self.temp_path / "poetry.lock"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_translator(
        self,
        project_content: str,
        lock_content: str,
        default_group: bool = True,
        optional_groups: list[str] | None = None,
    ):
        self.project_path.write_text(project_content)
        self.lock_path.write_text(lock_content)
        return translate(
            project_file=self.project_path,
            lock_file=self.lock_path,
            default_group=default_group,
            optional_groups=optional_groups or [],
            all_optional_groups=False,
        )

    def test_minimal_lock(self):
        project = """
[tool.poetry]
name = "my-app"
version = "0.1.0"
description = ""
authors = []

[tool.poetry.dependencies]
python = "^3.8"
requests = "2.31.0"
"""
        lock = """
[[package]]
name = "requests"
version = "2.31.0"
description = ""
optional = false
python-versions = ">=3.8"
files = [
    { file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:12345" },
]
"""
        result = self.run_translator(project, lock)
        self.assertEqual(len(result.packages), 1)
        self.assertIn(PackageKey.from_parts("requests", "2.31.0"), result.packages)

    def test_lock_version_check(self):
        # poetry_translator doesn't enforce lock-version, so we just run it to ensure no error.
        project = """
[tool.poetry.dependencies]
python = "^3.8"
a = "1.0"
"""
        lock = """
[metadata]
lock-version = "3.0"

[[package]]
name = "a"
version = "1.0"
description = ""
optional = false
python-versions = "*"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
"""
        result = self.run_translator(project, lock)
        self.assertEqual(len(result.packages), 1)

    def test_package_with_extras(self):
        project = """
[tool.poetry.dependencies]
python = "^3.8"
a = "1.0"
"""
        lock = """
[[package]]
name = "a"
version = "1.0"
description = ""
optional = false
python-versions = "*"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]

[package.dependencies]
b = "2.0"

[package.extras]
testing = ["pytest (>=7.0)"]

[[package]]
name = "b"
version = "2.0"
description = ""
optional = false
python-versions = "*"
files = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(len(pkg_a.dependencies), 1)
        self.assertEqual(pkg_a.dependencies[0].name, "b")

    def test_source_directory(self):
        project = """
[tool.poetry.dependencies]
python = "^3.8"
a = "1.0"
"""
        lock = """
[[package]]
name = "a"
version = "1.0"
description = ""
optional = false
python-versions = "*"
source = { type = "directory", url = "..." }
"""
        result = self.run_translator(project, lock)
        self.assertEqual(len(result.packages), 0)

    def test_source_git(self):
        project = """
[tool.poetry.dependencies]
python = "^3.8"
a = "1.0"
"""
        lock = """
[[package]]
name = "a"
version = "1.0"
description = ""
optional = false
python-versions = "*"
source = { type = "git", url = "..." }
"""
        result = self.run_translator(project, lock)
        self.assertEqual(len(result.packages), 0)

    def test_python_constraint(self):
        project = """
[tool.poetry.dependencies]
python = "^3.8"
a = "1.0"
"""
        lock = """
[[package]]
name = "a"
version = "1.0"
description = ""
optional = false
python-versions = ">=3.9,<3.13"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(str(pkg_a.python_versions), "<3.13,>=3.9")

    def test_optional_dependency(self):
        project = """
[tool.poetry.dependencies]
python = "^3.8"
a = "1.0"
"""
        lock = """
[[package]]
name = "a"
version = "1.0"
description = ""
optional = false
python-versions = "*"
files = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]

[package.dependencies]
b = {version = "2.0", markers = "extra == 'testing'"}

[[package]]
name = "b"
version = "2.0"
description = ""
optional = true
python-versions = "*"
files = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = self.run_translator(project, lock)
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(len(pkg_a.dependencies), 1)
        dep_b = pkg_a.dependencies[0]
        self.assertEqual(dep_b.name, "b")
        self.assertEqual(dep_b.marker, "")


if __name__ == "__main__":
    unittest.main()
