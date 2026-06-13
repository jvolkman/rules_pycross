"""Copy a file into a Bazel TreeArtifact directory.

Used by wheel_dir.bzl to wrap a .whl file into a TreeArtifact.
Bazel pre-creates the output directory for declared TreeArtifacts,
so we copy the source file into it by name.

Usage: copy_file.py <src> <dest_dir>
"""

import os
import shutil
import sys


def main():
    src = sys.argv[1]
    dst_dir = sys.argv[2]
    shutil.copy2(src, os.path.join(dst_dir, os.path.basename(src)))


if __name__ == "__main__":
    main()
