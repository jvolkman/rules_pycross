import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
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
    parser.add_argument("--wheel-dir", required=True, help="Path to input wheel directory.")
    parser.add_argument("--out-wheel-dir", required=True, help="Path to output wheel directory.")
    parser.add_argument(
        "--lib-dir", action="append", default=[], help="Library directory for repairwheel (can be repeated)."
    )
    parser.add_argument("--target-environment", help="Path to target environment JSON for compatibility check.")
    parser.add_argument(
        "--exclude", action="append", default=[], help="Shared library glob to exclude from repairwheel."
    )

    args = parser.parse_args()

    out_wheel_dir = args.out_wheel_dir
    whl_files = glob.glob(os.path.join(args.wheel_dir, "*.whl"))
    if not whl_files:
        print("ERROR: No .whl file found in wheel directory: " + args.wheel_dir, file=sys.stderr)
        sys.exit(1)
    wheel_file = Path(whl_files[0])

    target_env_data = None
    if args.target_environment:
        target_env_path = Path(args.target_environment)
        if target_env_path.exists():
            with open(target_env_path, "r") as f:
                target_env_data = json.load(f)

    extra = os.environ.get("REPAIRWHEEL_PYTHONPATH", "")

    # Pure-Python wheels (-none-any.whl) contain no native shared libraries to
    # audit or bundle, so canonicalize them in-process instead of spawning a
    # repairwheel subprocess (preserving deterministic zip metadata and RECORD
    # regeneration) unless a custom repairwheel override is set.
    if wheel_file.name.lower().endswith("-none-any.whl") and not extra:
        from repairwheel.wheel import write_canonical_wheel

        mtime = None
        if "SOURCE_DATE_EPOCH" in os.environ:
            try:
                epoch = int(os.environ["SOURCE_DATE_EPOCH"])
                mtime = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
            except ValueError:
                print(
                    f"ERROR: SOURCE_DATE_EPOCH value cannot be parsed as a number: {os.environ['SOURCE_DATE_EPOCH']}",
                    file=sys.stderr,
                )
                sys.exit(1)

        out_path = Path(out_wheel_dir)
        out_path.mkdir(parents=True, exist_ok=True)
        dest_wheel = out_path / wheel_file.name
        if wheel_file.resolve() == dest_wheel.resolve():
            with tempfile.TemporaryDirectory(prefix="repairwheel") as tmp_dir:
                staged = write_canonical_wheel(wheel_file, wheel_file, Path(tmp_dir), mtime=mtime)
                shutil.move(str(staged), str(dest_wheel))
        else:
            write_canonical_wheel(wheel_file, wheel_file, out_path, mtime=mtime)
    else:
        lib_paths = [str(Path(p).absolute()) for p in args.lib_dir]

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
        if extra:
            python_path = extra.split(os.pathsep) + python_path
        env["PYTHONPATH"] = os.pathsep.join(python_path)

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
            expected_tags = target_env_data.get("compatibility_tags", [])
            compatibility_tags = set(expected_tags)

            repaired_wheels = list(Path(out_wheel_dir).glob("*.whl"))
            if not repaired_wheels:
                print("ERROR: No output wheel found in repaired output directory", file=sys.stderr)
                sys.exit(1)
            output_wheel_file = repaired_wheels[0]

            _, _, _, output_tag_objects = parse_wheel_filename(output_wheel_file.name)
            output_tags = {str(t) for t in output_tag_objects}

            if not output_tags.intersection(compatibility_tags):
                sample_limit = 5
                sample = ", ".join(expected_tags[:sample_limit])
                if len(expected_tags) > sample_limit:
                    sample += f", ... ({len(expected_tags)} total)"
                print(
                    f"ERROR: Built wheel {output_wheel_file.name} has incompatible tags: {sorted(output_tags)}",
                    file=sys.stderr,
                )
                print(
                    f"Target environment expects one of: {sample or '<none>'}",
                    file=sys.stderr,
                )
                sys.exit(1)

            print(f"Target compatibility check successful for: {output_wheel_file.name}")


if __name__ == "__main__":
    main()
