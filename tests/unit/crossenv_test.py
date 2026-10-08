import unittest

from pycross.private.build.tools.crossenv import guess_uname


def _darwin_release(deployment_target):
    return guess_uname("macosx-arm64", "aarch64-apple-darwin", "arm64", deployment_target).release


class GuessUnameTest(unittest.TestCase):
    def test_darwin_release_mapping(self):
        cases = {
            "10.9": "13.0.0",
            "10.13": "17.0.0",
            "10.13.4": "17.0.0",
            "10.15": "19.0.0",
            "11": "20.0.0",
            "11.0": "20.0.0",
            "11.1": "20.0.0",
            "12.3": "21.0.0",
            "14.0": "23.0.0",
            "15.4.1": "24.0.0",
            "26.0": "25.0.0",
        }
        for target, release in cases.items():
            with self.subTest(target=target):
                self.assertEqual(_darwin_release(target), release)

    def test_invalid_deployment_target(self):
        for target in ["", "abc", "14.x", "1.2.3.4", "9.0", "16.0"]:
            with self.subTest(target=target):
                if not target:
                    # Empty means unset.
                    self.assertEqual(_darwin_release(target), "0.0.0")
                    continue
                with self.assertRaises(ValueError):
                    _darwin_release(target)

    def test_linux_ignores_deployment_target(self):
        uname = guess_uname("linux-x86_64", "x86_64-pc-linux-gnu", None, None)
        self.assertEqual(uname.sysname, "linux")
        self.assertEqual(uname.machine, "x86_64")
        self.assertEqual(uname.release, "0.0.0")


if __name__ == "__main__":
    unittest.main()
