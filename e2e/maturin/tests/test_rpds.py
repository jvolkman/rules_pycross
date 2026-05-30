import unittest

import rpds


class TestRpds(unittest.TestCase):
    def test_hash_trie_map(self):
        m = rpds.HashTrieMap({"key": "val"})
        self.assertEqual(m["key"], "val")

    def test_immutability(self):
        m = rpds.HashTrieMap()
        m2 = m.insert("a", 1)
        self.assertEqual(len(m), 0)
        self.assertEqual(len(m2), 1)


if __name__ == "__main__":
    unittest.main()
