import importlib.metadata
import os

expected_idna = os.environ.get("EXPECTED_IDNA_VERSION", "3.7")
assert importlib.metadata.version("cowsay") == "6.1"
assert importlib.metadata.version("iniconfig") == "2.0.0"
actual_idna = importlib.metadata.version("idna")
assert actual_idna == expected_idna, f"expected idna {expected_idna}, got {actual_idna}"
