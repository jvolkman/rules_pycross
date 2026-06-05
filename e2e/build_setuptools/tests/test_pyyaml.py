import yaml


def test_pyyaml_import():
    # Attempt to use the C extension (if available) or pure Python fallback
    try:
        from yaml import CLoader as Loader
    except ImportError:
        from yaml import Loader

    data = yaml.load("hello: world\nlist:\n  - 1\n  - 2\n", Loader=Loader)
    assert data == {"hello": "world", "list": [1, 2]}
    print("PyYAML loaded successfully!")


if __name__ == "__main__":
    test_pyyaml_import()
