"""Link or copy a wheel file to a stable destination.

If the source is a directory, it scans for a single .whl file inside.
If the source is a file, it uses it directly.
"""

import glob
import os
import shutil
import sys


def main():
    if len(sys.argv) != 3:
        print("Usage: link_wheel.py <src_file_or_dir> <dst_file>", file=sys.stderr)
        sys.exit(1)

    src = sys.argv[1]
    dst = sys.argv[2]

    if os.path.isdir(src):
        wheels = glob.glob(os.path.join(src, "*.whl"))
        if not wheels:
            print(f"Error: No .whl files found in {src}", file=sys.stderr)
            sys.exit(1)
        if len(wheels) > 1:
            print(f"Error: Multiple .whl files found in {src}: {wheels}", file=sys.stderr)
            sys.exit(1)
        src_file = wheels[0]
    else:
        src_file = src

    # Ensure destination directory exists
    dst_dir = os.path.dirname(dst)
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)

    # Try to symlink first, fallback to copy
    try:
        if os.path.lexists(dst):
            os.unlink(dst)
        rel_src = os.path.relpath(src_file, os.path.dirname(dst))
        os.symlink(rel_src, dst)
    except OSError:
        shutil.copy2(src_file, dst)


if __name__ == "__main__":
    main()
