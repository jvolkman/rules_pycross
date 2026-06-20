import unittest

import pywt


class TestPyWavelets(unittest.TestCase):
    def test_dwt(self):
        cA, cD = pywt.dwt([1.0, 2.0, 3.0, 4.0], "db1")
        self.assertEqual(len(cA), 2)


if __name__ == "__main__":
    unittest.main()
