import unittest
import pandas as pd

class TestPandas(unittest.TestCase):
    def test_dataframe(self):
        df = pd.DataFrame({"A": [1, 2], "B": [3, 4]})
        self.assertEqual(df["A"].sum(), 3)

if __name__ == "__main__":
    unittest.main()
