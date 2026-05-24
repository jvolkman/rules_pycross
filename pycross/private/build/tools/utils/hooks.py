import json
import subprocess
import sys
from pathlib import Path
from typing import Any
from typing import Dict

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder


def run_pre_build_hook(ctx: BuildContext, hook_config: Dict[str, Any]) -> None:
    """Execute a pre-build hook mixin inside the build sandbox.

    The hook receives the current build environment and config settings
    via JSON files. It may mutate both by writing back to those files.
    """
    hook_exe = (ctx.prefix / Path(hook_config["executable"])).absolute()

    # Write current state files for the hook to read/modify
    config_settings_file = ctx.temp_dir / "config_settings.json"
    env_file = ctx.temp_dir / "build_env.json"

    with open(config_settings_file, "w") as f:
        json.dump(ctx.config_settings, f)
    with open(env_file, "w") as f:
        json.dump({k: v for k, v in ctx.build_env.items() if isinstance(v, str)}, f)

    hook_env = dict(ctx.build_env)
    hook_env["PYCROSS_BAZEL_ROOT"] = str(ctx.prefix)
    hook_env["PYCROSS_CONFIG_SETTINGS_FILE"] = str(config_settings_file)
    hook_env["PYCROSS_ENV_VARS_FILE"] = str(env_file)

    # Merge hook-specific env vars
    for key, value in hook_config.get("env", {}).items():
        hook_env[key] = replace_placeholder(ctx.prefix, value)

    try:
        subprocess.check_output(
            args=[str(hook_exe)],
            env=hook_env,
            cwd=str(ctx.sdist_dir),
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as cpe:
        print("===== PRE-BUILD HOOK FAILED =====", file=sys.stderr)
        if cpe.output:
            print(cpe.output.decode("utf-8", "replace"), file=sys.stderr)
        raise

    # Read back any mutations the hook made
    if env_file.exists():
        with open(env_file, "r") as f:
            updated_env = json.load(f)
            ctx.build_env.update(updated_env)

    if config_settings_file.exists():
        with open(config_settings_file, "r") as f:
            ctx.config_settings = json.load(f)
