import os
import shutil
import sys


def main():
    src = sys.argv[1]
    dst = sys.argv[2]

    make_executable = "--executable" in sys.argv

    # If the destination is a directory, copy into it.
    if os.path.isdir(dst):
        dst_file = os.path.join(dst, os.path.basename(src))
    else:
        dst_file = dst

    shutil.copyfile(src, dst_file)

    if make_executable:
        os.chmod(dst_file, 0o755)


if __name__ == "__main__":
    main()
