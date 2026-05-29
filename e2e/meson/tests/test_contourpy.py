import unittest
import contourpy
import numpy as np

class TestContourPy(unittest.TestCase):
    def test_contour_generator(self):
        x = np.array([[0.0, 1.0], [0.0, 1.0]])
        y = np.array([[0.0, 0.0], [1.0, 1.0]])
        z = np.array([[0.0, 1.0], [1.0, 2.0]])
        gen = contourpy.contour_generator(x, y, z)
        lines = gen.lines(1.0)
        self.assertIsNotNone(lines)

if __name__ == "__main__":
    unittest.main()
