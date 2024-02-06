import unittest

import cowsay


class TestCowsay(unittest.TestCase):
    def test_cowsay(self):
        # Just make sure it runs.
        cowsay.kitty("hello")


if __name__ == "__main__":
    unittest.main()
