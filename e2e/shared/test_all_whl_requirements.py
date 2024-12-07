import os
import re
import unittest


class TestAllWhlRequirements(unittest.TestCase):
    def test_all_whl_requirements(self):
        expected = os.environ.get("EXPECTED_WHL_REQUIREMENTS", "").split(",")
        all = os.environ.get("ALL_WHL_REQUIREMENTS", "").split(",")
        all = [re.search(".*:(.*)@.*", whl).group(1) for whl in all]

        self.assertNotEqual(len(expected), 0)
        self.assertEqual(sorted(all), sorted(expected))


if __name__ == "__main__":
    unittest.main()
