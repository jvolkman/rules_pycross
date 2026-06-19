"""Test that the correct typing_extensions version is resolved for each conflict variant."""
import sys
from importlib.metadata import version


def main():
    expected = sys.argv[1]
    actual = version("typing-extensions")
    if actual != expected:
        print(f"FAIL: expected typing-extensions {expected}, got {actual}", file=sys.stderr)
        sys.exit(1)
    print(f"OK: typing-extensions {actual}")


if __name__ == "__main__":
    main()
