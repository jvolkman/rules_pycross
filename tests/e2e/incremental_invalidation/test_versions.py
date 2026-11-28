import importlib.metadata
import pathlib

expected_six = pathlib.Path("expected_six.txt").read_text(encoding="utf-8").strip()
assert importlib.metadata.version("cowsay") == "6.1"
assert importlib.metadata.version("python-dateutil") == "2.9.0.post0"
actual_six = importlib.metadata.version("six")
assert actual_six == expected_six, f"expected six {expected_six}, got {actual_six}"
