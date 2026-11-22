"""Extract an executable (native binary or console script) from a wheel's bin/ directory.

Used by tool_extract.bzl to pull executables (e.g. cmake, meson, ninja) out of
wheel TreeArtifacts so they can be placed on PATH during builds.

Usage: extract_wheel_bin.py <wheel_dir> <binary_name> <out_file>
"""

import os
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

    with open(src, "rb") as f:
        data = f.read()

    # wheel_installer.py installs POSIX console scripts with the placeholder
    # shebang `#!python`. Rewrite it to `#!/usr/bin/env python3` so tools that
    # re-invoke themselves by sys.argv[0] (e.g. meson via ninja) remain directly
    # executable instead of failing with `python: bad interpreter`.
    if data.startswith(b"#!python\n"):
        data = b"#!/usr/bin/env python3\n" + data[len(b"#!python\n") :]
    elif data.startswith(b"#!python\r\n"):
        data = b"#!/usr/bin/env python3\n" + data[len(b"#!python\r\n") :]

    with open(out_file, "wb") as f:
        f.write(data)
    os.chmod(out_file, 0o755)


if __name__ == "__main__":
    main()
