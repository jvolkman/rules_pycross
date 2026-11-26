import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from pycross.private.build.tools.cmake_builder import generate_toolchain_file
from pycross.private.build.tools.utils.cc_toolchain import setup_cc_layer
from pycross.private.build.tools.utils.context import CcLayerState


class CmakeBuilderTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def _ctx(self, cc_layer=None):
        return SimpleNamespace(
            prefix=self.temp_path,
            temp_dir=self.temp_path,
            sysconfig_vars={},
            build_env={},
            cc_layer=cc_layer,
        )

    def test_darwin_aarch64_flags_init_escaping_and_search_paths(self):
        native_inc = (self.temp_path / "native_inc").absolute()
        layer_lib = (self.temp_path / "cc_layer" / "lib").absolute()
        ctx = self._ctx(
            CcLayerState(
                cc_path=Path("C:\\tools\\clang;cc.exe"),
                cxx_path=Path("C:\\tools\\clang++;cxx.exe"),
                cflags=["-nostdlibinc", "-O2"],
                cxxflags=["-nostdlibinc", "-O2", "-std=c++17"],
                ldflags=["-L/some/lib"],
                ldsharedflags=[],
                ar_list=[],
                arflags=[],
                ranlib_path=None,
                include_dirs=[native_inc],
                layer_lib_dir=layer_lib,
                runtime_libs=[],
            )
        )
        cc_config = {
            "target_os": "darwin",
            "target_cpu": "aarch64",
        }

        generate_toolchain_file(ctx, cc_config)

        toolchain_path = self.temp_path / "cc_layer" / "CMakeToolchain.txt"
        content = toolchain_path.read_text()

        self.assertIn("set(CMAKE_SYSTEM_NAME Darwin)", content)
        self.assertIn("set(CMAKE_SYSTEM_PROCESSOR arm64)", content)
        self.assertIn(r'set(CMAKE_C_COMPILER "C:\\tools\\clang\;cc.exe")', content)
        self.assertIn(r'set(CMAKE_CXX_COMPILER "C:\\tools\\clang++\;cxx.exe")', content)

        # Uses *_INIT rather than CACHE ... FORCE.
        self.assertIn('set(CMAKE_C_FLAGS_INIT "-nostdlibinc -O2")', content)
        self.assertIn('set(CMAKE_CXX_FLAGS_INIT "-nostdlibinc -O2 -std=c++17")', content)
        self.assertIn('set(CMAKE_EXE_LINKER_FLAGS_INIT "-L/some/lib")', content)
        self.assertIn('set(CMAKE_SHARED_LINKER_FLAGS_INIT "-L/some/lib")', content)
        self.assertIn('set(CMAKE_MODULE_LINKER_FLAGS_INIT "-L/some/lib")', content)
        self.assertNotIn("set(CMAKE_C_FLAGS ", content)

        # Populates library and filtered include search paths.
        self.assertIn(f'list(PREPEND CMAKE_LIBRARY_PATH "{layer_lib.as_posix()}")', content)
        self.assertIn(f'list(PREPEND CMAKE_INCLUDE_PATH "{native_inc.as_posix()}")', content)
        self.assertNotIn("cc_layer/include", content)
        self.assertNotIn("libcxx", content)

    def test_setup_cc_layer_integration_filters_libcxx(self):
        native_inc = (self.temp_path / "native_inc").absolute()
        libcxx_inc = (self.temp_path / "libcxx" / "include").absolute()
        ctx = self._ctx()
        cc_config = {
            "CC": "/usr/bin/clang",
            "CXX": "/usr/bin/clang++",
            "CFLAGS": ["-nostdlibinc", "-O2"],
            "CXXFLAGS": ["-nostdlibinc", "-O2", "-std=c++17"],
            "LDFLAGS": [],
            "LDSHAREDFLAGS": ["-shared"],
            "AR": "/usr/bin/ar",
            "ARFLAGS": ["rcs"],
            "target_os": "darwin",
            "target_cpu": "aarch64",
            "include_dirs": [str(native_inc), str(libcxx_inc)],
        }

        setup_cc_layer(ctx, cc_config)
        generate_toolchain_file(ctx, cc_config)

        content = (self.temp_path / "cc_layer" / "CMakeToolchain.txt").read_text()
        self.assertIn(f'list(PREPEND CMAKE_INCLUDE_PATH "{native_inc.as_posix()}")', content)
        self.assertNotIn("libcxx", content)


if __name__ == "__main__":
    unittest.main()
