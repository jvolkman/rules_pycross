import json
import ntpath
import os
import shlex
import shutil
import subprocess
import sys
import textwrap
import unittest
from contextlib import chdir
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from pycross.private.build.tools.utils.cc_toolchain import _resolve_msvc_environment
from pycross.private.build.tools.utils.cc_toolchain import get_wrapper_flags
from pycross.private.build.tools.utils.cc_toolchain import join_flags
from pycross.private.build.tools.utils.cc_toolchain import setup_cc_layer
from pycross.private.build.tools.utils.cc_toolchain import unversioned_library_name
from pycross.private.build.tools.utils.cc_toolchain import wrap_compiler
from pycross.private.build.tools.utils.context import load_build_context
from pycross.private.build.tools.utils.path_tools import setup_path_tools


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.sysconfig_vars = {}
        self.build_env = {}
        self.prefix = temp_dir
        self.temp_dir = temp_dir
        self.exec_python = Path(sys.executable)
        self.cc_layer = None


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

        compile_flags = ["-O2", "-target", "x86_64-linux-gnu", "--sysroot=/tmp/sysroot"]
        ldflags = ["-fuse-ld=lld", "-B/tmp/crt", "-L/tmp/glibc", "-Wl,--as-needed", "-Wl,-O1", "-lpthread"]
        wrapper = wrap_compiler("cc", "/usr/bin/gcc", compile_flags, bin_dir, ldflags=ldflags)

        self.assertTrue(wrapper.exists())
        self.assertTrue(os.access(wrapper, os.X_OK))

        content = wrapper.read_text()
        self.assertTrue(content.startswith("#!/bin/sh"))
        self.assertNotIn("import os", content)

        self.assertIn("-target x86_64-linux-gnu --sysroot=/tmp/sysroot", content)
        self.assertIn("-fuse-ld=lld -B/tmp/crt -L/tmp/glibc -lpthread", content)

        self.assertIn("-Wl,--start-group", content)
        self.assertIn("-Wl,--end-group", content)
        self.assertIn("-Wl,--as-needed", content)

    def test_get_wrapper_flags_trailing_flag(self):
        self.assertEqual(get_wrapper_flags(["-O2", "-target"]), [])
        self.assertEqual(get_wrapper_flags(["-O2", "--sysroot=/tmp/s", "-isysroot"]), ["--sysroot=/tmp/s"])

    def test_wrap_compiler_link_vs_non_link_invocations(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake_cc = self._make_fake_cc()

        compile_flags = ["-O2", "-target", "x86_64-linux-gnu", "--sysroot=/dev/null"]
        ldflags = [
            "-fuse-ld=lld",
            "-B/tmp/crt",
            "-L/tmp/glibc",
            "-Wl,-rpath,$ORIGIN",
            "-Wl,--as-needed",
            "-Wl,-O1",
            "-lpthread",
        ]
        wrapper = wrap_compiler("cc", str(fake_cc), compile_flags, bin_dir, ldflags=ldflags)

        def run_wrapper(*args: str) -> list[str]:
            out = subprocess.check_output([str(wrapper), *args], text=True)
            return json.loads(out)

        expected_prefix = ["-target", "x86_64-linux-gnu", "--sysroot=/dev/null"]
        expected_linker_tail = ["-fuse-ld=lld", "-B/tmp/crt", "-L/tmp/glibc", "-Wl,-rpath,$ORIGIN", "-lpthread"]

        # Real link: LDFLAGS appended after caller args, incompatible flags filtered from both,
        # and `$ORIGIN` is preserved literally without shell expansion.
        self.assertEqual(
            run_wrapper("probe.o", "-Wl,--as-needed", "-Wl,--start-group", "-lm", "-Wl,--end-group", "-o", "probe"),
            expected_prefix + ["probe.o", "-lm", "-o", "probe"] + expected_linker_tail,
        )

        # Spaces, single/double quotes, empty args, leading dashes, and glob chars survive POSIX /bin/sh intact.
        self.assertEqual(
            run_wrapper("-c", '-DFOO="a b"', "-DBAR='c d'", "", "-n", "--", "*.c", "-o", "probe.o"),
            expected_prefix + ["-c", '-DFOO="a b"', "-DBAR='c d'", "", "-n", "--", "*.c", "-o", "probe.o"],
        )

        # Compile / preprocess / assemble / dependency-gen / syntax-only / partial link (-r) /
        # compiler probes / bare -v: LDFLAGS must NOT be appended.
        non_link_cases = [
            ["-c", "probe.c", "-o", "probe.o"],
            ["-E", "probe.c"],
            ["-S", "probe.c"],
            ["-M", "probe.c"],
            ["-MM", "probe.c"],
            ["-fsyntax-only", "probe.c"],
            ["-r", "a.o", "b.o", "-o", "combined.o"],
            ["--version"],
            ["-dumpmachine"],
            ["-dumpversion"],
            ["-dumpfullversion"],
            ["--help"],
            ["--help=common"],
            ["-print-search-dirs"],
            ["--print-search-dirs"],
            ["-print-file-name=libc.a"],
            ["-v"],
            [],
        ]
        for case in non_link_cases:
            with self.subTest(case=case):
                self.assertEqual(run_wrapper(*case), expected_prefix + case)

    def test_wrap_compiler_large_arg_list_fast_path(self):
        """A multi-thousand-arg link line without filtered flags takes the linear fast path."""
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake_cc = self._make_fake_cc()

        wrapper = wrap_compiler("cc", str(fake_cc), ["-O2"], bin_dir, ldflags=["-lpthread"])
        # Confirm the wrapper checks needs_filter before rebuilding "$@".
        content = wrapper.read_text()
        self.assertIn("needs_filter=0", content)
        self.assertIn('if [ "$needs_filter" -eq 1 ]; then', content)

        obj_args = [f"obj_{i}.o" for i in range(3000)] + ["-o", "big_bin"]
        result = json.loads(subprocess.check_output([str(wrapper), *obj_args], text=True, timeout=5))
        self.assertEqual(result, obj_args + ["-lpthread"])

    def test_wrap_compiler_shared_links_use_shared_flags(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake_cc = self._make_fake_cc()

        # Like the @llvm musl toolchain: -static-pie is executable-only.
        ldflags = ["-static-pie", "-fuse-ld=lld", "-L/tmp/musl", "-Wl,--gc-sections"]
        ldsharedflags = ["-fuse-ld=lld", "-L/tmp/musl", "-Wl,--gc-sections", "-shared"]
        wrapper = wrap_compiler("cc", str(fake_cc), ["-O2"], bin_dir, ldflags=ldflags, ldsharedflags=ldsharedflags)

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

    def test_wrap_compiler_preserves_caller_archive_groups_on_linux(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir()
        fake_cc = self._make_fake_cc()
        start = "-Wl,--start-group"
        end = "-Wl,--end-group"
        archives = ["lib a.a", "libb.a"]
        group = [start, *archives, end]

        for target_os in ("linux", "darwin", "windows", None):
            with self.subTest(target_os=target_os):
                wrapper = wrap_compiler(
                    "cc",
                    str(fake_cc),
                    [],
                    bin_dir,
                    ldflags=[start, "-lexecutable", end],
                    ldsharedflags=["-shared", end, "-lshared"],
                    target_os=target_os,
                )

                args = ["probe.o", "-Wl,--as-needed", "-Wl,-start_group", *group, "-Wl,-end_group"]
                expected_args = ["probe.o", *(group if target_os == "linux" else archives)]
                for modes, tail in (([], "-lexecutable"), (["-shared"], "-lshared")):
                    actual = json.loads(subprocess.check_output([str(wrapper), *modes, *args], text=True))
                    self.assertEqual(actual, [*modes, *expected_args, tail])

    def test_wrap_compiler_preserves_linux_groups_across_driver_syntax(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir()
        wrapper = wrap_compiler("cc", str(self._make_fake_cc()), [], bin_dir, ldflags=["-lpthread"], target_os="linux")
        start = "-Wl,--start-group"
        end = "-Wl,--end-group"

        for caller_args, expected in (
            ([start, "liba.a", "-Xlinker", "--end-group"], [start, "liba.a", "-Xlinker", "--end-group", "-lpthread"]),
            (["-Xlinker", "--start-group", "liba.a", end], ["-Xlinker", "--start-group", "liba.a", end, "-lpthread"]),
            (["-r", start, "liba.a", end], ["-r", start, "liba.a", end]),
            (["-c", start, "probe.c", end], ["-c", "probe.c"]),
        ):
            with self.subTest(caller_args=caller_args):
                actual = json.loads(subprocess.check_output([str(wrapper), *caller_args], text=True))
                self.assertEqual(actual, expected)

    def test_setup_cc_layer_exports_no_toolchain_ldflags(self):
        ctx = MockBuildContext(self.temp_path)
        fake_cc = self._make_fake_cc()
        cc_config = {
            "CC": str(fake_cc),
            "CXX": str(fake_cc),
            "CFLAGS": ["-O2"],
            "CXXFLAGS": ["-O2"],
            "target_os": "linux",
            # Like hermetic-llvm 0.8.24 on glibc.
            "LDFLAGS": ["-fuse-ld=lld", "-no-pie", "-Wl,-S"],
            "LDSHAREDFLAGS": ["-fuse-ld=lld", "-shared", "-Wl,-S", "-Wl,--end-group"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
        }

        setup_cc_layer(ctx, cc_config)

        # Build systems apply LDFLAGS to every link; the wrapper is the single source
        # of the toolchain's link flags, so LDFLAGS only carries pycross's own additions.
        layer_lib = self.temp_path / "cc_layer" / "lib"
        self.assertEqual(ctx.sysconfig_vars["LDFLAGS"], f"-L{layer_lib}")
        self.assertEqual(ctx.build_env["LDFLAGS"], ctx.sysconfig_vars["LDFLAGS"])
        # LDSHARED / LDCXXSHARED pass only -shared (wrapper appends shared_linker_flags once).
        self.assertEqual(ctx.sysconfig_vars["LDSHARED"], f"{ctx.sysconfig_vars['CC']} -shared")
        self.assertEqual(ctx.sysconfig_vars["LDCXXSHARED"], f"{ctx.sysconfig_vars['CXX']} -shared")

        def run_wrapper(*args: str) -> list[str]:
            return json.loads(subprocess.check_output([ctx.sysconfig_vars["CC"], *args], text=True))

        # distutils-style shared link (LDSHARED + $LDFLAGS): shared-valid flags appear once,
        # and no executable-only ones (-no-pie).
        ldshared = shlex.split(ctx.sysconfig_vars["LDSHARED"])[1:]
        group = ["-Wl,--start-group", "liba.a", "libb.a", "-Wl,--end-group"]
        self.assertEqual(
            run_wrapper(*ldshared, *shlex.split(ctx.sysconfig_vars["LDFLAGS"]), "a.o", *group, "-o", "a.so"),
            ["-shared", f"-L{layer_lib}", "a.o", *group, "-o", "a.so", "-fuse-ld=lld", "-Wl,-S"],
        )
        # Executable links get the executable set, including -no-pie.
        self.assertEqual(run_wrapper("a.o", "-o", "a"), ["a.o", "-o", "a", "-fuse-ld=lld", "-no-pie", "-Wl,-S"])

    def test_setup_cc_layer_cxx_wrapper_uses_cxxflags(self):
        ctx = MockBuildContext(self.temp_path)
        fake_cc = self._make_fake_cc()
        cc_config = {
            "CC": str(fake_cc),
            "CXX": str(fake_cc),
            "CFLAGS": ["-O2", "-target", "x86_64-linux-gnu", "--sysroot=/c-sysroot"],
            "CXXFLAGS": ["-O2", "-target", "aarch64-apple-darwin", "-isysroot", "/cxx-sdk", "--sysroot=/cxx-sysroot"],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": ["-shared"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
        }

        setup_cc_layer(ctx, cc_config)

        cc_out = json.loads(subprocess.check_output([ctx.sysconfig_vars["CC"], "-c", "a.c"], text=True))
        cxx_out = json.loads(subprocess.check_output([ctx.sysconfig_vars["CXX"], "-c", "a.cc"], text=True))

        self.assertEqual(cc_out, ["-target", "x86_64-linux-gnu", "--sysroot=/c-sysroot", "-c", "a.c"])
        self.assertEqual(
            cxx_out,
            ["-target", "aarch64-apple-darwin", "-isysroot", "/cxx-sdk", "--sysroot=/cxx-sysroot", "-c", "a.cc"],
        )
        self.assertNotIn("LDSHAREDFLAGS", ctx.sysconfig_vars)
        self.assertNotIn("LDSHAREDFLAGS", ctx.build_env)
        self.assertFalse((self.temp_path / "cc_layer" / "include").exists())

    def test_setup_cc_layer(self):
        ctx = MockBuildContext(self.temp_path)

        lib_foo = self.temp_path / "libfoo.pic.a"
        lib_foo.touch()
        lib_bar = self.temp_path / "libbar.so"
        lib_bar.touch()

        cc_config = {
            "static_libs": [str(lib_foo)],
            "shared_libs": [str(lib_bar)],
            "CC": "/usr/bin/gcc",
            "CXX": "/usr/bin/g++",
            "CFLAGS": ["-O2"],
            "CXXFLAGS": ["-O2"],
            "LDFLAGS": ["-fuse-ld=lld", "-B$$EXT_BUILD_ROOT$$/crt", "-Wl,-O1"],
            "LDSHAREDFLAGS": ["-shared", "-Wl,-O1"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
        }

        setup_cc_layer(ctx, cc_config)

        # Assert PYCROSS_LIBRARY_PATH and PYCROSS_INCLUDE_PATH
        self.assertIn("PYCROSS_LIBRARY_PATH", ctx.build_env)
        self.assertIn("PYCROSS_INCLUDE_PATH", ctx.build_env)
        self.assertEqual(Path(ctx.build_env["PYCROSS_LIBRARY_PATH"]), self.temp_path / "cc_layer" / "lib")

        # PIC archive gets both libfoo.pic.a and libfoo.a symlinks so -lfoo resolves.
        lib_dir = Path(ctx.build_env["PYCROSS_LIBRARY_PATH"])
        self.assertEqual((lib_dir / "libfoo.pic.a").resolve(), lib_foo.resolve())
        self.assertEqual((lib_dir / "libfoo.a").resolve(), lib_foo.resolve())

        # Assert wrapper received placeholder-expanded, filtered LDFLAGS
        cc_wrapper_content = Path(ctx.sysconfig_vars["CC"]).read_text()
        self.assertIn(f"-B{self.temp_path}/crt", cc_wrapper_content)
        self.assertIn("-fuse-ld=lld", cc_wrapper_content)

        # Assert LDSHARED and LDCXXSHARED
        self.assertIn("LDSHARED", ctx.sysconfig_vars)
        self.assertIn("-shared", ctx.sysconfig_vars["LDSHARED"])
        self.assertNotIn("-bundle", ctx.sysconfig_vars["LDSHARED"])
        self.assertTrue(ctx.sysconfig_vars["LDCXXSHARED"].startswith(ctx.sysconfig_vars["CXX"]))

    def test_setup_cc_layer_uses_msvc_action_environment(self):
        execroot = self.temp_path.resolve() / "exec root"
        execroot.mkdir()
        tool_dir = execroot / "external" / "MSVC tools" / "bin"
        config_path = execroot / "config.json"
        user_tool_dir = self.temp_path / "user tools"
        for bin_dir in (tool_dir, user_tool_dir):
            bin_dir.mkdir(parents=True)
            for tool in ("cl.exe", "link.exe"):
                exe = bin_dir / tool
                exe.touch()
                exe.chmod(0o755)
        config_path.write_text(
            json.dumps(
                {
                    "sdist": "source.tar.gz",
                    "exec_python": sys.executable,
                    "target_python": sys.executable,
                    "wheel_dir": "wheel",
                    "build_env": {"Path": str(user_tool_dir), "Include": "user headers", "Lib": "user libraries"},
                }
            )
        )
        static_sdk_dir = self.temp_path / "Windows SDK"
        cc_config = {
            "CC": "external/MSVC tools/bin/cl.exe",
            "CXX": "$$EXT_BUILD_ROOT$$/external/MSVC tools/bin/cl.exe",
            "CFLAGS": ["-nologo"],
            "CXXFLAGS": ["-nologo", "-std:c++17"],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": [],
            "AR": str(tool_dir / "lib.exe"),
            "ARFLAGS": [],
            "include_dirs": ["$$EXT_BUILD_ROOT$$/dep include"],
            "msvc_env": {
                "PATH": "external/MSVC tools/bin;$$EXT_BUILD_ROOT$$/SDK bin",
                "INCLUDE": f"external/MSVC tools/include;{static_sdk_dir / 'include'}",
                "LIB": "bazel-out/sdk/lib;$$EXT_BUILD_ROOT$$/MSVC libs",
            },
        }
        action_env = {"PATH": "inherited", "PYCROSS_BUILD_ROOT": "scratch", "PYCROSS_SDIST_DIR": "source"}
        with (
            patch.dict(os.environ, action_env),
            patch("pycross.private.build.tools.utils.context.os", wraps=os) as context_os,
            patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os,
        ):
            context_os.name = cc_os.name = "nt"
            context_os.environ = os.environ
            cc_os.pathsep = ";"
            with chdir(execroot):
                ctx = load_build_context(str(config_path))
            ctx.sysconfig_vars.update({"LDSHARED": "link.exe /DLL", "LDCXXSHARED": "link.exe /DLL"})
            self.assertEqual(ctx.temp_dir, execroot / "scratch")
            self.assertEqual(execroot / ctx.build_env["PYCROSS_SDIST_DIR"], ctx.sdist_root_dir)
            ctx.sdist_dir.mkdir(parents=True)
            with chdir(ctx.sdist_dir):
                setup_cc_layer(ctx, cc_config)

        self.assertEqual(
            [Path(path) for path in ctx.build_env["PATH"].split(";")],
            [tool_dir, execroot / "SDK bin", user_tool_dir],
        )
        self.assertEqual(ctx.sysconfig_vars["CC"], str(tool_dir / "cl.exe"))
        self.assertEqual(ctx.sysconfig_vars["CXX"], str(tool_dir / "cl.exe"))
        self.assertEqual(ctx.build_env["CC"], str(tool_dir / "cl.exe"))
        self.assertEqual(ctx.build_env["CXX"], str(tool_dir / "cl.exe"))
        self.assertEqual(ctx.sysconfig_vars["LDSHARED"], "link.exe /DLL")
        self.assertEqual(ctx.sysconfig_vars["LDCXXSHARED"], "link.exe /DLL")
        self.assertEqual(list((ctx.temp_dir / "cc_layer" / "bin").iterdir()), [])
        self.assertEqual(
            [Path(path) for path in ctx.build_env["INCLUDE"].split(";")],
            [tool_dir.parent / "include", static_sdk_dir / "include"],
        )
        self.assertEqual(
            [Path(path) for path in ctx.build_env["LIB"].split(";")],
            [execroot / "bazel-out" / "sdk" / "lib", execroot / "MSVC libs"],
        )
        self.assertEqual(
            [Path(path) for path in ctx.build_env["PYCROSS_INCLUDE_PATH"].split(";")],
            [execroot / "dep include"],
        )
        self.assertEqual(ctx.build_env["DISTUTILS_USE_SDK"], "1")
        for key in ("Path", "Include", "Lib"):
            self.assertNotIn(key, ctx.build_env)
        search_path = ctx.build_env["PATH"].replace(";", os.pathsep)
        for tool in ("cl.exe", "link.exe"):
            self.assertEqual(Path(shutil.which(tool, path=search_path)), tool_dir / tool)

    def test_resolve_msvc_environment_normalizes_sdk_paths(self):
        ctx = MockBuildContext(Path("C:/execroot"))
        inherited_path = "D:/custom/../bin;E://user tools//bin"
        environment = {
            "PATH": "C:/Program Files/MSVC/../bin;$$EXT_BUILD_ROOT$$/SDK/../SDK bin;external/SDK café/bin;;",
            "INCLUDE": "C:/Windows SDK/include/../ucrt;external/Unicode café/../headers;"
            "$$EXT_BUILD_ROOT$$/headers space;;",
            "LIB": "external/MSVC lib/../x64;C:/Program Files/MSVC lib/../lib;",
        }

        with (
            patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os,
            patch("pycross.private.build.tools.utils.context.os", wraps=os) as context_os,
        ):
            cc_os.path = ntpath
            cc_os.pathsep = ";"
            context_os.path = ntpath
            resolved = _resolve_msvc_environment(ctx, environment, inherited_path)

        self.assertEqual(
            resolved["PATH"],
            r"C:\Program Files\bin;C:\execroot\SDK bin;C:\execroot\external\SDK café\bin;;;" + inherited_path,
        )
        self.assertEqual(
            resolved["INCLUDE"],
            r"C:\Windows SDK\ucrt;C:\execroot\external\headers;C:\execroot\headers space;;",
        )
        self.assertEqual(resolved["LIB"], r"C:\execroot\external\x64;C:\Program Files\lib;")

    def test_resolve_msvc_environment_appends_inherited_path_after_sdk_paths(self):
        ctx = MockBuildContext(Path("C:/execroot"))
        inherited_path = "D:/inherited/../bin;E://user tools//bin"
        cases = (
            (
                "sdk-first",
                "C:/SDK/temp/../bin;external/SDK tools",
                inherited_path,
                r"C:\SDK\bin;C:\execroot\external\SDK tools;" + inherited_path,
            ),
            ("empty-sdk-path", "", inherited_path, inherited_path),
            ("empty-inherited-fallback", "C:/SDK/temp/../bin", "", r"C:\SDK\bin"),
            (
                "preserve-empty-sdk-entries",
                "C:/SDK/temp/../bin;;",
                inherited_path,
                r"C:\SDK\bin;;;" + inherited_path,
            ),
        )

        with (
            patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os,
            patch("pycross.private.build.tools.utils.context.os", wraps=os) as context_os,
        ):
            cc_os.path = ntpath
            cc_os.pathsep = ";"
            context_os.path = ntpath
            for label, sdk_path, inherited, expected in cases:
                with self.subTest(label=label):
                    self.assertEqual(_resolve_msvc_environment(ctx, {"PATH": sdk_path}, inherited)["PATH"], expected)
            self.assertEqual(_resolve_msvc_environment(ctx, {}, inherited_path), {})

    def test_setup_cc_layer_puts_sdk_tools_before_inherited_path_without_wrappers(self):
        execroot = self.temp_path.resolve()
        sdk_tools = execroot / "sdk tools"
        user_tools = execroot / "user tools"
        sdk_tools.mkdir()
        user_tools.mkdir()
        for directory in (sdk_tools, user_tools):
            (directory / "cl.exe").touch()
            (directory / "cl.exe").chmod(0o755)

        ctx = MockBuildContext(execroot)
        ctx.build_env["PATH"] = str(user_tools)
        cc_config = {
            "CC": str(sdk_tools / "cl.exe"),
            "CXX": str(sdk_tools / "cl.exe"),
            "CFLAGS": [],
            "CXXFLAGS": [],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": [],
            "AR": "lib.exe",
            "ARFLAGS": [],
            "msvc_env": {"PATH": "sdk tools", "INCLUDE": "", "LIB": ""},
        }
        with patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os:
            cc_os.name = "nt"
            cc_os.pathsep = ";"
            setup_cc_layer(ctx, cc_config)

        paths = ctx.build_env["PATH"].split(";")
        self.assertEqual(paths[0], str(execroot / "sdk tools"))
        self.assertEqual(paths[1], str(user_tools))
        self.assertNotIn(str(ctx.temp_dir / "cc_layer" / "bin"), paths)
        self.assertEqual(ctx.sysconfig_vars["CC"], str(sdk_tools / "cl.exe"))
        self.assertEqual(ctx.sysconfig_vars["CXX"], str(sdk_tools / "cl.exe"))
        self.assertEqual(list((ctx.temp_dir / "cc_layer" / "bin").iterdir()), [])
        self.assertEqual(Path(shutil.which("cl.exe", path=os.pathsep.join(paths))), sdk_tools / "cl.exe")
        self.assertNotIn("DISTUTILS_USE_SDK", ctx.build_env)

    def test_incomplete_msvc_environment_does_not_enable_sdk(self):
        tool_path = self.temp_path / "external" / "MSVC tools" / "bin" / "cl.exe"
        tool_path.parent.mkdir(parents=True, exist_ok=True)
        tool_path.touch()
        for msvc_env in (
            {},
            {"PATH": "", "INCLUDE": "headers", "LIB": "libraries"},
            {"PATH": "prepared", "INCLUDE": "", "LIB": "libraries"},
            {"PATH": "prepared", "INCLUDE": "headers", "LIB": ""},
            {"PATH": "prepared"},
            {"INCLUDE": "headers", "LIB": "libraries"},
        ):
            with self.subTest(msvc_env=msvc_env):
                ctx = MockBuildContext(self.temp_path)
                inherited_path = str(self.temp_path / "inherited tools")
                ctx.build_env["PATH"] = inherited_path
                cc_config = {
                    "CC": "external/MSVC tools/bin/cl.exe",
                    "CXX": "$$EXT_BUILD_ROOT$$/external/MSVC tools/bin/cl.exe",
                    "CFLAGS": [],
                    "CXXFLAGS": [],
                    "LDFLAGS": [],
                    "LDSHAREDFLAGS": [],
                    "AR": "ar",
                    "ARFLAGS": [],
                    "msvc_env": msvc_env,
                }
                with patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os:
                    cc_os.name = "nt"
                    cc_os.pathsep = ";"
                    setup_cc_layer(ctx, cc_config)
                for key, value in msvc_env.items():
                    if key == "PATH":
                        expected = inherited_path if not value else f"{self.temp_path / value};{inherited_path}"
                    else:
                        expected = str(self.temp_path / value) if value else ""
                    self.assertEqual(ctx.build_env[key], expected)
                if "PATH" not in msvc_env:
                    self.assertEqual(ctx.build_env["PATH"], inherited_path)
                self.assertEqual(ctx.sysconfig_vars["CC"], str(tool_path))
                self.assertEqual(ctx.sysconfig_vars["CXX"], str(tool_path))
                self.assertNotIn("DISTUTILS_USE_SDK", ctx.build_env)
                self.assertEqual(list((ctx.temp_dir / "cc_layer" / "bin").iterdir()), [])
                self.assertNotIn("LDSHARED", ctx.sysconfig_vars)
                self.assertNotIn("LDCXXSHARED", ctx.sysconfig_vars)

    def test_unversioned_library_name(self):
        self.assertEqual(unversioned_library_name("libcudart.so.12"), "libcudart.so")
        self.assertEqual(unversioned_library_name("libarrow.so.1900.1.0"), "libarrow.so")
        self.assertEqual(unversioned_library_name("libarrow.1900.dylib"), "libarrow.dylib")
        self.assertIsNone(unversioned_library_name("libfoo.so"))
        self.assertIsNone(unversioned_library_name("libfoo.dylib"))
        self.assertIsNone(unversioned_library_name("libfoo.a"))

    def test_setup_cc_layer_links_unversioned_name(self):
        ctx = MockBuildContext(self.temp_path)
        versioned = self.temp_path / "libcudart.so.12"
        versioned.touch()
        cc_config = {
            "shared_libs": [str(versioned)],
            "CC": "/usr/bin/gcc",
            "CXX": "/usr/bin/g++",
            "CFLAGS": [],
            "CXXFLAGS": [],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": ["-shared"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
        }
        setup_cc_layer(ctx, cc_config)
        lib_dir = Path(ctx.build_env["PYCROSS_LIBRARY_PATH"])
        self.assertEqual((lib_dir / "libcudart.so").resolve(), versioned.resolve())
        self.assertEqual((lib_dir / "libcudart.so.12").resolve(), versioned.resolve())

    def test_setup_cc_layer_mac(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.sysconfig_vars["MACHDEP"] = "darwin"

        cc_config = {
            "CC": "/usr/bin/clang",
            "CXX": "/usr/bin/clang++",
            "CFLAGS": ["-O2"],
            "CXXFLAGS": ["-O2"],
            "LDFLAGS": ["-Wl,-O1"],
            "LDSHAREDFLAGS": ["-Wl,-O1", "-shared"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
        }

        setup_cc_layer(ctx, cc_config)
        # Extensions are linked as MH_BUNDLE like CPython, not MH_DYLIB (-shared).
        ldshared = ctx.sysconfig_vars["LDSHARED"].split()
        # Toolchain link flags come from the wrapper, not LDSHARED.
        self.assertNotIn("-Wl,-O1", ldshared)
        self.assertNotIn("-shared", ldshared)
        self.assertEqual(ldshared[-3:], ["-bundle", "-undefined", "dynamic_lookup"])
        self.assertTrue(ctx.sysconfig_vars["LDSHARED"].startswith(ctx.sysconfig_vars["CC"]))
        self.assertTrue(ctx.sysconfig_vars["LDCXXSHARED"].startswith(ctx.sysconfig_vars["CXX"]))
        self.assertEqual(ctx.sysconfig_vars["LDCXXSHARED"].split()[-3:], ["-bundle", "-undefined", "dynamic_lookup"])

    def test_setup_cc_layer_state_quoting_and_filtering(self):
        ctx = MockBuildContext(self.temp_path)
        spaced_inc = self.temp_path / "dep include"
        libcxx_inc = self.temp_path / "libcxx" / "include"
        spaced_rt = self.temp_path / "rt libs" / "libc++.a"
        cc_config = {
            "CC": "/usr/bin/clang",
            "CXX": "/usr/bin/clang++",
            # -nostdlibinc only in CXXFLAGS must still filter libcxx consistently everywhere.
            "CFLAGS": ["-O2", '-D__DATE__="redacted"'],
            "CXXFLAGS": ["-nostdlibinc", "-O2"],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": ["-shared"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
            "include_dirs": [str(spaced_inc), str(libcxx_inc), str(spaced_inc)],
            "runtime_libs": [str(spaced_rt)],
        }

        state = setup_cc_layer(ctx, cc_config)

        self.assertIs(ctx.cc_layer, state)
        self.assertEqual(state.include_dirs, [spaced_inc.absolute()])
        self.assertEqual(state.runtime_libs, [spaced_rt.absolute()])
        self.assertEqual(state.cflags, ["-O2", '-D__DATE__="redacted"', f"-I{spaced_inc.absolute()}"])
        self.assertEqual(state.cxxflags, ["-nostdlibinc", "-O2", f"-I{spaced_inc.absolute()}"])
        self.assertEqual(state.ldflags, [f"-L{state.layer_lib_dir}", str(spaced_rt.absolute())])
        self.assertEqual(state.arflags, ["rcs"])

        # Spaced include dirs and runtime libs are properly shell-quoted in sysconfig_vars.
        self.assertEqual(shlex.split(ctx.sysconfig_vars["CFLAGS"]), state.cflags)
        self.assertEqual(shlex.split(ctx.sysconfig_vars["LDFLAGS"]), state.ldflags)
        self.assertEqual(ctx.build_env["PYCROSS_INCLUDE_PATH"], str(spaced_inc.absolute()))
        self.assertNotIn("libcxx", ctx.build_env["PYCROSS_INCLUDE_PATH"])
        for key in ("CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "AR", "ARFLAGS"):
            self.assertEqual(ctx.build_env[key], ctx.sysconfig_vars[key])

    def test_join_flags_posix_and_windows(self):
        self.assertEqual(join_flags([]), "")
        self.assertEqual(
            join_flags(["-nologo", r"-IC:\a\b", r"-IC:\a b\c"], posix=False),
            r'-nologo -IC:\a\b "-IC:\a b\c"',
        )
        self.assertEqual(
            join_flags(["-O2", "-I/path with spaces/inc"], posix=True),
            "-O2 '-I/path with spaces/inc'",
        )

    def test_setup_path_tools_posix_wrapper(self):
        tools_dir = self.temp_path / "tools"
        env_dir = self.temp_path / "venv"
        (env_dir / "bin").mkdir(parents=True)
        (env_dir / "bin" / "python").symlink_to(sys.executable)

        spaced_dir = self.temp_path / "dir with spaces"
        spaced_dir.mkdir()
        tool_script = spaced_dir / "my_tool.py"
        tool_script.write_text("import json, sys; print(json.dumps(sys.argv[1:]))\n")

        ctx = MockBuildContext(self.temp_path)
        ctx.tools_dir = tools_dir
        ctx.env_dir = env_dir
        ctx.path_tools = [{"name": "my-tool", "path": tool_script}]

        setup_path_tools(ctx)
        wrapper = tools_dir / "my-tool"
        self.assertTrue(wrapper.exists())
        self.assertFalse((tools_dir / "my-tool.py").exists())
        out = subprocess.check_output([str(wrapper), "a b", "", "*.txt"], text=True)
        self.assertEqual(json.loads(out), ["a b", "", "*.txt"])

    def test_setup_path_tools_preserves_bazel_runfiles_binary(self):
        tools_dir = self.temp_path / "tools"
        env_dir = self.temp_path / "venv"
        (env_dir / "bin").mkdir(parents=True)
        # Deliberately poison venv python so hijacking would fail.
        venv_python = env_dir / "bin" / "python"
        venv_python.write_text("#!/bin/sh\necho HIJACKED >&2\nexit 99\n")
        venv_python.chmod(0o755)

        tool_dir = self.temp_path / "bin"
        tool_dir.mkdir()
        tool = tool_dir / "real_py_bin"
        tool.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "print(json.dumps({"
            "'argv0': sys.argv[0], "
            "'args': sys.argv[1:], "
            "'rf': os.environ.get('RUNFILES_DIR'), "
            "'sysconfig': os.environ.get('_PYTHON_SYSCONFIGDATA_NAME')"
            "}))\n"
        )
        tool.chmod(0o755)
        (tool_dir / "real_py_bin.runfiles").mkdir()

        ctx = MockBuildContext(self.temp_path)
        ctx.tools_dir = tools_dir
        ctx.env_dir = env_dir
        ctx.path_tools = [{"name": "renamed-tool", "path": tool}]

        setup_path_tools(ctx)
        wrapper = tools_dir / "renamed-tool"
        self.assertTrue(wrapper.exists())
        py_bin_dir = str(Path(sys.executable).parent)
        env = dict(
            os.environ,
            PATH=f"{py_bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
            RUNFILES_DIR="/stale/runfiles",
            _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata_pycross",
        )
        out = subprocess.check_output([str(wrapper), "x y"], env=env, text=True)
        data = json.loads(out)
        self.assertEqual(data["argv0"], str(tool.absolute()))
        self.assertEqual(data["args"], ["x y"])
        self.assertIsNone(data["rf"])
        self.assertIsNone(data["sysconfig"])

    def test_load_build_context_reproducibility_env_defaults(self):
        import json
        import os
        from unittest import mock

        from pycross.private.build.tools.utils.context import load_build_context

        cfg = self.temp_path / "cfg.json"
        base = {
            "sdist": "pkg.tar.gz",
            "exec_python": "/usr/bin/python3",
            "target_python": "/usr/bin/python3",
            "wheel_dir": "out",
        }
        cfg.write_text(json.dumps(base))
        env = {"PYCROSS_BUILD_ROOT": str(self.temp_path / "root"), "PYCROSS_SDIST_DIR": str(self.temp_path / "sdist")}
        with mock.patch.dict(os.environ, env, clear=True):
            ctx = load_build_context(str(cfg))
        self.assertEqual(ctx.build_env["SOURCE_DATE_EPOCH"], "315532800")
        self.assertEqual(ctx.build_env["PYTHONHASHSEED"], "0")

        cfg.write_text(json.dumps({**base, "build_env": {"SOURCE_DATE_EPOCH": "1700000000", "PYTHONHASHSEED": "42"}}))
        with mock.patch.dict(os.environ, env, clear=True):
            ctx = load_build_context(str(cfg))
        self.assertEqual(ctx.build_env["SOURCE_DATE_EPOCH"], "1700000000")
        self.assertEqual(ctx.build_env["PYTHONHASHSEED"], "42")


if __name__ == "__main__":
    unittest.main()
