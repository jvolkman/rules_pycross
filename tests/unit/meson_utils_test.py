import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.meson_utils import generate_cross_ini


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.sysconfig_vars = {}
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


class MesonUtilsTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.ctx = MockBuildContext(self.temp_path)

        # Set some variables that generate_cross_ini needs
        self.ctx.sysconfig_vars["CC"] = "/usr/bin/gcc"
        self.ctx.sysconfig_vars["CXX"] = "/usr/bin/g++"
        self.ctx.sysconfig_vars["CFLAGS"] = "-O2 -fPIC"
        self.ctx.sysconfig_vars["CXXFLAGS"] = "-O2 -fPIC -std=c++14"
        self.ctx.sysconfig_vars["LDFLAGS"] = "-Wl,-O1"

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

        self.assertIn("[properties]", content)
        self.assertIn("needs_exe_wrapper = false", content)

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


if __name__ == "__main__":
    unittest.main()
