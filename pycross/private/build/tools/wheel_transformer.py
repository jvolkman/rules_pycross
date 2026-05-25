import argparse
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a wheel transform tool with proper staging and collection.")
    parser.add_argument("--wheel-file", required=True, help="Path to the input wheel file.")
    parser.add_argument("--wheel-name-file", help="Path to .whl.name file containing the real wheel name.")
    parser.add_argument("--wheel-directory", help="Path to a directory containing the wheel under its proper name.")
    parser.add_argument("--staging-dir", help="Directory to stage the wheel in before transform.")
    parser.add_argument(
        "--output-dir", required=True, help="Directory where the transform tool writes the output wheel."
    )
    parser.add_argument("--out-wheel-file", required=True, help="Path where the output symlink should be created.")
    parser.add_argument(
        "--out-wheel-name-file", required=True, help="Path where the output wheel name should be written."
    )
    parser.add_argument(
        "--out-wheel-dir-basename", required=True, help="Basename of the output wheel directory (for relative symlink)."
    )
    parser.add_argument("--tool", required=True, help="Path to the user's transform tool executable.")
    parser.add_argument(
        "--env", action="append", default=[], help="Extra environment variable in KEY=VALUE format (can be repeated)."
    )

    args = parser.parse_args()

    # Determine the wheel file for the transform tool.
    if args.wheel_directory:
        # When input is a directory, find the .whl inside it.
        whl_files = glob.glob(os.path.join(args.wheel_directory, "*.whl"))
        if not whl_files:
            print("ERROR: No .whl file found in wheel directory: " + args.wheel_directory, file=sys.stderr)
            sys.exit(1)
        wheel_file = whl_files[0]
    elif args.wheel_name_file:
        # Stage the wheel under its real name so the tool can parse the filename.
        with open(args.wheel_name_file, "r") as f:
            real_name = f.read().strip()
        os.makedirs(args.staging_dir, exist_ok=True)
        wheel_file = os.path.join(args.staging_dir, real_name)
        shutil.copy2(args.wheel_file, wheel_file)
    else:
        # No name file; stage with the original basename.
        os.makedirs(args.staging_dir, exist_ok=True)
        basename = os.path.basename(args.wheel_file)
        wheel_file = os.path.join(args.staging_dir, basename)
        shutil.copy2(args.wheel_file, wheel_file)

    # Build the environment for the transform tool.
    env = os.environ.copy()
    env["PYCROSS_WHEEL_FILE"] = wheel_file
    env["PYCROSS_WHEEL_OUTPUT_ROOT"] = args.output_dir

    for env_entry in args.env:
        key, _, value = env_entry.partition("=")
        if key:
            env[key] = value

    # Run the user's transform tool.
    subprocess.check_call([args.tool], env=env)

    # Collect output: find the transformed wheel in the output directory.
    output_dir = Path(args.output_dir)
    whl_files = sorted(output_dir.glob("*.whl"))
    if not whl_files:
        print("ERROR: No .whl file found in transform output", file=sys.stderr)
        sys.exit(1)
    transformed_wheel = whl_files[0]

    # Create a relative symlink from out_wheel_file -> <out_wheel_dir_basename>/<wheel_name>.
    symlink_target = os.path.join(args.out_wheel_dir_basename, transformed_wheel.name)
    os.symlink(symlink_target, args.out_wheel_file)

    # Write the wheel basename to the name file.
    with open(args.out_wheel_name_file, "w") as f:
        f.write(transformed_wheel.name)


if __name__ == "__main__":
    main()
