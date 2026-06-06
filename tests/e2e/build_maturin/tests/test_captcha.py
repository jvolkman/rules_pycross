import unittest

import captcha_rs


class TestCaptcha(unittest.TestCase):
    def test_import(self):
        # Just check that we can import it.
        # We can also print dir(captcha_rs) to help debugging if needed.
        print("captcha_rs members:", dir(captcha_rs))
        self.assertIsNotNone(captcha_rs)


if __name__ == "__main__":
    unittest.main()
