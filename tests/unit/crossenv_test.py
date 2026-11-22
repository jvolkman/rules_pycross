import importlib.machinery
import subprocess
import sys
import sysconfig
import unittest
from unittest.mock import patch

from pycross.private.build.tools.crossenv import determine_glibc_version
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


class DetermineGlibcVersionTest(unittest.TestCase):
    def test_uses_c_source_and_fsyntax_only(self):
        captured = {}

        def fake_check_output(cmd, **kwargs):
            captured["cmd"] = cmd
            return b"note: #pragma message: GLIBC=2.39\n"

        with (
            patch("pycross.private.build.tools.crossenv.shutil.which", return_value="/usr/bin/cc"),
            patch("pycross.private.build.tools.crossenv.subprocess.check_output", side_effect=fake_check_output),
        ):
            version = determine_glibc_version({"CC": "/usr/bin/cc", "CFLAGS": "-O2"})

        self.assertEqual(version, "2.39")
        self.assertIn("-fsyntax-only", captured["cmd"])
        self.assertNotIn("-c", captured["cmd"])
        self.assertTrue(captured["cmd"][-1].endswith("teller.c"))

    def test_returns_none_on_compiler_error(self):
        with (
            patch("pycross.private.build.tools.crossenv.shutil.which", return_value="/usr/bin/cc"),
            patch(
                "pycross.private.build.tools.crossenv.subprocess.check_output",
                side_effect=subprocess.CalledProcessError(1, ["cc"]),
            ),
        ):
            self.assertIsNone(determine_glibc_version({"CC": "/usr/bin/cc"}))


class SysPatchTest(unittest.TestCase):
    def test_sys_patch_uses_getframe_for_caller_platform(self):
        import pkgutil
        import types

        from pycross.private.build.tools.crossenv.utils import TemplateContext

        tmpl = TemplateContext()
        tmpl.update(
            {
                "lib_path": "/mock/lib",
                "exec_stdlib": "/mock/stdlib",
                "target": types.SimpleNamespace(abiflags=None, multiarch=None, uname_sysname="Darwin"),
            }
        )
        raw = pkgutil.get_data("pycross.private.build.tools.crossenv", "scripts/sys-patch.py.tmpl")
        assert raw is not None
        src = tmpl.expand(raw.decode("utf-8"))

        depths = []

        def fake_getframe(depth):
            depths.append(depth)
            if current_filename is None:
                raise ValueError("call stack is not deep enough")
            return types.SimpleNamespace(f_code=types.SimpleNamespace(co_filename=current_filename))

        fake_sys = {
            "implementation": types.SimpleNamespace(_multiarch="x86_64-linux-gnu"),
            "path": ["/mock/lib", "/mock/stdlib"],
            "platform": "linux",
            "_getframe": fake_getframe,
        }
        exec(src, fake_sys, fake_sys)
        getter = fake_sys["__getattr__"]

        for current_filename, expected in [
            ("<frozen importlib._bootstrap>", "linux"),
            ("/usr/lib/python3/distutils/sysconfig.py", "darwin"),
            ("setup.py", "darwin"),
            ("/usr/lib/python3/site-packages/pkg.py", "linux"),
            (None, "linux"),
        ]:
            self.assertEqual(getter("platform"), expected, msg=current_filename)

        self.assertEqual(depths, [1, 1, 1, 1, 1])

        with self.assertRaises(AttributeError):
            getter("not_platform")


if __name__ == "__main__":
    unittest.main()
