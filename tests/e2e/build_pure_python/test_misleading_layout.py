"""Verify an sdist with a misleading repo-time layout guess imports under venvs_site_packages=yes."""

import importlib.metadata
import unittest

import misleading_pkg


class MisleadingSdistLayoutTest(unittest.TestCase):
    def test_imports_real_package(self):
        self.assertEqual(misleading_pkg.VALUE, 42)

    def test_single_dist_info_entry(self):
        self.assertEqual(importlib.metadata.version("misleading-pkg"), "0.1.0")
        matches = [
            d
            for d in importlib.metadata.distributions()
            if (d.metadata["Name"] or "").lower().replace("_", "-") == "misleading-pkg"
        ]
        self.assertEqual(len(matches), 1)


if __name__ == "__main__":
    unittest.main()
