"""pkgb links against pkga's libfoo.so without bundling its own copy."""

import unittest
from pathlib import Path

import pkga  # Loads pkga/lib/libfoo.so first, as torch does for its libraries.
import pkgb


def _loaded_libfoo_paths():
    paths = set()
    for line in Path("/proc/self/maps").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 6 and "libfoo" in fields[5]:
            paths.add(fields[5])
    return sorted(paths)


class WheelCcImportTest(unittest.TestCase):
    def test_repair_does_not_bundle_libfoo(self):
        site_packages = Path(pkgb.__file__).parent.parent
        self.assertFalse((site_packages / "pkgb.libs").exists())

    def test_both_packages_share_one_libfoo(self):
        self.assertEqual(pkga.value(), 42)
        self.assertEqual(pkgb.value(), 42)
        self.assertEqual(pkga.counter_addr(), pkgb.counter_addr())
        first = pkga.inc()
        self.assertEqual(pkgb.inc(), first + 1)
        self.assertEqual(len(_loaded_libfoo_paths()), 1, _loaded_libfoo_paths())


if __name__ == "__main__":
    unittest.main()
