import os
import site
import sys
import unittest


class TestNamespacePkgs(unittest.TestCase):
    def test_google_cloud_namespace(self):
        # We test that we can import both from the same namespace
        from google.cloud import pubsub_v1
        from google.cloud import storage

        self.assertIsNotNone(storage)
        self.assertIsNotNone(pubsub_v1)

    def test_zope_namespace(self):
        from zope import event
        from zope import interface

        self.assertIsNotNone(interface)
        self.assertIsNotNone(event)

    def test_no_per_wheel_site_packages_on_sys_path(self):
        # Under venvs_site_packages=yes, wheels are linked into the venv's site-packages, so their
        # own install dirs must not be on sys.path (matching rules_python).
        if "_bazel_import_index" in sys.modules:
            # rules_python's import index (--venv_import_index, prototype) keeps every wheel root
            # on sys.path instead, whatever venvs_site_packages says.
            self.skipTest("the import index keeps wheel roots on sys.path")
        venv_site_packages = {os.path.realpath(p) for p in site.getsitepackages()}
        extra = [
            p
            for p in sys.path
            if os.path.basename(p.rstrip("/")) == "site-packages" and os.path.realpath(p) not in venv_site_packages
        ]
        self.assertEqual(extra, [])


if __name__ == "__main__":
    unittest.main()
