"""Test that the correct package version is resolved for each conflict variant."""

import sys
from importlib.metadata import version


def main():
    args = sys.argv[1:]
    for i in range(0, len(args), 2):
        pkg = args[i]
        expected = args[i + 1]
        actual = version(pkg)
        if actual != expected:
            print(f"FAIL: expected {pkg} {expected}, got {actual}", file=sys.stderr)
            sys.exit(1)
        print(f"OK: {pkg} {actual}")


if __name__ == "__main__":
    main()
