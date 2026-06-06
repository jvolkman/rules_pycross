import argparse
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("wheel", nargs="*", default=[])
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for wheel_str in args.wheel:
        for p in wheel_str.split(" "):
            wheel_path = Path(p)
            if not wheel_path.name.endswith(".whl"):
                continue

            real_path = wheel_path.resolve()
            target_name = real_path.name

            target_path = out_dir / target_name
            if target_path.exists():
                continue

            shutil.copy2(real_path, target_path)


if __name__ == "__main__":
    main()
