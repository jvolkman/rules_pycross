import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.utils.hooks import run_pre_build_hook


class MockBuildContext:
    def __init__(self, temp_dir: Path):
        self.prefix = temp_dir
        self.temp_dir = temp_dir
        self.sdist_dir = temp_dir / "sdist"
        self.sdist_dir.mkdir()
        self.config_settings = {"initial": "value"}
        self.build_env = {"MY_ENV": "1"}


class HooksTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_run_pre_build_hook_success(self):
        ctx = MockBuildContext(self.temp_path)

        hook_exe = self.temp_path / "hook.sh"
        with open(hook_exe, "w") as f:
            f.write("""#!/bin/sh
            echo '{"modified": "yes"}' > "$PYCROSS_CONFIG_SETTINGS_FILE"
            """)
        hook_exe.chmod(0o755)

        hook_config = {"executable": "hook.sh"}
        run_pre_build_hook(ctx, hook_config)

        self.assertIn("modified", ctx.config_settings)
        self.assertEqual(ctx.config_settings["modified"], "yes")

    def test_run_pre_build_hook_failure(self):
        ctx = MockBuildContext(self.temp_path)

        hook_exe = self.temp_path / "hook.sh"
        with open(hook_exe, "w") as f:
            f.write("""#!/bin/sh
            exit 1
            """)
        hook_exe.chmod(0o755)

        hook_config = {"executable": "hook.sh"}
        with self.assertRaises(subprocess.CalledProcessError):
            run_pre_build_hook(ctx, hook_config)


if __name__ == "__main__":
    unittest.main()
