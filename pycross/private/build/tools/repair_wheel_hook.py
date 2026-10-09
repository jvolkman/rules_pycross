import argparse
import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable
from typing import Optional

_LINUX_PLAT_RE = re.compile(r"^(musllinux|manylinux)_(\d+)_(\d+)_\w+$")


def auditwheel_plat_from_tags(compatibility_tags: Iterable[str]) -> Optional[str]:
    """Pick the AUDITWHEEL_PLAT for repairwheel from the target's PEP 425 tags.

    repairwheel uses a musllinux_X_Y platform as both the libc and the musl
    policy, and any manylinux platform to mean glibc. Prefer the highest
    musllinux tag, then the highest manylinux tag.
    """
    best = {}
    for tag in compatibility_tags:
        platform = tag.rsplit("-", 1)[-1]
        m = _LINUX_PLAT_RE.match(platform)
        if not m:
            continue
        kind, version = m.group(1), (int(m.group(2)), int(m.group(3)))
        if kind not in best or version > best[kind][0]:
            best[kind] = (version, platform)
    for kind in ("musllinux", "manylinux"):
        if kind in best:
            return best[kind][1]
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Repair a Python wheel by bundling native shared libraries.")
    parser.add_argument("--wheel-dir", required=False, help="Path to input wheel directory.")
    parser.add_argument("--out-wheel-dir", required=False, help="Path to output wheel directory.")
    parser.add_argument(
        "--lib-dir", action="append", default=[], help="Library directory for repairwheel (can be repeated)."
    )
    parser.add_argument("--target-environment", help="Path to target environment JSON for compatibility check.")
    parser.add_argument(
        "--exclude", action="append", default=[], help="Shared library glob to exclude from repairwheel."
    )

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

    from pycross.private.build.tools.utils.env import make_clean_env

    for pattern in args.exclude:
        cmd.extend(["--exclude", pattern])

    env = make_clean_env()
    python_path = list(sys.path)
    extra = os.environ.get("REPAIRWHEEL_PYTHONPATH", "")
    if extra:
        python_path = extra.split(os.pathsep) + python_path
    env["PYTHONPATH"] = os.pathsep.join(python_path)

    target_env_data = None
    if args.target_environment:
        target_env_path = Path(args.target_environment)
        if target_env_path.exists():
            with open(target_env_path, "r") as f:
                target_env_data = json.load(f)

    # Tell repairwheel the target libc and musl policy up front; otherwise it
    # guesses from the input wheel and ignores the configured musl version.
    if target_env_data and "AUDITWHEEL_PLAT" not in env:
        plat = auditwheel_plat_from_tags(target_env_data.get("compatibility_tags", []))
        if plat:
            env["AUDITWHEEL_PLAT"] = plat

    subprocess.check_call(cmd, env=env)

    if args.target_environment:
        from packaging.utils import parse_wheel_filename

        if target_env_data is not None:
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
