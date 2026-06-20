import unittest

import regex


class TestRegex(unittest.TestCase):
    def test_regex(self):
        assert regex.match(".*(jump).*", "The quick brown fox jumps over the lazy dog")


if __name__ == "__main__":
    unittest.main()
