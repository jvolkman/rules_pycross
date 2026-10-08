import argparse
import hashlib
import shutil
import sys
from pathlib import Path


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _copy_or_verify(src: Path, dst: Path) -> None:
    if dst.exists():
        if _sha256(src) != _sha256(dst):
            print(
                f"Error: Wheel {dst.name} differs across target platforms: {src} vs {dst}",
                file=sys.stderr,
            )
            sys.exit(1)
        return
    shutil.copy2(src, dst)


def collect_wheels(out_dir: Path, wheel_args: list[str]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    for wheel_str in wheel_args:
        for p in wheel_str.split(" "):
            if not p:
                continue
            wheel_path = Path(p)

            # TreeArtifact: a directory containing .whl files
            if wheel_path.is_dir():
                for whl in wheel_path.glob("*.whl"):
                    real_path = whl.resolve()
                    target_path = out_dir / real_path.name
                    _copy_or_verify(real_path, target_path)
                continue

            if not wheel_path.name.endswith(".whl"):
                continue

            real_path = wheel_path.resolve()
            target_path = out_dir / real_path.name
            _copy_or_verify(real_path, target_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("wheel", nargs="*", default=[])
    args = parser.parse_args()

    collect_wheels(Path(args.out_dir), args.wheel)


if __name__ == "__main__":
    main()
