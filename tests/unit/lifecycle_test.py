import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

        # Create minimal config JSON
        self.config_path = self.temp_path / "config.json"
        with open(self.config_path, "w") as f:
            json.dump(
                {
                    "sdist": "dummy_sdist.tar.gz",
                    "exec_python": "python3",
                    "target_python": "python3",
                    "wheel_file": "out.whl",
                    "wheel_name_file": "out.name",
                    "wheel_directory": "out_dir",
                    "layers": [],
                },
                f,
            )

        os.environ["PYCROSS_BUILD_ROOT"] = "build_root"
        os.environ["PYCROSS_SDIST_DIR"] = "sdist_dir"

    def tearDown(self):
        self.temp_dir.cleanup()
        os.environ.pop("PYCROSS_BUILD_ROOT", None)
        os.environ.pop("PYCROSS_SDIST_DIR", None)

    @patch("pycross.private.build.tools.utils.lifecycle.extract_sdist")
    @patch("pycross.private.build.tools.utils.lifecycle.os.chdir")
    @patch("pycross.private.build.tools.utils.lifecycle.setup_path_tools")
    @patch("pycross.private.build.tools.utils.lifecycle.apply_sysconfig_overrides")
    @patch("pycross.private.build.tools.utils.lifecycle.run_pep517_build")
    @patch("pycross.private.build.tools.utils.lifecycle.load_target_sysconfig")
    def test_lifecycle_ordering(
        self, mock_load_sysconfig, mock_pep517, mock_apply_sys, mock_setup_path, mock_chdir, mock_extract
    ):
        call_order = []

        def setup_toolchains(ctx):
            call_order.append("setup_toolchains")

        def setup_venv(ctx):
            call_order.append("setup_venv")

        def pre_build(ctx):
            call_order.append("pre_build")

        def prepare_env(ctx):
            call_order.append("prepare_env")

        strategy = BackendStrategy(
            setup_toolchains=setup_toolchains, setup_venv=setup_venv, pre_build=pre_build, prepare_env=prepare_env
        )

        run_standard_build_lifecycle(str(self.config_path), strategy)

        self.assertEqual(call_order, ["setup_toolchains", "setup_venv", "pre_build", "prepare_env"])


if __name__ == "__main__":
    unittest.main()
