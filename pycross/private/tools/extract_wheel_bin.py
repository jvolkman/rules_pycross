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
