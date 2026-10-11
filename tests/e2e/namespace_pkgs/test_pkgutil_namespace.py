import unittest


class TestPkgutilNamespace(unittest.TestCase):
    def test_shared_pkgutil_namespace(self):
        # backports.tarfile and backports.entry-points-selectable both ship a pkgutil-style
        # backports/__init__.py, so both must be importable from the shared namespace.
        from backports import entry_points_selectable
        from backports import tarfile

        self.assertTrue(hasattr(tarfile, "TarFile"))
        self.assertTrue(hasattr(entry_points_selectable, "entry_points"))


if __name__ == "__main__":
    unittest.main()
