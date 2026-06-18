import unittest

from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.pylock_translator import LockfileIncompatibleException
from pycross.private.tools.pylock_translator import translate


class MockArgs:
    def __init__(self, lock_file):
        self.lock_file = lock_file
        self.project_file = None
        self.default_group = True
        self.optional_group = []
        self.all_optional_groups = False
        self.development_group = []
        self.all_development_groups = False


class PylockTranslatorTest(unittest.TestCase):
    def test_minimal_lock(self):
        lock = """
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
wheels = [{ file = "my_app-0.1.0-py3-none-any.whl", hash = "sha256:abc" }]
dependencies = [
    { name = "requests" },
]

[[package]]
name = "requests"
version = "2.31.0"
wheels = [
    { file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:1234567890abcdef" },
]
"""
        with open("test_pylock.toml", "w") as f:
            f.write(lock)

        result = translate(MockArgs("test_pylock.toml"))
        self.assertEqual(len(result.packages), 2)
        req_key = PackageKey.from_parts("requests", "2.31.0")
        pkg = result.packages[req_key]
        self.assertEqual(pkg.name, "requests")
        self.assertEqual(len(pkg.files), 1)
        self.assertEqual(pkg.files[0].sha256, "1234567890abcdef")

    def test_version_check(self):
        lock = 'lock-version = "2.0"\n'
        with open("test_pylock_v2.toml", "w") as f:
            f.write(lock)
        with self.assertRaises(LockfileIncompatibleException):
            translate(MockArgs("test_pylock_v2.toml"))

    def test_dependencies(self):
        lock = """
lock-version = "1.0"
requires-python = ">=3.8"

[[packages]]
name = "my-app"
version = "0.1.0"
wheels = [{ file = "my_app-0.1.0-py3-none-any.whl", hash = "sha256:abc" }]
dependencies = [{ name = "a" }]

[[packages]]
name = "a"
version = "1.0"
dependencies = [{ name = "b" }]
wheels = [{ file = "a-1.0-py3-none-any.whl", hash = "sha256:a" }]

[[packages]]
name = "b"
version = "2.0"
wheels = [{ file = "b-2.0-py3-none-any.whl", hash = "sha256:b" }]
"""
        with open("test_pylock_deps.toml", "w") as f:
            f.write(lock)

        result = translate(MockArgs("test_pylock_deps.toml"))
        self.assertEqual(len(result.packages), 3)
        key_a = PackageKey.from_parts("a", "1.0")
        pkg_a = result.packages[key_a]
        self.assertEqual(len(pkg_a.dependencies), 1)
        self.assertEqual(pkg_a.dependencies[0].name, "b")

    def test_platform_specific_deps(self):
        lock = """
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
wheels = [{ file = "my_app-0.1.0-py3-none-any.whl", hash = "sha256:abc" }]
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
        with open("test_pylock_plat.toml", "w") as f:
            f.write(lock)

        result = translate(MockArgs("test_pylock_plat.toml"))
        key_a = PackageKey.from_parts("a", "1.0")
        pkg_a = result.packages[key_a]
        dep_b = pkg_a.dependencies[0]
        self.assertEqual(dep_b.marker, "sys_platform == 'linux'")

    def test_wheels_with_urls(self):
        lock = """
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "my-app"
version = "0.1.0"
wheels = [{ file = "my_app-0.1.0-py3-none-any.whl", hash = "sha256:abc" }]
dependencies = [{ name = "a" }]

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", url = "https://example.com/a-1.0-py3-none-any.whl", hash = "sha256:a" }]
"""
        with open("test_pylock_urls.toml", "w") as f:
            f.write(lock)

        result = translate(MockArgs("test_pylock_urls.toml"))
        pkg = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(pkg.files[0].urls, ("https://example.com/a-1.0-py3-none-any.whl",))

    def test_wheel_hashes_table(self):
        lock = """
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "a"
version = "1.0"
wheels = [{ file = "a-1.0-py3-none-any.whl", hashes = { "sha256" = "deadbeef" } }]
"""
        with open("test_pylock_hashes.toml", "w") as f:
            f.write(lock)

        result = translate(MockArgs("test_pylock_hashes.toml"))
        pkg = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(pkg.files[0].sha256, "deadbeef")

    def _write_file(self, name, content):
        """Helper to write a temp file and return its path."""
        import os
        import tempfile

        path = os.path.join(tempfile.gettempdir(), name)
        with open(path, "w") as f:
            f.write(content)
        return path

    def _make_args(
        self,
        lock_file,
        project_file=None,
        default=True,
        optional_group=None,
        all_optional_groups=False,
        development_group=None,
        all_development_groups=False,
    ):
        args = MockArgs(lock_file)
        args.project_file = project_file
        args.default_group = default
        args.optional_group = optional_group or []
        args.all_optional_groups = all_optional_groups
        args.development_group = development_group or []
        args.all_development_groups = all_development_groups
        return args

    # -- Lock and project fixtures shared across multiple tests --

    LOCK_WITH_GROUPS = """\
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "requests"
version = "2.31.0"
dependencies = [{ name = "urllib3" }]
wheels = [{ file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:req" }]

[[package]]
name = "urllib3"
version = "2.0.0"
wheels = [{ file = "urllib3-2.0.0-py3-none-any.whl", hash = "sha256:url" }]

[[package]]
name = "pytest"
version = "7.4.0"
dependencies = [{ name = "pluggy" }]
wheels = [{ file = "pytest-7.4.0-py3-none-any.whl", hash = "sha256:pyt" }]

[[package]]
name = "pluggy"
version = "1.2.0"
wheels = [{ file = "pluggy-1.2.0-py3-none-any.whl", hash = "sha256:plg" }]

[[package]]
name = "mypy"
version = "1.5.0"
wheels = [{ file = "mypy-1.5.0-py3-none-any.whl", hash = "sha256:myp" }]

[[package]]
name = "ruff"
version = "0.1.0"
wheels = [{ file = "ruff-0.1.0-py3-none-any.whl", hash = "sha256:ruf" }]

[[package]]
name = "typing-extensions"
version = "4.7.0"
wheels = [{ file = "typing_extensions-4.7.0-py3-none-any.whl", hash = "sha256:tex" }]
"""

    PROJECT_WITH_GROUPS = """\
[project]
name = "my-project"
version = "1.0.0"
dependencies = ["requests>=2.0"]

[project.optional-dependencies]
test = ["pytest>=7.0"]
lint = ["ruff>=0.1"]

[dependency-groups]
dev = ["mypy>=1.0"]
typing = ["typing-extensions>=4.0"]
all = ["ruff", {include-group = "typing"}]
"""

    def test_no_default(self):
        """default=False excludes the project's main dependencies."""
        lock_path = self._write_file("test_nodef_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_nodef_proj.toml", self.PROJECT_WITH_GROUPS)

        args = self._make_args(lock_path, project_file=proj_path, default=False)
        result = translate(args)

        # No default deps → no packages selected, since no groups were requested
        self.assertEqual(len(result.packages), 0)
        self.assertEqual(len(result.pins), 0)

    def test_optional_group(self):
        """optional_group=['test'] includes test deps + transitive deps."""
        lock_path = self._write_file("test_optgrp_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_optgrp_proj.toml", self.PROJECT_WITH_GROUPS)

        args = self._make_args(lock_path, project_file=proj_path, default=False, optional_group=["test"])
        result = translate(args)

        pkg_names = {pkg.name for pkg in result.packages.values()}
        # pytest + its transitive dep pluggy
        self.assertIn("pytest", pkg_names)
        self.assertIn("pluggy", pkg_names)
        # requests is a default dep, should not be included
        self.assertNotIn("requests", pkg_names)
        self.assertNotIn("urllib3", pkg_names)
        self.assertEqual(len(result.packages), 2)

    def test_all_optional_groups(self):
        """all_optional_groups=True includes all optional deps."""
        lock_path = self._write_file("test_allopt_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_allopt_proj.toml", self.PROJECT_WITH_GROUPS)

        args = self._make_args(lock_path, project_file=proj_path, default=False, all_optional_groups=True)
        result = translate(args)

        pkg_names = {pkg.name for pkg in result.packages.values()}
        # test group: pytest + pluggy
        self.assertIn("pytest", pkg_names)
        self.assertIn("pluggy", pkg_names)
        # lint group: ruff
        self.assertIn("ruff", pkg_names)
        # default deps excluded
        self.assertNotIn("requests", pkg_names)

    def test_development_group(self):
        """development_group=['dev'] includes the dev dependency group."""
        lock_path = self._write_file("test_devgrp_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_devgrp_proj.toml", self.PROJECT_WITH_GROUPS)

        args = self._make_args(lock_path, project_file=proj_path, default=False, development_group=["dev"])
        result = translate(args)

        pkg_names = {pkg.name for pkg in result.packages.values()}
        self.assertIn("mypy", pkg_names)
        self.assertEqual(len(result.packages), 1)
        # requests not included
        self.assertNotIn("requests", pkg_names)

    def test_all_development_groups(self):
        """all_development_groups=True includes all dependency-groups."""
        lock_path = self._write_file("test_alldev_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_alldev_proj.toml", self.PROJECT_WITH_GROUPS)

        args = self._make_args(lock_path, project_file=proj_path, default=False, all_development_groups=True)
        result = translate(args)

        pkg_names = {pkg.name for pkg in result.packages.values()}
        # dev group: mypy
        self.assertIn("mypy", pkg_names)
        # typing group: typing-extensions
        self.assertIn("typing-extensions", pkg_names)
        # all group: ruff + typing-extensions (via include-group)
        self.assertIn("ruff", pkg_names)

    def test_include_group(self):
        """include-group pulls in deps from the referenced group."""
        lock_path = self._write_file("test_incgrp_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_incgrp_proj.toml", self.PROJECT_WITH_GROUPS)

        # Request only the "all" dev group which uses {include-group = "typing"}
        args = self._make_args(lock_path, project_file=proj_path, default=False, development_group=["all"])
        result = translate(args)

        pkg_names = {pkg.name for pkg in result.packages.values()}
        # "all" group has "ruff" directly, plus includes "typing" → "typing-extensions"
        self.assertIn("ruff", pkg_names)
        self.assertIn("typing-extensions", pkg_names)
        # mypy is in "dev" group, not "all"
        self.assertNotIn("mypy", pkg_names)

    def test_graph_traversal(self):
        """Only transitive deps of selected roots are included, not the full lockfile."""
        lock_path = self._write_file("test_graph_lock.toml", self.LOCK_WITH_GROUPS)
        proj_path = self._write_file("test_graph_proj.toml", self.PROJECT_WITH_GROUPS)

        # default=True includes requests, which transitively pulls in urllib3
        args = self._make_args(lock_path, project_file=proj_path, default=True, optional_group=["test"])
        result = translate(args)

        pkg_names = {pkg.name for pkg in result.packages.values()}
        # From default: requests → urllib3
        self.assertIn("requests", pkg_names)
        self.assertIn("urllib3", pkg_names)
        # From test: pytest → pluggy
        self.assertIn("pytest", pkg_names)
        self.assertIn("pluggy", pkg_names)
        # mypy, ruff, typing-extensions are not reachable
        self.assertNotIn("mypy", pkg_names)
        self.assertNotIn("ruff", pkg_names)
        self.assertNotIn("typing-extensions", pkg_names)
        self.assertEqual(len(result.packages), 4)

        # Pins should reference the direct root packages
        self.assertIn("requests", result.pins)
        self.assertIn("pytest", result.pins)
        # Transitive deps are in packages but NOT in pins
        self.assertNotIn("urllib3", result.pins)
        self.assertNotIn("pluggy", result.pins)

    def test_sdist_parsing(self):
        """Lock with sdist entries produces correct files with hash/url."""
        lock = """\
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "foo"
version = "1.0.0"
wheels = [{ file = "foo-1.0.0-py3-none-any.whl", hash = "sha256:whlhash" }]

[[package.sdists]]
file = "foo-1.0.0.tar.gz"
url = "https://files.example.com/foo-1.0.0.tar.gz"
hash = "sha256:sdsthash"
"""
        lock_path = self._write_file("test_sdist_lock.toml", lock)

        args = self._make_args(lock_path)
        result = translate(args)

        pkg = result.packages[PackageKey.from_parts("foo", "1.0.0")]
        # Should have 2 files: one wheel + one sdist
        self.assertEqual(len(pkg.files), 2)

        file_names = {f.name for f in pkg.files}
        self.assertIn("foo-1.0.0-py3-none-any.whl", file_names)
        self.assertIn("foo-1.0.0.tar.gz", file_names)

        sdist_file = [f for f in pkg.files if f.name == "foo-1.0.0.tar.gz"][0]
        self.assertEqual(sdist_file.sha256, "sdsthash")
        self.assertEqual(sdist_file.urls, ("https://files.example.com/foo-1.0.0.tar.gz",))

    def test_no_default_no_groups_empty(self):
        """default=False with no groups results in empty packages."""
        lock = """\
lock-version = "1.0"
requires-python = ">=3.8"

[[package]]
name = "requests"
version = "2.31.0"
wheels = [{ file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:req" }]

[[package]]
name = "pytest"
version = "7.4.0"
wheels = [{ file = "pytest-7.4.0-py3-none-any.whl", hash = "sha256:pyt" }]
"""
        proj = """\
[project]
name = "my-project"
version = "1.0.0"
dependencies = ["requests"]

[project.optional-dependencies]
test = ["pytest"]
"""
        lock_path = self._write_file("test_empty_lock.toml", lock)
        proj_path = self._write_file("test_empty_proj.toml", proj)

        args = self._make_args(lock_path, project_file=proj_path, default=False)
        result = translate(args)

        self.assertEqual(len(result.packages), 0)
        self.assertEqual(len(result.pins), 0)


if __name__ == "__main__":
    unittest.main()
