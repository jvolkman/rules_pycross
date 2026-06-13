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


if __name__ == "__main__":
    unittest.main()
