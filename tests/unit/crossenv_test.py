import importlib.machinery
import sys
import sysconfig
import unittest

from pycross.private.build.tools.crossenv import guess_uname
from pycross.private.build.tools.crossenv.utils import target_extension_suffixes


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


def _vars(version, platform, freethreaded=False):
    soabi = "cpython-%s%s-%s" % (version.replace(".", ""), "t" if freethreaded else "", platform)
    sysconfig_vars = {
        "EXT_SUFFIX": ".%s.so" % soabi,
        "Py_GIL_DISABLED": 1 if freethreaded else 0,
        "SOABI": soabi,
        "VERSION": version,
    }
    if version >= "3.15":
        sysconfig_vars["SOABI_PLATFORM"] = platform
    return sysconfig_vars


class TargetExtensionSuffixesTest(unittest.TestCase):
    def test_matrix(self):
        cases = {
            ("3.14", "x86_64-linux-gnu", False): [".cpython-314-x86_64-linux-gnu.so", ".abi3.so", ".so"],
            ("3.14", "x86_64-linux-gnu", True): [".cpython-314t-x86_64-linux-gnu.so", ".abi3.so", ".so"],
            ("3.14", "darwin", False): [".cpython-314-darwin.so", ".abi3.so", ".so"],
            ("3.14", "x86_64-linux-musl", False): [".cpython-314-x86_64-linux-musl.so", ".abi3.so", ".so"],
            ("3.15", "x86_64-linux-gnu", False): [
                ".cpython-315-x86_64-linux-gnu.so",
                ".abi3-x86_64-linux-gnu.so",
                ".abi3.so",
                ".abi3t-x86_64-linux-gnu.so",
                ".abi3t.so",
                ".so",
            ],
            ("3.15", "x86_64-linux-gnu", True): [
                ".cpython-315t-x86_64-linux-gnu.so",
                ".abi3t-x86_64-linux-gnu.so",
                ".abi3t.so",
                ".so",
            ],
            ("3.15", "darwin", False): [
                ".cpython-315-darwin.so",
                ".abi3-darwin.so",
                ".abi3.so",
                ".abi3t-darwin.so",
                ".abi3t.so",
                ".so",
            ],
            ("3.15", "darwin", True): [".cpython-315t-darwin.so", ".abi3t-darwin.so", ".abi3t.so", ".so"],
            ("3.15", "x86_64-linux-musl", False): [
                ".cpython-315-x86_64-linux-musl.so",
                ".abi3-x86_64-linux-musl.so",
                ".abi3.so",
                ".abi3t-x86_64-linux-musl.so",
                ".abi3t.so",
                ".so",
            ],
            ("3.15", "x86_64-linux-musl", True): [
                ".cpython-315t-x86_64-linux-musl.so",
                ".abi3t-x86_64-linux-musl.so",
                ".abi3t.so",
                ".so",
            ],
        }
        for (version, platform, freethreaded), expected in cases.items():
            with self.subTest(version=version, platform=platform, freethreaded=freethreaded):
                self.assertEqual(target_extension_suffixes(_vars(version, platform, freethreaded)), expected)

    def test_matches_running_interpreter(self):
        # Ground truth: the helper must reproduce the running CPython's own list.
        if sys.implementation.name != "cpython" or sys.platform == "win32":
            self.skipTest("POSIX CPython only")
        self.assertEqual(target_extension_suffixes(sysconfig.get_config_vars()), importlib.machinery.EXTENSION_SUFFIXES)

    def test_non_cpython(self):
        self.assertIsNone(target_extension_suffixes({"SOABI": "pypy311-pp73-x86_64-linux-gnu", "VERSION": "3.11"}))
        self.assertIsNone(target_extension_suffixes({}))


if __name__ == "__main__":
    unittest.main()
