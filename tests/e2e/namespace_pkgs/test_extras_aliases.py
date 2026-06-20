import google.api_core
import grpc


def test_extras_aliases():
    assert grpc is not None
    assert google.api_core is not None


if __name__ == "__main__":
    test_extras_aliases()
    print("Extras aliases test passed!")
