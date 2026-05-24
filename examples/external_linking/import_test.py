"""End-to-End integration test for diverse rules_pycross wheel builds."""

import unittest

import contourpy
import filelock  # pure-python (hatchling)
import numpy as np
import pandas as pd
import psycopg2
import pyproject_metadata  # pure-python (flit-core)
import pywt  # pywavelets
import rpds  # rpds-py (Rust extension)
import tomli  # pure-python (pdm-backend)


class TestWheelCompilationAndLinking(unittest.TestCase):
    def test_numpy(self):
        arr = np.array([10, 20, 30])
        self.assertEqual(arr.sum(), 60)
        print("SUCCESS: NumPy array C-extensions loaded. Sum:", arr.sum())

    def test_pandas(self):
        df = pd.DataFrame({"A": [1, 2], "B": [3, 4]})
        self.assertEqual(df["A"].sum(), 3)
        print("SUCCESS: Pandas C-extensions and DataFrames loaded successfully.")

    def test_psycopg2(self):
        # Verify import succeeds and check package attributes
        self.assertIsNotNone(psycopg2.__version__)
        print("SUCCESS: Psycopg2 C-extension linked and imported successfully. Version:", psycopg2.__version__)

    def test_contourpy(self):
        # Verify we can initialize a contour generator
        x = np.array([[0.0, 1.0], [0.0, 1.0]])
        y = np.array([[0.0, 0.0], [1.0, 1.0]])
        z = np.array([[0.0, 1.0], [1.0, 2.0]])
        generator = contourpy.contour_generator(x, y, z)
        lines = generator.lines(1.0)
        self.assertIsNotNone(lines)
        print("SUCCESS: ContourPy C++ extension compiled against NumPy headers loaded successfully.")

    def test_pywavelets(self):
        # Verify we can perform a basic wavelet transform
        cA, cD = pywt.dwt([1.0, 2.0, 3.0, 4.0], "db1")
        self.assertEqual(len(cA), 2)
        print("SUCCESS: PyWavelets C/Cython extension compiled against NumPy headers loaded successfully.")

    def test_rpds_py_rust(self):
        # Verify Rust extension compiles and functions
        m = rpds.HashTrieMap({"key": "val"})
        self.assertEqual(m["key"], "val")
        print("SUCCESS: rpds-py Rust extension built with Maturin loaded and executed successfully.")

    def test_tomli(self):
        # Verify pdm-backend fallback pure-python wheel
        d = tomli.loads("a = 1")
        self.assertEqual(d["a"], 1)
        print("SUCCESS: tomli built with pdm-backend loaded successfully.")

    def test_pyproject_metadata(self):
        # Verify flit-core pure-python wheel
        self.assertIsNotNone(pyproject_metadata.__version__)
        print("SUCCESS: pyproject-metadata built with flit-core loaded successfully.")

    def test_filelock(self):
        # Verify hatchling pure-python wheel
        lock = filelock.FileLock("dummy.lock")
        self.assertIsNotNone(lock)
        print("SUCCESS: filelock built with hatchling loaded successfully.")


if __name__ == "__main__":
    unittest.main()
