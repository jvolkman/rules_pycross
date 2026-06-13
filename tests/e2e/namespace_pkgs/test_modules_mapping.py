import json
import os
import unittest


class TestModulesMapping(unittest.TestCase):
    def test_mapping(self):
        mapping_path = os.environ.get("MAPPING_JSON")
        self.assertTrue(mapping_path and os.path.exists(mapping_path))

        with open(mapping_path, "r") as f:
            mapping = json.load(f)

        expected = {
            "attr": "attrs",
            "attrs": "attrs",
            "bs4": "beautifulsoup4",
            "IPython": "ipython",
            "dateutil": "python-dateutil",
            "regex": "regex",
            "six": "six",
        }

        # Verify that expected mapping is a subset of actual mapping
        # (there might be more transitive mappings)
        for k, v in expected.items():
            self.assertEqual(mapping.get(k), v, f"Expected {k} -> {v}, got {mapping.get(k)}")


if __name__ == "__main__":
    unittest.main()
