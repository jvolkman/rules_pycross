"""Extract a native binary from a wheel's bin/ directory.

Used by tool_extract.bzl to pull executables (e.g. ninja) out of
wheel TreeArtifacts so they can be placed on PATH during builds.

Usage: extract_wheel_bin.py <wheel_dir> <binary_name> <out_file>
"""

import os
import shutil
import sys


def main():
    wheel_dir = sys.argv[1]
    binary_name = sys.argv[2]
    out_file = sys.argv[3]

    src = os.path.join(wheel_dir, "bin", binary_name)
    shutil.copyfile(src, out_file)
    os.chmod(out_file, 0o755)


if __name__ == "__main__":
    main()
