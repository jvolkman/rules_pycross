import sys
import unittest

import six


class TestForkedBuildTools(unittest.TestCase):
    EXPECTED_VERSION = None

    def test_build_env_setuptools_version(self):
        versions = getattr(six, "BUILD_SETUPTOOLS_VERSIONS", None)
        self.assertIsNotNone(
            versions,
            "Expected six.BUILD_SETUPTOOLS_VERSIONS to be recorded by site_hooks during sdist build",
        )
        self.assertEqual(
            len(versions),
            1,
            f"Expected exactly 1 setuptools version in the sdist build environment, got: {versions}",
        )
        self.assertEqual(versions[0], self.EXPECTED_VERSION)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("Usage: test_forked_build_tools.py <expected_setuptools_version>")
    TestForkedBuildTools.EXPECTED_VERSION = sys.argv.pop(1)
    unittest.main()
