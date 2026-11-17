"""Check the installed version of a distribution."""

import importlib.metadata
import sys

if __name__ == "__main__":
    dist, expected = sys.argv[1], sys.argv[2]
    actual = importlib.metadata.version(dist)
    print(f"{dist} {actual}")
    if actual != expected:
        sys.exit(f"expected {dist} {expected}, got {actual}")
