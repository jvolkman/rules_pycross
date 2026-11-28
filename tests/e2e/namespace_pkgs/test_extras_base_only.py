import importlib.util

import google.api_core


def test_extras_base_only():
    assert google.api_core is not None
    assert importlib.util.find_spec("grpc") is None


if __name__ == "__main__":
    test_extras_base_only()
    print("Base-only extras target test passed!")
