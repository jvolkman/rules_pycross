import unittest

try:
    import jiter
except ImportError:
    jiter = None


@unittest.skipIf(jiter is None, "jiter not installed")
class TestJiter(unittest.TestCase):
    def test_import(self):
        # Just check that we can import it.
        # We can also print dir(jiter) to help debugging if needed.
        print("jiter members:", dir(jiter))
        self.assertIsNotNone(jiter)


if __name__ == "__main__":
    unittest.main()
