"""Check that the interpreter and installed binary wheels match the expected threading build.

Environment:
  EXPECT_FREETHREADED: "1" to expect a free-threaded (PEP 703) build; otherwise a GIL build.
  PYCROSS_TEST_MODULE: a module from a binary (C extension) wheel to import and check.
  PYCROSS_TEST_DIST: the distribution name that provides PYCROSS_TEST_MODULE.
  PYCROSS_TEST_GIL_FREE: "1" if PYCROSS_TEST_MODULE declares that it doesn't need the GIL,
    so importing it on a free-threaded interpreter must keep the GIL disabled.
"""

import importlib
import importlib.machinery
import importlib.metadata
import os
import sys
import sysconfig
import unittest

EXPECT_FREETHREADED = os.environ.get("EXPECT_FREETHREADED") == "1"
MODULE = os.environ["PYCROSS_TEST_MODULE"]
DIST = os.environ["PYCROSS_TEST_DIST"]
GIL_FREE = os.environ.get("PYCROSS_TEST_GIL_FREE") == "1"

# Importing an extension that doesn't declare GIL-free support re-enables the GIL, so record the
# state before any test imports one.
GIL_ENABLED_AT_START = sys._is_gil_enabled() if hasattr(sys, "_is_gil_enabled") else True

ABI = "cp{}{}{}".format(sys.version_info[0], sys.version_info[1], "t" if EXPECT_FREETHREADED else "")


class FreethreadedTest(unittest.TestCase):
    def test_interpreter(self):
        self.assertEqual(sysconfig.get_config_var("Py_GIL_DISABLED"), 1 if EXPECT_FREETHREADED else 0)
        if EXPECT_FREETHREADED:
            self.assertFalse(GIL_ENABLED_AT_START)
            self.assertIn("python{}.{}t".format(*sys.version_info[:2]), sysconfig.get_path("stdlib"))

    def test_binary_wheel(self):
        wheel = importlib.metadata.distribution(DIST).read_text("WHEEL")
        tags = [line.split(":", 1)[1].strip() for line in wheel.splitlines() if line.startswith("Tag:")]
        self.assertTrue(tags, wheel)
        for tag in tags:
            _, abi, _ = tag.split("-")
            self.assertEqual(abi, ABI, tags)

        mod = importlib.import_module(MODULE)
        self.assertTrue(
            mod.__file__.endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES)),
            mod.__file__,
        )
        self.assertIn(sysconfig.get_config_var("SOABI"), mod.__file__)
        if EXPECT_FREETHREADED and GIL_FREE:
            self.assertFalse(sys._is_gil_enabled(), f"importing {MODULE} re-enabled the GIL")


if __name__ == "__main__":
    unittest.main()
