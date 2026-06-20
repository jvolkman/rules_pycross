"""Test that the correct package version is resolved for each conflict variant."""

import sys
from importlib.metadata import version


def main():
    pkg = sys.argv[1]
    expected = sys.argv[2]
    actual = version(pkg)
    if actual != expected:
        print(f"FAIL: expected {pkg} {expected}, got {actual}", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {pkg} {actual}")


if __name__ == "__main__":
    main()
