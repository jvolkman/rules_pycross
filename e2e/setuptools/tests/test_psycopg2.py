import unittest
import psycopg2

class TestPsycopg2(unittest.TestCase):
    def test_import(self):
        self.assertIsNotNone(psycopg2.__version__)

if __name__ == "__main__":
    unittest.main()
