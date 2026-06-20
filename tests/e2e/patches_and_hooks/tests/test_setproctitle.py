import unittest

import setproctitle


class TestSetproctitle(unittest.TestCase):
    def test_import(self):
        title = setproctitle.getproctitle()
        self.assertIsNotNone(title)
        self.assertTrue(setproctitle.PATCHED)
        self.assertTrue(setproctitle.POST_PATCHED)
        self.assertTrue(setproctitle.SITE_HOOK_RAN)


if __name__ == "__main__":
    unittest.main()
