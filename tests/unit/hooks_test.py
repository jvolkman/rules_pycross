import json
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from pycross.private.build.tools.utils import context
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

    def test_run_pre_build_hook_receives_consistent_scratch_paths(self):
        original_sdist_root = "bazel-out/config-a/bin/pkg/target/sdist"
        config_path = self.temp_path / "config.json"
        config_path.write_text(
            json.dumps(
                {
                    "sdist": "pkg.tar.gz",
                    "exec_python": "python",
                    "target_python": "python",
                    "wheel_dir": "wheels",
                    "source_dir": "project/src",
                    "build_env": {"PYTHONPATH": original_sdist_root + ";C:\\external\\dependency"},
                }
            )
        )
        action_env = os.environ.copy()
        action_env.update(
            {
                "PYCROSS_BUILD_ROOT": "very/long/bazel/output/build/root/_tmp",
                "PYCROSS_SDIST_DIR": original_sdist_root,
                "PYTHONPATH": original_sdist_root + ";C:\\launcher\\path",
            }
        )
        simulated_windows = SimpleNamespace(name="nt", environ=action_env, path=os.path, pathsep=";")
        with (
            patch.object(context, "os", simulated_windows),
            patch.object(context.Path, "cwd", return_value=self.temp_path),
        ):
            ctx = context.load_build_context(str(config_path))
        ctx.temp_dir.mkdir(parents=True)
        ctx.sdist_dir.mkdir(parents=True)
        output_file = self.temp_path / "hook-paths.txt"
        hook_exe = self.temp_path / ("hook.cmd" if os.name == "nt" else "hook.sh")
        if os.name == "nt":
            hook_exe.write_text(
                "@echo off\r\n"
                'echo %PYCROSS_SDIST_DIR%> "%PYCROSS_TEST_OUTPUT%"\r\n'
                'echo %PYCROSS_BUILD_ROOT%>> "%PYCROSS_TEST_OUTPUT%"\r\n'
                'cd >> "%PYCROSS_TEST_OUTPUT%"\r\n'
                'echo %PYTHONPATH%>> "%PYCROSS_TEST_OUTPUT%"\r\n'
            )
        else:
            hook_exe.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$PYCROSS_SDIST_DIR" "$PYCROSS_BUILD_ROOT" "$PWD" "$PYTHONPATH" '
                '> "$PYCROSS_TEST_OUTPUT"\n'
            )
            hook_exe.chmod(0o755)

        run_pre_build_hook(ctx, {"executable": hook_exe.name, "env": {"PYCROSS_TEST_OUTPUT": str(output_file)}})

        sdist_root, build_path, hook_cwd, pythonpath = output_file.read_text().splitlines()
        self.assertEqual(Path(sdist_root), ctx.sdist_root_dir)
        self.assertEqual(Path(build_path), ctx.temp_dir.absolute())
        self.assertEqual(Path(hook_cwd).resolve(), ctx.sdist_dir.resolve())
        self.assertEqual(
            pythonpath.split(";"),
            [str(ctx.sdist_root_dir), "C:\\external\\dependency"],
        )

    def test_run_pre_build_hook_deletes_env_var_with_null(self):
        ctx = MockBuildContext(self.temp_path)
        ctx.build_env = {"KEEP_ME": "1", "DELETE_ME": "yes"}

        hook_exe = self.temp_path / "hook.sh"
        hook_exe.write_text('#!/bin/sh\necho \'{"DELETE_ME": null, "ADDED": "2"}\' > "$PYCROSS_ENV_VARS_FILE"\n')
        hook_exe.chmod(0o755)

        run_pre_build_hook(ctx, {"executable": "hook.sh"})

        self.assertEqual(ctx.build_env, {"KEEP_ME": "1", "ADDED": "2"})


if __name__ == "__main__":
    unittest.main()
