import os
import unittest


class TestAllWhlRequirements(unittest.TestCase):
    def test_all_whl_requirements(self):
        self.maxDiff = None
        self.assertNotEqual(os.environ["ALL_WHL_REQUIREMENTS"], "")


if __name__ == "__main__":
    unittest.main()
