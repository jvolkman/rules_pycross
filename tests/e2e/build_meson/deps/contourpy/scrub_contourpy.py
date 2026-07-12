"""Custom post-build hook to scrub contourpy build config.

Scrubs paths and host CPU/OS metadata for reproducibility.
"""

import os
import re
import sys
import zipfile
from pathlib import Path


def main():
    wheel_file = Path(os.environ["PYCROSS_WHEEL_FILE"])
    output_dir = Path(os.environ["PYCROSS_WHEEL_OUTPUT_DIR"])
    prefix = os.environ["PYCROSS_BAZEL_ROOT"]

    prefix_with_slash = prefix + "/"
    bazel_out_re = re.compile(r"bazel-out/[^/]+/bin/")
    external_re = re.compile(r"external/")

    # Regex to match build machine info
    build_cpu_re = re.compile(r'(build_cpu=")[^"]+(")')
    build_cpu_family_re = re.compile(r'(build_cpu_family=")[^"]+(")')
    build_cpu_system_re = re.compile(r'(build_cpu_system=")[^"]+(")')

    output_wheel = output_dir / wheel_file.name
    modified = False

    target_file = "contourpy/util/_build_config.py"

    with zipfile.ZipFile(wheel_file, "r") as zin, zipfile.ZipFile(output_wheel, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename == target_file:
                text = data.decode("utf-8")

                # Scrub paths
                text = text.replace(prefix_with_slash, "")
                text = text.replace(prefix, "")
                text = bazel_out_re.sub("", text)
                text = external_re.sub("", text)

                # Scrub build machine metadata
                text = build_cpu_re.sub(r"\1redacted\2", text)
                text = build_cpu_family_re.sub(r"\1redacted\2", text)
                text = build_cpu_system_re.sub(r"\1redacted\2", text)

                data = text.encode("utf-8")
                modified = True
                print(f"Scrubbed build paths and metadata from {info.filename}", file=sys.stderr)
            zout.writestr(info, data)

    if modified:
        print(f"Wrote scrubbed wheel to {output_wheel}", file=sys.stderr)
    else:
        print(f"No matching files found to scrub in {wheel_file.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
