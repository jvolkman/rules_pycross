import argparse
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Repair a Python wheel by bundling native shared libraries.")
    parser.add_argument("--wheel-file", required=True, help="Path to the input wheel file.")
    parser.add_argument("--wheel-name-file", help="Path to .whl.name file containing the real wheel name.")
    parser.add_argument("--wheel-directory", help="Path to a directory containing the wheel under its proper name.")
    parser.add_argument("--staging-dir", help="Directory to stage the wheel in before repair.")
    parser.add_argument("--output-dir", required=True, help="Directory where repairwheel writes the repaired wheel.")
    parser.add_argument("--out-wheel-file", required=True, help="Path where the output symlink should be created.")
    parser.add_argument(
        "--out-wheel-name-file", required=True, help="Path where the output wheel name should be written."
    )
    parser.add_argument(
        "--out-wheel-dir-basename", required=True, help="Basename of the output wheel directory (for relative symlink)."
    )
    parser.add_argument(
        "--lib-dir", action="append", default=[], help="Library directory for repairwheel (can be repeated)."
    )
    parser.add_argument("--target-environment", help="Path to target environment JSON for compatibility check.")

    args = parser.parse_args()

    # Determine the wheel file to pass to repairwheel.
    if args.wheel_directory:
        # When input is a directory, find the .whl inside it.
        whl_files = glob.glob(os.path.join(args.wheel_directory, "*.whl"))
        if not whl_files:
            print("ERROR: No .whl file found in wheel directory: " + args.wheel_directory, file=sys.stderr)
            sys.exit(1)
        wheel_file = whl_files[0]
    elif args.wheel_name_file:
        # Stage the wheel under its real name so repairwheel can parse the filename.
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

    # Build the repairwheel command.
    lib_paths = [str(Path(p).absolute()) for p in args.lib_dir]

    cmd = [
        sys.executable,
        "-m",
        "repairwheel",
        wheel_file,
        "--output-dir",
        args.output_dir,
        "--no-sys-paths",
    ]

    for lp in lib_paths:
        cmd.extend(["--lib-dir", lp])

    env = os.environ.copy()
    python_path = list(sys.path)
    # Prepend user-provided repairwheel paths so they shadow the bundled version.
    extra = os.environ.get("REPAIRWHEEL_PYTHONPATH", "")
    if extra:
        python_path = extra.split(os.pathsep) + python_path
    env["PYTHONPATH"] = os.pathsep.join(python_path)
    subprocess.check_call(cmd, env=env)

    # Perform target environment tag compatibility verification if specified.
    if args.target_environment:
        import json

        from packaging.utils import parse_wheel_filename

        target_env_path = Path(args.target_environment)
        if target_env_path.exists():
            with open(target_env_path, "r") as f:
                target_env_data = json.load(f)
            compatibility_tags = set(target_env_data.get("compatibility_tags", []))

            # Scan output directory for the final output wheel.
            repaired_wheels = list(Path(args.output_dir).glob("*.whl"))
            if not repaired_wheels:
                print("ERROR: No output wheel found in repaired output directory", file=sys.stderr)
                sys.exit(1)
            output_wheel_file = repaired_wheels[0]

            # Extract tags from output wheel name and convert them to strings.
            _, _, _, output_tag_objects = parse_wheel_filename(output_wheel_file.name)
            output_tags = {str(t) for t in output_tag_objects}

            # Verify tag intersection.
            if not output_tags.intersection(compatibility_tags):
                print(
                    f"ERROR: Built wheel {output_wheel_file.name} has incompatible tags: {output_tags}",
                    file=sys.stderr,
                )
                print(
                    f"Target environment requires compatible tags from list of size {len(compatibility_tags)}",
                    file=sys.stderr,
                )
                sys.exit(1)

            print(f"Target compatibility check successful for: {output_wheel_file.name}")

    # Collect output: find the repaired wheel in the output directory.
    output_dir = Path(args.output_dir)
    whl_files = sorted(output_dir.glob("*.whl"))
    if not whl_files:
        print("ERROR: No .whl file found in repair output", file=sys.stderr)
        sys.exit(1)
    repaired_wheel = whl_files[0]

    # Create a relative symlink from out_wheel_file -> <out_wheel_dir_basename>/<wheel_name>.
    symlink_target = os.path.join(args.out_wheel_dir_basename, repaired_wheel.name)
    os.symlink(symlink_target, args.out_wheel_file)

    # Write the wheel basename to the name file.
    with open(args.out_wheel_name_file, "w") as f:
        f.write(repaired_wheel.name)


if __name__ == "__main__":
    main()
