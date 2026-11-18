"""Copy a library out of an installed wheel's site-packages so it can be linked.

Used by pycross_wheel_cc_import. The copy is a regular file, because link and
repair actions stage it without the wheel's TreeArtifact.

Usage: extract_wheel_lib.py <site_packages_tree> <path_in_site_packages> <attr_name> <out_file>
"""

import os
import shutil
import sys


def main():
    tree, rel_path, attr_name, out_file = sys.argv[1:5]
    src = os.path.join(tree, "site-packages", rel_path)
    if not os.path.isfile(src):
        sys.exit(f"error: {attr_name} '{rel_path}' is not a file in the wheel's site-packages")
    # A stale output from a local run may be read-only.
    if os.path.lexists(out_file):
        os.unlink(out_file)
    shutil.copyfile(src, out_file)


if __name__ == "__main__":
    main()
