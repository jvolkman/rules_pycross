"""Custom post-build hook to scrub numpy build config.

Scrubs paths and host CPU/OS metadata for reproducibility.
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

    prefix_with_slash = prefix + "/"
    bazel_out_re = re.compile(r"bazel-out/[^/]+/bin/")
    external_re = re.compile(r"external/")

    # Regex to match toolchain minimal path in args
    toolchain_re = re.compile(r"llvm-toolchain-minimal-[^/]+")

    output_wheel = output_dir / wheel_file.name
    modified = False

    target_file = "numpy/__config__.py"

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
                
                # Scrub specific toolchain path differences
                text = toolchain_re.sub("llvm-toolchain-minimal-redacted", text)
                
                # Scrub build machine metadata
                # We want to scrub ONLY the "build" block under "Machine Information"
                # Simple state machine to find "build": { and scrub lines underneath
                lines = text.splitlines()
                in_build_block = False
                for i, line in enumerate(lines):
                    if '"build": {' in line:
                        in_build_block = True
                        continue
                    if in_build_block:
                        if '}' in line:
                            in_build_block = False
                            continue
                        # Redact cpu, family, system
                        if '"cpu":' in line:
                            lines[i] = re.sub(r'("cpu": ")[^"]+(")', r'\1redacted\2', line)
                        elif '"family":' in line:
                            lines[i] = re.sub(r'("family": ")[^"]+(")', r'\1redacted\2', line)
                        elif '"system":' in line:
                            lines[i] = re.sub(r'("system": ")[^"]+(")', r'\1redacted\2', line)
                
                text = "\n".join(lines) + "\n"
                
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
