import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.meson_utils import generate_cross_ini
from pycross.private.build.tools.utils.cc_toolchain import setup_cc_layer
from pycross.private.build.tools.utils.context import CcLayerState


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.sysconfig_vars = {}
        self.build_env = {}
        self.prefix = temp_dir
        self.temp_dir = temp_dir
        self.sdist_dir = temp_dir / "sdist"
        self.sdist_dir.mkdir()
        self.env_dir = temp_dir / "env"
        self.tools_dir = temp_dir / "tools"

        self.exec_python = self.env_dir / "bin" / "python"
        self.target_python = self.env_dir / "bin" / "python"
        self.pkg_config_files = []
        self.config_settings = {}
        self.cc_layer = None


class MesonUtilsTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.ctx = MockBuildContext(self.temp_path)

        self.ctx.cc_layer = CcLayerState(
            cc_path=Path("/usr/bin/gcc"),
            cxx_path=Path("/usr/bin/g++"),
            cflags=["-O2", "-fPIC"],
            cxxflags=["-O2", "-fPIC", "-std=c++14"],
            ldflags=["-Wl,-O1"],
            ldsharedflags=[],
            ar_list=[],
            arflags=[],
            ranlib_path=None,
            include_dirs=[],
            layer_lib_dir=(self.temp_path / "cc_layer" / "lib").absolute(),
            runtime_libs=[],
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_generate_cross_ini_native(self):
        cc_config = {"target_os": "linux", "target_cpu": "x86_64"}
        generate_cross_ini(self.ctx, cc_config)

        cross_ini_path = self.temp_path / "cc_layer" / "cross.ini"
        self.assertTrue(cross_ini_path.exists())

        content = cross_ini_path.read_text()

        self.assertIn("[host_machine]", content)
        self.assertIn("system = 'linux'", content)
        self.assertIn("cpu_family = 'x86_64'", content)

        self.assertIn("[binaries]", content)
        self.assertIn("c = ['/usr/bin/gcc']", content)
        self.assertIn("cpp = ['/usr/bin/g++']", content)

        self.assertIn("[built-in options]", content)
        self.assertIn("c_args = ['-O2', '-fPIC']", content)
        self.assertIn("c_link_args = ['-Wl,-O1']", content)

        # Even for native builds, default is needs_exe_wrapper=true for reproducibility
        self.assertIn("[properties]", content)
        self.assertIn("needs_exe_wrapper = true", content)
        self.assertIn("skip_sanity_check = true", content)

    def test_generate_cross_ini_cross(self):
        # Make it a cross build by having target_python != exec_python
        self.ctx.target_python = self.temp_path / "target_env" / "bin" / "python"

        cc_config = {"target_os": "linux", "target_cpu": "aarch64"}
        generate_cross_ini(self.ctx, cc_config)

        cross_ini_path = self.temp_path / "cc_layer" / "cross.ini"
        content = cross_ini_path.read_text()

        self.assertIn("system = 'linux'", content)
        self.assertIn("cpu_family = 'aarch64'", content)
        self.assertIn("needs_exe_wrapper = true", content)

    def test_generate_cross_ini_allow_native_exec(self):
        # With allow_native_exec, native builds should get needs_exe_wrapper=false
        cc_config = {"target_os": "linux", "target_cpu": "x86_64"}
        meson_config = {"meson_properties": {}, "allow_native_exec": True}
        generate_cross_ini(self.ctx, cc_config, meson_config)

        cross_ini_path = self.temp_path / "cc_layer" / "cross.ini"
        content = cross_ini_path.read_text()

        self.assertIn("needs_exe_wrapper = false", content)
        self.assertIn("skip_sanity_check = false", content)

    def test_generate_cross_ini_allow_native_exec_cross(self):
        # With allow_native_exec but cross-compiling, should still be true
        self.ctx.target_python = self.temp_path / "target_env" / "bin" / "python"

        cc_config = {"target_os": "linux", "target_cpu": "aarch64"}
        meson_config = {"meson_properties": {}, "allow_native_exec": True}
        generate_cross_ini(self.ctx, cc_config, meson_config)

        cross_ini_path = self.temp_path / "cc_layer" / "cross.ini"
        content = cross_ini_path.read_text()

        self.assertIn("needs_exe_wrapper = true", content)
        self.assertIn("skip_sanity_check = true", content)

    def test_generate_cross_ini_quoted_flags(self):
        # Meson drops literal double quotes inside tokens, since projects like
        # numpy embed c_args in generated Python sources.
        self.ctx.cc_layer.cflags = ["-O2", '-D__DATE__="redacted"']
        cc_config = {"target_os": "linux", "target_cpu": "x86_64"}
        generate_cross_ini(self.ctx, cc_config)

        content = (self.temp_path / "cc_layer" / "cross.ini").read_text()
        self.assertIn("c_args = ['-O2', '-D__DATE__=redacted']", content)

    def test_generate_cross_ini_omits_build_machine(self):
        # Meson detects the build machine itself; the cross file only
        # describes the target.
        self.ctx.target_python = self.temp_path / "target_env" / "bin" / "python"
        cc_config = {"target_os": "darwin", "target_cpu": "aarch64"}
        generate_cross_ini(self.ctx, cc_config)

        content = (self.temp_path / "cc_layer" / "cross.ini").read_text()
        self.assertIn("[host_machine]", content)
        self.assertNotIn("[build_machine]", content)

    def test_generate_cross_ini_runtime_libs_not_duplicated(self):
        # setup_cc_layer already appends runtime_libs to cc_layer.ldflags.
        self.ctx.cc_layer.ldflags = ["-Wl,-O1", "/abs/libc++.a"]
        cc_config = {
            "target_os": "linux",
            "target_cpu": "x86_64",
            "runtime_libs": ["/abs/libc++.a"],
        }
        generate_cross_ini(self.ctx, cc_config)

        content = (self.temp_path / "cc_layer" / "cross.ini").read_text()
        self.assertIn("c_link_args = ['-Wl,-O1', '/abs/libc++.a']", content)

    def test_generate_cross_ini_longdouble_format(self):
        cases = [
            ("darwin", "x86_64", "INTEL_EXTENDED_16_BYTES_LE"),
            ("darwin", "aarch64", "IEEE_DOUBLE_LE"),
            ("linux", "x86_64", "INTEL_EXTENDED_16_BYTES_LE"),
            ("linux", "aarch64", "IEEE_QUAD_LE"),
            ("linux", "arm", "IEEE_DOUBLE_LE"),
            ("linux", "x86", "INTEL_EXTENDED_12_BYTES_LE"),
            ("windows", "x86_64", "IEEE_DOUBLE_LE"),
        ]
        for target_os, target_cpu, expected in cases:
            with self.subTest(target_os=target_os, target_cpu=target_cpu):
                generate_cross_ini(self.ctx, {"target_os": target_os, "target_cpu": target_cpu})
                content = (self.temp_path / "cc_layer" / "cross.ini").read_text()
                self.assertIn(f"longdouble_format = '{expected}'", content)

    def test_generate_cross_ini_filters_and_dedups_include_dirs(self):
        native_inc = (self.temp_path / "native_inc").absolute()
        libcxx_inc = (self.temp_path / "libcxx" / "include").absolute()
        extra_inc = (self.temp_path / "extra_inc").absolute()
        cc_config = {
            "CC": "/usr/bin/gcc",
            "CXX": "/usr/bin/g++",
            "CFLAGS": ["-nostdlibinc", f"-I{native_inc}"],
            "CXXFLAGS": ["-nostdlibinc", f"-I{native_inc}"],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": ["-shared"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
            "target_os": "linux",
            "target_cpu": "x86_64",
            "include_dirs": [str(native_inc), str(libcxx_inc), str(extra_inc)],
        }
        setup_cc_layer(self.ctx, cc_config)
        generate_cross_ini(self.ctx, cc_config)

        content = (self.temp_path / "cc_layer" / "cross.ini").read_text()
        self.assertNotIn("-isystem", content)
        self.assertNotIn("libcxx", content)
        self.assertEqual(content.count(f"-I{native_inc}"), 2)  # once in c_args, once in cpp_args
        self.assertEqual(content.count(f"-I{extra_inc}"), 2)

    def test_generate_cross_ini_preserves_spaces_escapes_and_build_dir(self):
        self.ctx.cc_layer.cflags = ["-I/path/with spaces/inc", '-DNAME="o\'reilly\\x"']
        self.ctx.config_settings["build-dir"] = "custom_build"
        pc_file = self.temp_path / "demo.pc"
        pc_file.write_text("prefix=$$EXT_BUILD_ROOT$$/demo\n")
        self.ctx.pkg_config_files = [pc_file]

        cc_config = {
            "target_os": "linux",
            "target_cpu": "x86_64",
        }
        meson_config = {
            "meson_properties": {"custom_prop": "a'b\\c", "_internal": "ignored"},
            "allow_native_exec": False,
        }
        generate_cross_ini(self.ctx, cc_config, meson_config)

        content = (self.temp_path / "cc_layer" / "cross.ini").read_text()
        self.assertIn("'-I/path/with spaces/inc'", content)
        self.assertIn("'-DNAME=o\\'reilly\\\\x'", content)
        self.assertIn("custom_prop = 'a\\'b\\\\c'", content)
        self.assertNotIn("_internal", content)
        self.assertEqual(self.ctx.config_settings["build-dir"], "custom_build")
        self.assertTrue((self.temp_path / "pkgconfig" / "demo.pc").exists())
        self.assertFalse((self.ctx.sdist_dir / "pkgconfig").exists())


if __name__ == "__main__":
    unittest.main()
