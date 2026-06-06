import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.utils.cc_toolchain import setup_cc_layer
from pycross.private.build.tools.utils.cc_toolchain import wrap_compiler


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.sysconfig_vars = {}
        self.build_env = {}
        self.prefix = temp_dir
        self.temp_dir = temp_dir
        self.exec_python = Path("/usr/bin/python3")


class CcToolchainTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_wrap_compiler(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir()

        cflags = "-O2 -target x86_64-linux-gnu --sysroot=/tmp/sysroot"
        wrapper = wrap_compiler("cc", "/usr/bin/gcc", cflags, Path("/usr/bin/python3"), bin_dir)

        self.assertTrue(wrapper.exists())
        self.assertTrue(os.access(wrapper, os.X_OK))

        content = wrapper.read_text()
        self.assertTrue(content.startswith("#!/bin/sh"))

        self.assertIn("'-target'", content)
        self.assertIn("'x86_64-linux-gnu'", content)
        self.assertIn("'--sysroot=/tmp/sysroot'", content)

        self.assertIn("-Wl,--start-group", content)
        self.assertIn("-Wl,--end-group", content)
        self.assertIn("-Wl,--as-needed", content)

    def test_setup_cc_layer(self):
        ctx = MockBuildContext(self.temp_path)

        lib_foo = self.temp_path / "libfoo.a"
        lib_foo.touch()
        lib_bar = self.temp_path / "libbar.so"
        lib_bar.touch()

        cc_config = {
            "static_libs": [str(lib_foo)],
            "shared_libs": [str(lib_bar)],
            "CC": "/usr/bin/gcc",
            "CXX": "/usr/bin/g++",
            "CFLAGS": "-O2",
            "CXXFLAGS": "-O2",
            "LDFLAGS": "-Wl,-O1",
            "LDSHAREDFLAGS": "-shared -Wl,-O1",
            "AR": "/usr/bin/ar",
            "ARFLAGS": "rcs",
        }

        setup_cc_layer(ctx, cc_config)

        # Assert PYCROSS_LIBRARY_PATH and PYCROSS_INCLUDE_PATH
        self.assertIn("PYCROSS_LIBRARY_PATH", ctx.build_env)
        self.assertIn("PYCROSS_INCLUDE_PATH", ctx.build_env)
        self.assertTrue(ctx.build_env["PYCROSS_LIBRARY_PATH"].endswith("cc_layer/lib"))

        # Assert LDSHARED
        self.assertIn("LDSHARED", ctx.sysconfig_vars)
        if sys.platform == "darwin" or ctx.sysconfig_vars.get("MACHDEP") == "darwin":
            self.assertIn("-undefined,dynamic_lookup", ctx.sysconfig_vars["LDSHARED"])
        self.assertIn("-shared", ctx.sysconfig_vars["LDSHARED"])

    def test_setup_cc_layer_mac(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.sysconfig_vars["MACHDEP"] = "darwin"

        cc_config = {
            "CC": "/usr/bin/clang",
            "CXX": "/usr/bin/clang++",
            "CFLAGS": "-O2",
            "CXXFLAGS": "-O2",
            "LDFLAGS": "-Wl,-O1",
            "LDSHAREDFLAGS": "-bundle -Wl,-O1",
            "AR": "/usr/bin/ar",
            "ARFLAGS": "rcs",
        }

        setup_cc_layer(ctx, cc_config)
        self.assertIn("-bundle", ctx.sysconfig_vars["LDSHARED"])
        self.assertIn("-undefined,dynamic_lookup", ctx.sysconfig_vars["LDSHARED"])


if __name__ == "__main__":
    unittest.main()
