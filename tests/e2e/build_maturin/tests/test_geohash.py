import unittest

import geohash


class TestGeohash(unittest.TestCase):
    def test_cycle(self):
        for code in ["000000000000", "zzzzzzzzzzzz", "bgr96qxvpd46"]:
            self.assertEqual(code, geohash.encode(*geohash.decode(code)))

    def test_ezs42(self):
        x = geohash.bbox("ezs42")
        self.assertEqual(round(x["s"], 3), 42.583)
        self.assertEqual(round(x["n"], 3), 42.627)

    def test_neighbors_empty(self):
        self.assertEqual([], geohash.neighbors(""))


if __name__ == "__main__":
    unittest.main()
