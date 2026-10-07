import tempfile
import unittest
import zipfile
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
