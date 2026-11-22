"""Extract an executable (native binary or console script) from a wheel's bin/ directory.

Used by tool_extract.bzl to pull executables (e.g. cmake, meson, ninja) out of
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
    if not os.path.isfile(src) and os.path.isfile(src + ".exe"):
        src = src + ".exe"

    if os.path.lexists(out_file):
        try:
            os.chmod(out_file, 0o644)
        except OSError:
            pass
        os.unlink(out_file)

    # wheel_installer.py installs POSIX console scripts with the placeholder
    # shebang `#!python`. Rewrite it to `#!/usr/bin/env python3` so tools that
    # re-invoke themselves by sys.argv[0] (e.g. meson via ninja) remain directly
    # executable instead of failing with `python: bad interpreter`.
    with open(src, "rb") as src_f:
        header = src_f.read(11)
        if header.startswith(b"#!python\n"):
            remainder = header[len(b"#!python\n") :]
            with open(out_file, "wb") as dst_f:
                dst_f.write(b"#!/usr/bin/env python3\n")
                dst_f.write(remainder)
                shutil.copyfileobj(src_f, dst_f)
            os.chmod(out_file, 0o755)
            return
        if header.startswith(b"#!python\r\n"):
            remainder = header[len(b"#!python\r\n") :]
            with open(out_file, "wb") as dst_f:
                dst_f.write(b"#!/usr/bin/env python3\n")
                dst_f.write(remainder)
                shutil.copyfileobj(src_f, dst_f)
            os.chmod(out_file, 0o755)
            return

    shutil.copyfile(src, out_file)
    os.chmod(out_file, 0o755)


if __name__ == "__main__":
    main()
