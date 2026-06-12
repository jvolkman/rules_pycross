import os
import unittest


class TestAllWhlRequirements(unittest.TestCase):
    def test_all_whl_requirements(self):
        expected = os.environ.get("EXPECTED_WHL_REQUIREMENTS", "").split(",")
        raw_all = os.environ.get("ALL_WHL_REQUIREMENTS", "").split(",")
        all = [whl.split("//")[-1].split(":")[0] for whl in raw_all if whl]

        self.assertNotEqual(len(expected), 0)
        self.assertTrue(set(expected).issubset(set(all)), f"Expected {expected} to be subset of {all}")


if __name__ == "__main__":
    unittest.main()
