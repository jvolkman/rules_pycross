import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any
from typing import Dict

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import replace_placeholder


def run_pre_build_hook(ctx: BuildContext, hook_config: Dict[str, Any]) -> None:
    """Execute a pre-build hook inside the build sandbox.

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


def run_pre_build_hooks_from_config(ctx: BuildContext) -> None:
    """Run pre-build hooks specified directly in the build config."""
    hook_paths = ctx.bazel_config.get("pre_build_hooks", [])
    for hook_path in hook_paths:
        run_pre_build_hook(ctx, {"executable": hook_path})


def run_post_build_hooks(ctx: BuildContext, wheel_file: Path) -> Path:
    """Run post-build hooks after the wheel is built.

    Each hook receives PYCROSS_WHEEL_FILE pointing to the current wheel.
    The hook may modify the wheel in place or write a new wheel to
    PYCROSS_WHEEL_OUTPUT_DIR.

    Returns the final wheel file path.
    """
    hook_paths = ctx.bazel_config.get("post_build_hooks", [])
    wheel_file = Path(wheel_file)
    if not hook_paths:
        return wheel_file

    wheel_staging = ctx.temp_dir / "post_wheel_staging"
    wheel_output = ctx.temp_dir / "post_wheel_output"

    for hook_path in hook_paths:
        hook_exe = (ctx.prefix / Path(hook_path)).absolute()

        # Set up staging directories
        wheel_staging.mkdir(parents=True, exist_ok=True)
        wheel_output.mkdir(parents=True, exist_ok=True)

        # Move wheel to staging for the hook to process
        staged_wheel = wheel_staging / wheel_file.name
        shutil.move(str(wheel_file), str(staged_wheel))

        hook_env = dict(ctx.build_env)
        hook_env["PYCROSS_BAZEL_ROOT"] = str(ctx.prefix)
        hook_env["PYCROSS_WHEEL_FILE"] = str(staged_wheel)
        hook_env["PYCROSS_WHEEL_OUTPUT_DIR"] = str(wheel_output)

        try:
            subprocess.check_output(
                args=[str(hook_exe)],
                env=hook_env,
                cwd=str(ctx.sdist_dir),
                stderr=subprocess.STDOUT,
            )
        except subprocess.CalledProcessError as cpe:
            print("===== POST-BUILD HOOK FAILED =====", file=sys.stderr)
            if cpe.output:
                print(cpe.output.decode("utf-8", "replace"), file=sys.stderr)
            raise

        # Check for output wheel
        output_wheels = list(wheel_output.glob("*.whl"))
        if output_wheels:
            wheel_file = output_wheels[0]
        else:
            # Hook modified in place
            wheel_file = staged_wheel

        # Clean up staging for next iteration (output kept — wheel_file may point there)
        shutil.rmtree(str(wheel_staging), ignore_errors=True)

    # Move final wheel back to ctx.wheel_dir
    final_dest = ctx.wheel_dir / wheel_file.name
    if final_dest.exists():
        final_dest.unlink()
    shutil.move(str(wheel_file), str(final_dest))

    # Clean up output dir
    shutil.rmtree(str(wheel_output), ignore_errors=True)

    return final_dest
