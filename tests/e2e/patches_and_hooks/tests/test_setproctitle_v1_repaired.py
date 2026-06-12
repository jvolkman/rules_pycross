import unittest

import setproctitle


class TestSetproctitleV1Repaired(unittest.TestCase):
    def test_v1_repaired(self):
        # Verify python pre-build hook ran and imported dep
        self.assertEqual(getattr(setproctitle, "PY_PRE_BUILD_HOOK_MARKER", None), "Hello from dep")

        # Verify setproctitle actually works
        setproctitle.setproctitle("my_test_title")


if __name__ == "__main__":
    unittest.main()
