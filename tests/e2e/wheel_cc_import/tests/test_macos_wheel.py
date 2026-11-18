"""The macOS pkgb wheel links pkga's libfoo without bundling a copy."""

import sys
import unittest
import zipfile
from pathlib import Path


class MacosWheelTest(unittest.TestCase):
    def test_libfoo_not_bundled(self):
        wheels = [whl for arg in sys.argv[1:] for whl in Path(arg).glob("*.whl")]
        self.assertEqual(len(wheels), 1, wheels)
        self.assertIn("macosx", wheels[0].name)
        names = zipfile.ZipFile(wheels[0]).namelist()
        self.assertTrue(any(name.startswith("pkgb/_ext") for name in names), names)
        self.assertFalse([name for name in names if "libfoo" in name or ".dylibs/" in name], names)


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
