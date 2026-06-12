#!/bin/bash
# Post-build hook: verify wheel file exists and modify it to add a marker.
set -euo pipefail

if [ ! -f "${PYCROSS_WHEEL_FILE:-}" ]; then
    echo "ERROR: PYCROSS_WHEEL_FILE not found" >&2
    exit 1
fi

if [ ! -d "${PYCROSS_WHEEL_OUTPUT_DIR:-}" ]; then
    echo "ERROR: PYCROSS_WHEEL_OUTPUT_DIR not found" >&2
    exit 1
fi

# Use python to append a marker file to the wheel and write it to the output dir.
python3 -c "
import zipfile
import os
import shutil

wheel_in = os.environ['PYCROSS_WHEEL_FILE']
out_dir = os.environ['PYCROSS_WHEEL_OUTPUT_DIR']
wheel_name = os.path.basename(wheel_in)
wheel_out = os.path.join(out_dir, wheel_name)

print(f'Post-build hook: Modifying wheel {wheel_in} -> {wheel_out}')

with zipfile.ZipFile(wheel_in, 'r') as yin:
    with zipfile.ZipFile(wheel_out, 'w', compression=zipfile.ZIP_DEFLATED) as yout:
        for item in yin.infolist():
            yout.writestr(item, yin.read(item.filename))
        # Add our marker file inside the package directory
        yout.writestr('setproctitle/POST_BUILD_HOOK_MARKER.txt', 'post_build_hook_was_here')
"

echo "Post-build hook completed successfully."
