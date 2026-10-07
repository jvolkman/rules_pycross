import importlib
import unittest


class TestDistutilsProbe(unittest.TestCase):
    def test_import(self) -> None:
        importlib.import_module("distutils_probe_pkg")


if __name__ == "__main__":
    unittest.main()
