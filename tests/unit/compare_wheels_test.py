import tempfile
import unittest
import zipfile
from pathlib import Path

from tests.e2e.tools.compare_wheels import check_extension_suffixes
from tests.e2e.tools.compare_wheels import compare_wheel_dirs


def _write_wheel(path: Path, files: dict[str, bytes]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as zf:
        for name, data in sorted(files.items()):
            zf.writestr(name, data)


class CompareWheelsTest(unittest.TestCase):
    def test_identical_wheel_sets_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            _write_wheel(dir_a / "pkg-1.0-py3-none-any.whl", {"pkg/__init__.py": b"x = 1\n"})
            _write_wheel(dir_b / "pkg-1.0-py3-none-any.whl", {"pkg/__init__.py": b"x = 1\n"})

            self.assertTrue(compare_wheel_dirs(dir_a, dir_b))

    def test_empty_intersection_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            _write_wheel(dir_a / "only_a-1.0-py3-none-any.whl", {"a.py": b"1"})
            _write_wheel(dir_b / "only_b-1.0-py3-none-any.whl", {"b.py": b"1"})

            self.assertFalse(compare_wheel_dirs(dir_a, dir_b))

    def test_both_empty_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            dir_a.mkdir()
            dir_b.mkdir()

            self.assertFalse(compare_wheel_dirs(dir_a, dir_b))

    def test_asymmetric_extra_wheel_in_host_a_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            _write_wheel(dir_a / "common-1.0-py3-none-any.whl", {"c.py": b"same"})
            _write_wheel(dir_a / "extra_a-1.0-py3-none-any.whl", {"a.py": b"extra"})
            _write_wheel(dir_b / "common-1.0-py3-none-any.whl", {"c.py": b"same"})

            self.assertFalse(compare_wheel_dirs(dir_a, dir_b))

    def test_asymmetric_extra_wheel_in_host_b_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            _write_wheel(dir_a / "common-1.0-py3-none-any.whl", {"c.py": b"same"})
            _write_wheel(dir_b / "common-1.0-py3-none-any.whl", {"c.py": b"same"})
            _write_wheel(dir_b / "extra_b-1.0-py3-none-any.whl", {"b.py": b"extra"})

            self.assertFalse(compare_wheel_dirs(dir_a, dir_b))

    def test_differing_wheel_contents_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            _write_wheel(dir_a / "pkg-1.0-py3-none-any.whl", {"pkg/__init__.py": b"x = 1\n"})
            _write_wheel(dir_b / "pkg-1.0-py3-none-any.whl", {"pkg/__init__.py": b"x = 2\n"})

            self.assertFalse(compare_wheel_dirs(dir_a, dir_b))


class ExtensionSuffixTest(unittest.TestCase):
    def _check(self, wheel_name, ext_names):
        with tempfile.TemporaryDirectory() as tmp:
            whl = Path(tmp) / wheel_name
            _write_wheel(whl, {name: b"\0" for name in ext_names})
            return check_extension_suffixes(whl)

    def test_matching_suffixes_pass(self):
        cases = {
            "pkg-1.0-cp38-abi3-macosx_14_0_arm64.whl": ["pkg/_ext.abi3-darwin.so", "pkg/_old.abi3.so"],
            "pkg-1.0-cp315-cp315-macosx_14_0_arm64.whl": ["pkg/_ext.cpython-315-darwin.so"],
            "pkg-1.0-cp38-abi3-manylinux_2_28_x86_64.whl": ["_ext.abi3-x86_64-linux-gnu.so"],
            "pkg-1.0-cp315-cp315t-manylinux2014_aarch64.manylinux_2_17_aarch64.whl": [
                "_ext.cpython-315t-aarch64-linux-gnu.so",
                "pkg.libs/libfoo-1234abcd.so.1",
            ],
            "pkg-1.0-cp315-cp315-musllinux_1_2_x86_64.whl": ["_ext.cpython-315-x86_64-linux-musl.so"],
            "pkg-1.0-cp314-cp314-linux_x86_64.whl": ["_ext.cpython-314-x86_64-linux-gnu.so", "libplain.so"],
        }
        for wheel_name, ext_names in cases.items():
            with self.subTest(wheel=wheel_name):
                self.assertEqual(self._check(wheel_name, ext_names), [])

    def test_mismatched_suffixes_fail(self):
        cases = {
            # Python 3.15 cross builds leaking the build host's limited-API suffix.
            "python_geohash-0.9.2-cp38-abi3-macosx_14_0_arm64.whl": "_geohash.abi3-x86_64-linux-gnu.so",
            "python_geohash-0.9.2-cp38-abi3-manylinux_2_28_x86_64.whl": "_geohash.abi3-darwin.so",
            "pkg-1.0-cp315-cp315-manylinux_2_28_aarch64.whl": "_ext.cpython-315-x86_64-linux-gnu.so",
            "pkg-1.0-cp315-cp315-musllinux_1_2_x86_64.whl": "_ext.cpython-315-x86_64-linux-gnu.so",
        }
        for wheel_name, ext_name in cases.items():
            with self.subTest(wheel=wheel_name):
                self.assertEqual(self._check(wheel_name, [ext_name]), [ext_name])

    def test_compare_wheel_dirs_fails_on_mismatched_suffix(self):
        with tempfile.TemporaryDirectory() as tmp:
            dir_a = Path(tmp) / "a"
            dir_b = Path(tmp) / "b"
            name = "pkg-1.0-cp38-abi3-macosx_14_0_arm64.whl"
            files = {"_ext.abi3-x86_64-linux-gnu.so": b"\0"}
            _write_wheel(dir_a / name, files)
            _write_wheel(dir_b / name, files)

            # Byte-identical across hosts, but the extension can't load on macOS.
            self.assertFalse(compare_wheel_dirs(dir_a, dir_b))


if __name__ == "__main__":
    unittest.main()
