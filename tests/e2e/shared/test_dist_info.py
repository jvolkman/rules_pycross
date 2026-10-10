"""Verify that a wheel with a mixed-case .dist-info directory is installed under its normalized name."""

import importlib.metadata
import os
import sys
import unittest
from pathlib import Path


class DistInfoNormalizationTest(unittest.TestCase):
    """Check metadata, entry points, and venv .dist-info symlink resolution for Pygments 2.16.1."""

    def test_version_and_metadata(self):
        self.assertEqual(importlib.metadata.version("Pygments"), "2.16.1")
        self.assertEqual(importlib.metadata.version("pygments"), "2.16.1")

        dist = importlib.metadata.distribution("Pygments")
        self.assertEqual(dist.metadata["Name"], "Pygments")

        dist_path = Path(dist._path)
        self.assertEqual(dist_path.name, "pygments-2.16.1.dist-info")
        self.assertTrue(dist_path.is_dir())

    def test_entry_points(self):
        dist = importlib.metadata.distribution("Pygments")
        console_eps = [ep for ep in dist.entry_points if ep.group == "console_scripts" and ep.name == "pygmentize"]
        self.assertEqual(len(console_eps), 1)
        self.assertEqual(console_eps[0].value, "pygments.cmdline:main")

    def test_venv_dist_info_symlink_resolves(self):
        if os.environ.get("PYCROSS_EXPECT_VENV_DIST_INFO") != "1":
            return

        venv_site_packages = [Path(p) for p in sys.path if ".venv" in p and p.endswith("site-packages")]
        self.assertTrue(
            venv_site_packages,
            f"Expected a .venv site-packages entry on sys.path, got: {sys.path}",
        )
        venv_sp = venv_site_packages[0]
        dist_info_link = venv_sp / "pygments-2.16.1.dist-info"
        self.assertTrue(
            dist_info_link.is_symlink(),
            f"Expected {dist_info_link} to be a symlink in venv site-packages",
        )
        self.assertTrue(
            dist_info_link.exists(),
            f"Dangling venv .dist-info symlink: {dist_info_link} -> {os.readlink(dist_info_link)}",
        )
        self.assertTrue((dist_info_link / "METADATA").is_file())


if __name__ == "__main__":
    unittest.main()
