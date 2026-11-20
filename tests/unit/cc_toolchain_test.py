import json
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

from pycross.private.build.tools.utils.cc_toolchain import get_wrapper_flags
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
        self.assertNotIn("import os", content)

        self.assertIn("-target x86_64-linux-gnu --sysroot=/tmp/sysroot", content)
        self.assertIn("-fuse-ld=lld -B/tmp/crt -L/tmp/glibc -lpthread", content)

        self.assertIn("-Wl,--start-group", content)
        self.assertIn("-Wl,--end-group", content)
        self.assertIn("-Wl,--as-needed", content)

    def test_get_wrapper_flags_trailing_flag(self):
        self.assertEqual(get_wrapper_flags("-O2 -target"), [])
        self.assertEqual(get_wrapper_flags("-O2 --sysroot=/tmp/s -isysroot"), ["--sysroot=/tmp/s"])

    def test_wrap_compiler_link_vs_non_link_invocations(self):
        bin_dir = self.temp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake_cc = self._make_fake_cc()

        cflags = "-O2 -target x86_64-linux-gnu --sysroot=/dev/null"
        ldflags = "-fuse-ld=lld -B/tmp/crt -L/tmp/glibc -Wl,-rpath,$ORIGIN -Wl,--as-needed -Wl,-O1 -lpthread"
        wrapper = wrap_compiler("cc", str(fake_cc), cflags, Path(sys.executable), bin_dir, ldflags=ldflags)

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

        wrapper = wrap_compiler("cc", str(fake_cc), "-O2", Path(sys.executable), bin_dir, ldflags="-lpthread")
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

    def test_setup_cc_layer_exports_no_toolchain_ldflags(self):
        ctx = MockBuildContext(self.temp_path)
        fake_cc = self._make_fake_cc()
        cc_config = {
            "CC": str(fake_cc),
            "CXX": str(fake_cc),
            "CFLAGS": "-O2",
            "CXXFLAGS": "-O2",
            # Like hermetic-llvm 0.8.24 on glibc.
            "LDFLAGS": "-fuse-ld=lld -no-pie -Wl,-S",
            "LDSHAREDFLAGS": "-fuse-ld=lld -shared -Wl,-S",
            "AR": "/usr/bin/ar",
            "ARFLAGS": "rcs",
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
        self.assertEqual(
            run_wrapper(*ldshared, *shlex.split(ctx.sysconfig_vars["LDFLAGS"]), "a.o", "-o", "a.so"),
            ["-shared", f"-L{layer_lib}", "a.o", "-o", "a.so", "-fuse-ld=lld", "-Wl,-S"],
        )
        # Executable links get the executable set, including -no-pie.
        self.assertEqual(run_wrapper("a.o", "-o", "a"), ["a.o", "-o", "a", "-fuse-ld=lld", "-no-pie", "-Wl,-S"])

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
        sdist_dir = execroot / "source"
        sdist_dir.mkdir()
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
            "CFLAGS": "-nologo",
            "CXXFLAGS": "-nologo -std:c++17",
            "LDFLAGS": "",
            "LDSHAREDFLAGS": "",
            "AR": str(tool_dir / "lib.exe"),
            "ARFLAGS": "",
            "include_dirs": ["$$EXT_BUILD_ROOT$$/dep include"],
            "msvc_env": {
                "PATH": "external/MSVC tools/bin;$$EXT_BUILD_ROOT$$/SDK bin;$PATH",
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
            self.assertEqual(ctx.temp_dir, execroot / "scratch")
            self.assertEqual(ctx.sdist_root_dir, execroot / "source")
            with chdir(sdist_dir):
                setup_cc_layer(ctx, cc_config)

        self.assertEqual(
            [Path(path) for path in ctx.build_env["PATH"].split(";")],
            [tool_dir, execroot / "SDK bin", user_tool_dir],
        )
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
            [ctx.temp_dir / "cc_layer" / "include", execroot / "dep include"],
        )
        self.assertEqual(ctx.build_env["DISTUTILS_USE_SDK"], "1")
        for key in ("Path", "Include", "Lib"):
            self.assertNotIn(key, ctx.build_env)
        search_path = ctx.build_env["PATH"].replace(";", os.pathsep)
        for tool in ("cl.exe", "link.exe"):
            self.assertEqual(Path(shutil.which(tool, path=search_path)), tool_dir / tool)

    def test_setup_cc_layer_expands_leading_msvc_path_without_wrappers(self):
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
            "CFLAGS": "",
            "CXXFLAGS": "",
            "LDFLAGS": "",
            "LDSHAREDFLAGS": "",
            "AR": "lib.exe",
            "ARFLAGS": "",
            "msvc_env": {"PATH": "$PATH;sdk tools", "INCLUDE": "", "LIB": ""},
        }
        with patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os:
            cc_os.name = "nt"
            cc_os.pathsep = ";"
            setup_cc_layer(ctx, cc_config)

        paths = ctx.build_env["PATH"].split(";")
        self.assertEqual(paths[0], str(user_tools))
        self.assertEqual(paths[1], str(execroot / "sdk tools"))
        self.assertNotIn(str(ctx.temp_dir / "cc_layer" / "bin"), paths)
        self.assertEqual(Path(shutil.which("cl.exe", path=os.pathsep.join(paths))), user_tools / "cl.exe")
        self.assertEqual(ctx.build_env["DISTUTILS_USE_SDK"], "1")

    def test_incomplete_msvc_environment_does_not_enable_sdk(self):
        for msvc_env in (
            {},
            {"PATH": "", "INCLUDE": "", "LIB": ""},
            {"PATH": "prepared"},
            {"INCLUDE": "headers", "LIB": "libraries"},
        ):
            with self.subTest(msvc_env=msvc_env):
                ctx = MockBuildContext(self.temp_path)
                cc_config = {
                    "CC": "/usr/bin/cc",
                    "CXX": "/usr/bin/c++",
                    "CFLAGS": "",
                    "CXXFLAGS": "",
                    "LDFLAGS": "",
                    "LDSHAREDFLAGS": "",
                    "AR": "ar",
                    "ARFLAGS": "",
                    "msvc_env": msvc_env,
                }
                with patch("pycross.private.build.tools.utils.cc_toolchain.os", wraps=os) as cc_os:
                    cc_os.name = "nt"
                    cc_os.pathsep = ";"
                    setup_cc_layer(ctx, cc_config)
                for key, value in msvc_env.items():
                    expected = str(self.temp_path / value) if value else ""
                    self.assertEqual(ctx.build_env[key], expected)
                self.assertNotIn("DISTUTILS_USE_SDK", ctx.build_env)

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
            "CFLAGS": "",
            "CXXFLAGS": "",
            "LDFLAGS": "",
            "LDSHAREDFLAGS": "-shared",
            "AR": "/usr/bin/ar",
            "ARFLAGS": "rcs",
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
        # Toolchain link flags come from the wrapper, not LDSHARED.
        self.assertNotIn("-Wl,-O1", ldshared)
        self.assertNotIn("-shared", ldshared)
        self.assertEqual(ldshared[-3:], ["-bundle", "-undefined", "dynamic_lookup"])
        self.assertTrue(ctx.sysconfig_vars["LDSHARED"].startswith(ctx.sysconfig_vars["CC"]))
        self.assertTrue(ctx.sysconfig_vars["LDCXXSHARED"].startswith(ctx.sysconfig_vars["CXX"]))
        self.assertEqual(ctx.sysconfig_vars["LDCXXSHARED"].split()[-3:], ["-bundle", "-undefined", "dynamic_lookup"])

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
