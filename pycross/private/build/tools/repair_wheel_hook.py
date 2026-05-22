import os
import subprocess
import sys
from pathlib import Path


def main() -> None:
    lib_path_env = os.environ.get("PYCROSS_LIBRARY_PATH", "")
    lib_path = [Path(p).absolute() for p in lib_path_env.split(os.pathsep) if p]

    wheel_file = Path(os.environ["PYCROSS_WHEEL_FILE"])
    output_dir = Path(os.environ["PYCROSS_WHEEL_OUTPUT_ROOT"])

    args = [
        sys.executable,
        "-m",
        "repairwheel",
        str(wheel_file),
        "--output-dir",
        str(output_dir),
        "--no-sys-paths",
    ]

    for lp in lib_path:
        args.extend(["--lib-dir", str(lp)])

    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(sys.path)
    subprocess.check_call(args, env=env)

    # Perform target environment tag compatibility verification if specified
    target_env_path_str = os.environ.get("PYCROSS_TARGET_ENVIRONMENT")
    if target_env_path_str:
        import json

        from packaging.utils import parse_wheel_filename

        target_env_path = Path(target_env_path_str)
        if target_env_path.exists():
            with open(target_env_path, "r") as f:
                target_env_data = json.load(f)
            compatibility_tags = set(target_env_data.get("compatibility_tags", []))

            # Scan output directory for the final output wheel
            repaired_wheels = list(output_dir.glob("*.whl"))
            if not repaired_wheels:
                print("ERROR: No output wheel found in repaired output directory", file=sys.stderr)
                sys.exit(1)
            output_wheel_file = repaired_wheels[0]

            # Extract tags from output wheel name and convert them to strings
            _, _, _, output_tag_objects = parse_wheel_filename(output_wheel_file.name)
            output_tags = {str(t) for t in output_tag_objects}

            # Verify tag intersection
            if not output_tags.intersection(compatibility_tags):
                print(
                    f"ERROR: Built wheel {output_wheel_file.name} has incompatible tags: {output_tags}", file=sys.stderr
                )
                print(
                    f"Target environment requires compatible tags from list of size {len(compatibility_tags)}",
                    file=sys.stderr,
                )
                sys.exit(1)

            print(f"Target compatibility check successful for: {output_wheel_file.name}")


if __name__ == "__main__":
    main()
