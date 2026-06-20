import argparse
import glob
import os
import subprocess
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a wheel transform tool with proper staging and collection.")
    parser.add_argument("--in-wheel-dir", help="Path to the input wheel directory.")
    parser.add_argument(
        "--out-wheel-dir", required=True, help="Directory where the transform tool writes the output wheel."
    )
    parser.add_argument("--tool", required=True, help="Path to the user's transform tool executable.")
    parser.add_argument(
        "--env", action="append", default=[], help="Extra environment variable in KEY=VALUE format (can be repeated)."
    )

    args = parser.parse_args()

    # Determine the wheel file for the transform tool.
    if args.in_wheel_dir:
        whl_files = glob.glob(os.path.join(args.in_wheel_dir, "*.whl"))
        if not whl_files:
            print("ERROR: No .whl file found in wheel directory: " + args.in_wheel_dir, file=sys.stderr)
            sys.exit(1)
        wheel_file = whl_files[0]
    else:
        print("ERROR: --in-wheel-dir is required", file=sys.stderr)
        sys.exit(1)

    # Build the environment for the transform tool.
    from pycross.private.build.tools.utils.env import make_clean_env

    env = make_clean_env()
    env["PYCROSS_WHEEL_FILE"] = wheel_file
    # The transform tool should write its output to args.out_wheel_dir
    os.makedirs(args.out_wheel_dir, exist_ok=True)
    env["PYCROSS_WHEEL_OUTPUT_ROOT"] = args.out_wheel_dir

    for env_entry in args.env:
        key, _, value = env_entry.partition("=")
        if key:
            env[key] = value

    # Run the user's transform tool.
    subprocess.check_call([args.tool], env=env)

    # Collect output: find the transformed wheel in the output directory.
    output_dir = Path(args.out_wheel_dir)
    whl_files = sorted(output_dir.glob("*.whl"))
    if not whl_files:
        print("ERROR: No .whl file found in transform output", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
