import tomllib
import unittest

from packaging.specifiers import SpecifierSet

from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.uv_translator import LockfileIncompatibleException
from pycross.private.tools.uv_translator import collect_and_process_packages
from pycross.private.tools.uv_translator import translate
from pycross.private.tools.uv_translator import validate_lockfile_version


def run_translator(
    project_toml_str: str,
    lock_toml_str: str,
    default_group: bool = True,
    optional_groups: list[str] | None = None,
    all_optional_groups: bool = False,
    development_groups: list[str] | None = None,
    all_development_groups: bool = False,
):
    project_dict = tomllib.loads(project_toml_str)
    lock_dict = tomllib.loads(lock_toml_str)

    validate_lockfile_version(lock_dict)

    project_name = package_canonical_name(project_dict["project"]["name"])

    # backwards-compatiblity for https://github.com/astral-sh/uv/pull/5861
    distributions_list = lock_dict.get("distribution", [])
    packages_list = lock_dict.get("package", distributions_list)
    requires_python = SpecifierSet(lock_dict.get("requires-python", ""))

    return translate(
        project_name,
        packages_list,
        requires_python,
        default_group=default_group,
        optional_groups=optional_groups or [],
        all_optional_groups=all_optional_groups,
        development_groups=development_groups or [],
        all_development_groups=all_development_groups,
        package_processor=collect_and_process_packages,
    )


class UvTranslatorTest(unittest.TestCase):
    def test_minimal_lock(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["requests==2.31.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [
    { name = "requests", version = "2.31.0" },
]

[[package]]
name = "requests"
version = "2.31.0"
wheels = [
    { file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:1234567890abcdef" },
]
"""
        result = run_translator(project, lock)
        self.assertEqual(len(result.packages), 1)
        req_key = PackageKey.from_parts("requests", "2.31.0")
        pkg = result.packages[req_key]
        self.assertEqual(pkg.name, "requests")
        self.assertEqual(len(pkg.files), 1)

    def test_version_check(self):
        project = '[project]\nname = "my-app"\nversion = "0.1.0"'
        lock = "version = 2\n"
        with self.assertRaises(LockfileIncompatibleException):
            run_translator(project, lock)

    def test_distribution_package_compat(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["requests==2.31.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[distribution]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [
    { name = "requests", version = "2.31.0" },
]

[[distribution]]
name = "requests"
version = "2.31.0"
wheels = [
    { file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:abc" },
]
"""
        result = run_translator(project, lock)
        self.assertEqual(len(result.packages), 1)

    def test_multiple_packages_with_deps(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a", version = "1.0" }]

[[package]]
name = "a"
version = "1.0"
dependencies = [{ name = "b", version = "2.0" }]
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]

[[package]]
name = "b"
version = "2.0"
wheels = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = run_translator(project, lock)
        self.assertEqual(len(result.packages), 2)
        key_a = PackageKey.from_parts("a", "1.0")
        pkg_a = result.packages[key_a]
        self.assertEqual(len(pkg_a.dependencies), 1)
        self.assertEqual(pkg_a.dependencies[0].name, "b")

    def test_platform_specific_deps(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
dependencies = [{ name = "b", marker = "sys_platform == 'linux'" }]

[[package]]
name = "b"
version = "2.0"
wheels = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = run_translator(project, lock)
        key_a = PackageKey.from_parts("a", "1.0")
        pkg_a = result.packages[key_a]
        dep_b = pkg_a.dependencies[0]
        self.assertEqual(dep_b.marker, 'sys_platform == "linux"')

    def test_optional_dependencies_extras(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a[test]==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
[package.optional-dependencies]
test = [{ name = "b" }]

[[package]]
name = "b"
version = "2.0"
wheels = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = run_translator(project, lock)
        key_a = PackageKey.from_parts("a", "1.0")
        pkg_a = result.packages[key_a]
        self.assertEqual(len(pkg_a.dependencies), 1)
        self.assertEqual(pkg_a.dependencies[0].name, "b")

    def test_dev_dependencies_pep735(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = []

[dependency-groups]
dev = ["b==2.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }

[package.dev-dependencies]
dev = [{ name = "b" }]

[[package]]
name = "b"
version = "2.0"
wheels = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        result = run_translator(project, lock, development_groups=["dev"])
        self.assertEqual(len(result.packages), 1)
        self.assertIn(PackageKey.from_parts("b", "2.0"), result.packages)

    def test_virtual_package(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = []
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }

[[package]]
name = "vpkg"
version = "1.0.0"
source = { virtual = "." }
"""
        result = run_translator(project, lock)
        self.assertEqual(len(result.packages), 0)

    def test_editable_package(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = []
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { editable = "." }

[[package]]
name = "epkg"
version = "1.0.0"
source = { editable = "." }
"""
        result = run_translator(project, lock)
        self.assertEqual(len(result.packages), 0)

    def test_wheels_with_urls(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ url = "https://example.com/a-1.0-py3-none-any.whl", hash = "sha256:a" }]
"""
        result = run_translator(project, lock)
        pkg = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(pkg.files[0].urls, ("https://example.com/a-1.0-py3-none-any.whl",))

    def test_no_static_urls(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
"""
        result = run_translator(project, lock)
        pkg = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(pkg.files[0].urls, tuple())

    def test_resolution_markers(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
resolution-markers = ["python_full_version == '3.8.0'"]

[[package]]
name = "a"
version = "2.0"
wheels = [{ file = "a-2.0-py3-none-any.whl", hash = "sha256:a2" }]
resolution-markers = ["python_full_version == '3.9.0'"]
"""
        result = run_translator(project, lock)
        self.assertIn(PackageKey.from_parts("a", "1.0"), result.packages)
        self.assertIn(PackageKey.from_parts("a", "2.0"), result.packages)
        self.assertEqual(str(result.packages[PackageKey.from_parts("a", "1.0")].python_versions), "==3.8.0")
        self.assertEqual(str(result.packages[PackageKey.from_parts("a", "2.0")].python_versions), "==3.9.0")

    def test_workspace_members(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["lib==1.0", "a==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "lib" }, { name = "a" }]

[[package]]
name = "lib"
version = "1.0"
source = { editable = "lib" }
dependencies = []

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
"""
        result = run_translator(project, lock)
        self.assertEqual(len(result.packages), 1)
        self.assertIn(PackageKey.from_parts("a", "1.0"), result.packages)
        self.assertNotIn(PackageKey.from_parts("lib", "1.0"), result.packages)

    def test_requires_python_propagation(self):
        project = """
[project]
name = "my-app"
version = "0.1.0"
dependencies = ["a==1.0"]
"""
        lock = """
version = 1
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]
resolution-markers = ["python_full_version >= '3.10'"]
"""
        result = run_translator(project, lock)
        self.assertEqual(str(result.python_versions), ">=3.8")
        pkg_a = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(str(pkg_a.python_versions), ">=3.10")


if __name__ == "__main__":
    unittest.main()
