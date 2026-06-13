import google.api_core
import grpc


def test_squash():
    assert grpc is not None
    assert google.api_core is not None


if __name__ == "__main__":
    test_squash()
    print("Squash extras test passed!")
