import unittest
import numpy as np

class TestNumPy(unittest.TestCase):
    def test_array_operations(self):
        arr = np.array([10, 20, 30])
        self.assertEqual(arr.sum(), 60)

    def test_linalg(self):
        m = np.array([[1, 2], [3, 4]])
        det = np.linalg.det(m)
        self.assertAlmostEqual(det, -2.0)

if __name__ == "__main__":
    unittest.main()
