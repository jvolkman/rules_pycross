"""Verify that six was installed from the external_six build_target."""

import six


def test_custom_build():
    """Verify the six module came from our external build, not PyPI."""
    # Our stub six.py has a BUILT_BY_EXTERNAL_REPO marker that the real
    # PyPI six does not have. This proves build_target was used.
    assert hasattr(six, "BUILT_BY_EXTERNAL_REPO"), (
        "six was not installed from external_six build_target; missing BUILT_BY_EXTERNAL_REPO attribute"
    )
    assert six.BUILT_BY_EXTERNAL_REPO is True
    assert six.__version__ == "1.17.0"


if __name__ == "__main__":
    test_custom_build()
    print("PASS")
