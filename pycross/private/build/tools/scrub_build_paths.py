"""Post-build hook to scrub sandbox paths from specific files inside a wheel.

Usage: Set the following environment variables before invoking this hook:
  PYCROSS_WHEEL_FILE       - Path to the wheel file to process.
  PYCROSS_WHEEL_OUTPUT_DIR - Directory to write the modified wheel to.
  PYCROSS_BAZEL_ROOT       - The sandbox prefix to strip.
  PYCROSS_SCRUB_PATHS      - Comma-separated list of file paths within the wheel
                             to scrub (e.g. "numpy/__config__.py,contourpy/util/_build_config.py").

The hook strips absolute sandbox paths, Bazel output directory prefixes
(bazel-out/<config>/bin/), and external/ prefixes from the specified files,
making build metadata reproducible across different build hosts.
"""

import os
import re
import shutil
import sys
import zipfile
from pathlib import Path


def main():
    wheel_file = Path(os.environ["PYCROSS_WHEEL_FILE"])
    output_dir = Path(os.environ["PYCROSS_WHEEL_OUTPUT_DIR"])
    prefix = os.environ["PYCROSS_BAZEL_ROOT"]
    scrub_paths_raw = os.environ.get("PYCROSS_SCRUB_PATHS", "")

    if not scrub_paths_raw:
        print("PYCROSS_SCRUB_PATHS not set, nothing to scrub", file=sys.stderr)
        shutil.copy2(str(wheel_file), str(output_dir / wheel_file.name))
        return

    scrub_paths = {p.strip() for p in scrub_paths_raw.split(",") if p.strip()}
    prefix_with_slash = prefix + "/"
    bazel_out_re = re.compile(r"bazel-out/[^/]+/bin/")
    external_re = re.compile(r"external/")

    output_wheel = output_dir / wheel_file.name
    modified = False

    with zipfile.ZipFile(wheel_file, "r") as zin, zipfile.ZipFile(output_wheel, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename in scrub_paths:
                text = data.decode("utf-8")
                text = text.replace(prefix_with_slash, "")
                text = text.replace(prefix, "")
                text = bazel_out_re.sub("", text)
                text = external_re.sub("", text)
                data = text.encode("utf-8")
                modified = True
                print(f"Scrubbed build paths from {info.filename}", file=sys.stderr)
            zout.writestr(info, data)

    if modified:
        print(f"Wrote scrubbed wheel to {output_wheel}", file=sys.stderr)
    else:
        print(f"No matching files found to scrub in {wheel_file.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
