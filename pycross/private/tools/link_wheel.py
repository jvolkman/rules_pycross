"""Copy a wheel file from a wheel directory to a stable destination."""

import glob
import os
import shutil
import sys


def main():
    if len(sys.argv) != 3:
        print("Usage: link_wheel.py <src_dir> <dst_file>", file=sys.stderr)
        sys.exit(1)

    src = sys.argv[1]
    dst = sys.argv[2]

    wheels = glob.glob(os.path.join(src, "*.whl"))
    if not wheels:
        print(f"Error: No .whl files found in {src}", file=sys.stderr)
        sys.exit(1)
    if len(wheels) > 1:
        print(f"Error: Multiple .whl files found in {src}: {wheels}", file=sys.stderr)
        sys.exit(1)
    src_file = wheels[0]

    # Ensure destination directory exists
    dst_dir = os.path.dirname(dst)
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)

    # Copy rather than symlink so Bazel path mapping does not bake
    # configuration-stripped paths into a relative symlink target.
    if os.path.lexists(dst):
        os.unlink(dst)
    shutil.copy2(src_file, dst)


if __name__ == "__main__":
    main()
