import json
import os
import subprocess
import sys
import textwrap
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
        self.exec_python = Path(sys.executable)


class CcToolchainTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def _make_fake_cc(self) -> Path:
        fake_cc = self.temp_path / "fake_clang"
        fake_cc.write_text(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                "exec" "{sys.executable}" "-S" "$0" "$@"
                import json
                import sys

                print(json.dumps(sys.argv[1:]))
                """
            )
        )
        fake_cc.chmod(0o755)
        return fake_cc

    def test_wrap_compiler(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir()

        cflags = "-O2 -target x86_64-linux-gnu --sysroot=/tmp/sysroot"
        ldflags = "-fuse-ld=lld -B/tmp/crt -L/tmp/glibc -Wl,--as-needed -Wl,-O1 -lpthread"
        wrapper = wrap_compiler("cc", "/usr/bin/gcc", cflags, Path(sys.executable), bin_dir, ldflags=ldflags)

        self.assertTrue(wrapper.exists())
        self.assertTrue(os.access(wrapper, os.X_OK))

        content = wrapper.read_text()
        self.assertTrue(content.startswith("#!/bin/sh"))

        self.assertIn("'-target'", content)
        self.assertIn("'x86_64-linux-gnu'", content)
        self.assertIn("'--sysroot=/tmp/sysroot'", content)
        self.assertIn("linker_flags = ['-fuse-ld=lld', '-B/tmp/crt', '-L/tmp/glibc', '-lpthread']", content)

        self.assertIn("-Wl,--start-group", content)
        self.assertIn("-Wl,--end-group", content)
        self.assertIn("-Wl,--as-needed", content)

    def test_wrap_compiler_link_vs_non_link_invocations(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake_cc = self._make_fake_cc()

        cflags = "-O2 -target x86_64-linux-gnu --sysroot=/dev/null"
        ldflags = "-fuse-ld=lld -B/tmp/crt -L/tmp/glibc -Wl,--as-needed -Wl,-O1 -lpthread"
        wrapper = wrap_compiler("cc", str(fake_cc), cflags, Path(sys.executable), bin_dir, ldflags=ldflags)

        def run_wrapper(*args: str) -> list[str]:
            out = subprocess.check_output([str(wrapper), *args], text=True)
            return json.loads(out)

        expected_prefix = ["-target", "x86_64-linux-gnu", "--sysroot=/dev/null"]
        expected_linker_tail = ["-fuse-ld=lld", "-B/tmp/crt", "-L/tmp/glibc", "-lpthread"]

        # Real link: LDFLAGS appended after caller args, incompatible flags filtered from both.
        self.assertEqual(
            run_wrapper("probe.o", "-Wl,--as-needed", "-Wl,--start-group", "-lm", "-Wl,--end-group", "-o", "probe"),
            expected_prefix + ["probe.o", "-lm", "-o", "probe"] + expected_linker_tail,
        )

        # Compile / preprocess / assemble / dependency-gen / syntax-only / partial link (-r) / bare -v:
        # LDFLAGS must NOT be appended.
        non_link_cases = [
            ["-c", "probe.c", "-o", "probe.o"],
            ["-E", "probe.c"],
            ["-S", "probe.c"],
            ["-M", "probe.c"],
            ["-MM", "probe.c"],
            ["-fsyntax-only", "probe.c"],
            ["-r", "a.o", "b.o", "-o", "combined.o"],
            ["-v"],
            [],
        ]
        for case in non_link_cases:
            with self.subTest(case=case):
                self.assertEqual(run_wrapper(*case), expected_prefix + case)

    def test_wrap_compiler_shared_links_use_shared_flags(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake_cc = self._make_fake_cc()

        # Like the @llvm musl toolchain: -static-pie is executable-only.
        ldflags = "-static-pie -fuse-ld=lld -L/tmp/musl -Wl,--gc-sections"
        ldsharedflags = "-fuse-ld=lld -L/tmp/musl -Wl,--gc-sections -shared"
        wrapper = wrap_compiler(
            "cc", str(fake_cc), "-O2", Path(sys.executable), bin_dir, ldflags=ldflags, ldsharedflags=ldsharedflags
        )

        def run_wrapper(*args: str) -> list[str]:
            return json.loads(subprocess.check_output([str(wrapper), *args], text=True))

        shared_tail = ["-fuse-ld=lld", "-L/tmp/musl", "-Wl,--gc-sections"]
        for mode in ["-shared", "-bundle", "-dynamiclib"]:
            with self.subTest(mode=mode):
                self.assertEqual(
                    run_wrapper(mode, "a.o", "-o", "a.so"),
                    [mode, "a.o", "-o", "a.so"] + shared_tail,
                )

        # Executable links still get the full LDFLAGS (#330).
        self.assertEqual(
            run_wrapper("a.o", "-o", "a"),
            ["a.o", "-o", "a", "-static-pie", "-fuse-ld=lld", "-L/tmp/musl", "-Wl,--gc-sections"],
        )
        # Compiles get neither.
        self.assertEqual(run_wrapper("-shared", "-c", "a.c"), ["-shared", "-c", "a.c"])
        # distutils appends $LDFLAGS (with -static-pie) to LDSHARED itself.
        self.assertEqual(
            run_wrapper("-shared", "-static-pie", "a.o", "-o", "a.so"),
            ["-shared", "a.o", "-o", "a.so"] + shared_tail,
        )
        self.assertEqual(
            run_wrapper("-static-pie", "a.o", "-o", "a")[:4],
            ["-static-pie", "a.o", "-o", "a"],
        )

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
            "LDFLAGS": "-fuse-ld=lld -B$$EXT_BUILD_ROOT$$/crt -Wl,-O1",
            "LDSHAREDFLAGS": "-shared -Wl,-O1",
            "AR": "/usr/bin/ar",
            "ARFLAGS": "rcs",
        }

        setup_cc_layer(ctx, cc_config)

        # Assert PYCROSS_LIBRARY_PATH and PYCROSS_INCLUDE_PATH
        self.assertIn("PYCROSS_LIBRARY_PATH", ctx.build_env)
        self.assertIn("PYCROSS_INCLUDE_PATH", ctx.build_env)
        self.assertTrue(ctx.build_env["PYCROSS_LIBRARY_PATH"].endswith("cc_layer/lib"))

        # Assert wrapper received placeholder-expanded, filtered LDFLAGS
        cc_wrapper_content = Path(ctx.sysconfig_vars["CC"]).read_text()
        self.assertIn(f"'-B{self.temp_path}/crt'", cc_wrapper_content)
        self.assertIn("'-fuse-ld=lld'", cc_wrapper_content)

        # Assert LDSHARED
        self.assertIn("LDSHARED", ctx.sysconfig_vars)
        self.assertIn("-shared", ctx.sysconfig_vars["LDSHARED"])
        self.assertNotIn("-bundle", ctx.sysconfig_vars["LDSHARED"])

    def test_setup_cc_layer_mac(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.sysconfig_vars["MACHDEP"] = "darwin"

        cc_config = {
            "CC": "/usr/bin/clang",
            "CXX": "/usr/bin/clang++",
            "CFLAGS": "-O2",
            "CXXFLAGS": "-O2",
            "LDFLAGS": "-Wl,-O1",
            "LDSHAREDFLAGS": "-Wl,-O1 -shared",
            "AR": "/usr/bin/ar",
            "ARFLAGS": "rcs",
        }

        setup_cc_layer(ctx, cc_config)
        # Extensions are linked as MH_BUNDLE like CPython, not MH_DYLIB (-shared).
        ldshared = ctx.sysconfig_vars["LDSHARED"].split()
        self.assertIn("-Wl,-O1", ldshared)
        self.assertNotIn("-shared", ldshared)
        self.assertEqual(ldshared[-3:], ["-bundle", "-undefined", "dynamic_lookup"])
        self.assertEqual(ctx.sysconfig_vars["LDCXXSHARED"], ctx.sysconfig_vars["LDSHARED"])


if __name__ == "__main__":
    unittest.main()
