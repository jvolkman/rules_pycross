"""Test that packages from different lock repos can be used together."""

import attrs
import regex
import six


def test_cross_repo():
    """Verify all packages are importable and functional."""
    # regex (shared between lock_a and lock_b via hub)
    m = regex.match(r"\w+", "hello")
    assert m is not None, "regex match failed"

    # six (only in lock_a)
    assert six.PY3, "Expected Python 3"

    # attrs (only in lock_b)
    @attrs.define
    class Point:
        x: int
        y: int

    p = Point(1, 2)
    assert p.x == 1 and p.y == 2, "attrs class failed"

    print("All cross-repo imports successful!")


if __name__ == "__main__":
    test_cross_repo()
