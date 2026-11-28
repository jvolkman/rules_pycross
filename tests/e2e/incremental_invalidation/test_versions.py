import importlib.metadata
import os

expected_six = os.environ.get("EXPECTED_SIX_VERSION", "1.16.0")
assert importlib.metadata.version("cowsay") == "6.1"
assert importlib.metadata.version("python-dateutil") == "2.9.0.post0"
actual_six = importlib.metadata.version("six")
assert actual_six == expected_six, f"expected six {expected_six}, got {actual_six}"
