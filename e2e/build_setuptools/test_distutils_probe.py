import importlib


def test_import() -> None:
    importlib.import_module("distutils_probe_pkg")
