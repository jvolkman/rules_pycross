import argparse
import glob
import os
import subprocess
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Repair a Python wheel by bundling native shared libraries.")
    parser.add_argument("--wheel-dir", required=False, help="Path to input wheel directory.")
    parser.add_argument("--out-wheel-dir", required=False, help="Path to output wheel directory.")
    parser.add_argument(
        "--lib-dir", action="append", default=[], help="Library directory for repairwheel (can be repeated)."
    )
    parser.add_argument("--target-environment", help="Path to target environment JSON for compatibility check.")

    args = parser.parse_args()

    wheel_dir = args.wheel_dir
    out_wheel_dir = args.out_wheel_dir
    wheel_file = None

    if not wheel_dir:
        wheel_file_env = os.environ.get("PYCROSS_WHEEL_FILE")
        if wheel_file_env:
            wheel_file = Path(wheel_file_env)
            wheel_dir = str(wheel_file.parent)
        else:
            print("ERROR: --wheel-dir is required if PYCROSS_WHEEL_FILE is not set", file=sys.stderr)
            sys.exit(1)

    if not out_wheel_dir:
        out_wheel_dir = os.environ.get("PYCROSS_WHEEL_OUTPUT_DIR") or os.environ.get("PYCROSS_WHEEL_OUTPUT_ROOT")
        if not out_wheel_dir:
            print("ERROR: --out-wheel-dir is required if PYCROSS_WHEEL_OUTPUT_DIR is not set", file=sys.stderr)
            sys.exit(1)

    if not wheel_file:
        whl_files = glob.glob(os.path.join(wheel_dir, "*.whl"))
        if not whl_files:
            print("ERROR: No .whl file found in wheel directory: " + wheel_dir, file=sys.stderr)
            sys.exit(1)
        wheel_file = Path(whl_files[0])

    lib_dirs = args.lib_dir
    if not lib_dirs:
        lib_path_env = os.environ.get("PYCROSS_LIBRARY_PATH")
        if lib_path_env:
            lib_dirs = lib_path_env.split(os.pathsep)

    lib_paths = [str(Path(p).absolute()) for p in lib_dirs]

    cmd = [
        sys.executable,
        "-m",
        "repairwheel",
        str(wheel_file),
        "--output-dir",
        out_wheel_dir,
        "--no-sys-paths",
    ]

    for lp in lib_paths:
        cmd.extend(["--lib-dir", lp])

    env = os.environ.copy()
    for key in [
        "PYTHONSAFEPATH",
        "RUNFILES_DIR",
        "RUNFILES_MANIFEST_FILE",
        "RUNFILES_MANIFEST_ONLY",
    ]:
        env.pop(key, None)
    python_path = list(sys.path)
    extra = os.environ.get("REPAIRWHEEL_PYTHONPATH", "")
    if extra:
        python_path = extra.split(os.pathsep) + python_path
    env["PYTHONPATH"] = os.pathsep.join(python_path)
    subprocess.check_call(cmd, env=env)

    if args.target_environment:
        import json

        from packaging.utils import parse_wheel_filename

        target_env_path = Path(args.target_environment)
        if target_env_path.exists():
            with open(target_env_path, "r") as f:
                target_env_data = json.load(f)
            compatibility_tags = set(target_env_data.get("compatibility_tags", []))

            repaired_wheels = list(Path(out_wheel_dir).glob("*.whl"))
            if not repaired_wheels:
                print("ERROR: No output wheel found in repaired output directory", file=sys.stderr)
                sys.exit(1)
            output_wheel_file = repaired_wheels[0]

            _, _, _, output_tag_objects = parse_wheel_filename(output_wheel_file.name)
            output_tags = {str(t) for t in output_tag_objects}

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


if __name__ == "__main__":
    main()
