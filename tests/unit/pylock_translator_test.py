import unittest

from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.pylock_translator import LockfileIncompatibleException
from pycross.private.tools.pylock_translator import translate


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

        result = translate("test_pylock.toml")
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
            translate("test_pylock_v2.toml")

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

        result = translate("test_pylock_deps.toml")
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

        result = translate("test_pylock_plat.toml")
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

        result = translate("test_pylock_urls.toml")
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

        result = translate("test_pylock_hashes.toml")
        pkg = result.packages[PackageKey.from_parts("a", "1.0")]
        self.assertEqual(pkg.files[0].sha256, "deadbeef")


if __name__ == "__main__":
    unittest.main()
