#!/bin/bash
# Pre-build hook: set a marker env var to prove it ran.
set -euo pipefail

if [ -n "${PYCROSS_ENV_VARS_FILE:-}" ]; then
    # Add PRE_HOOK_MARKER to the build env JSON
    sed -i 's/}$/, "PRE_HOOK_MARKER": "pre_hook_was_here"}/' "$PYCROSS_ENV_VARS_FILE"
fi

# Append build env vars to setproctitle so we can verify them in tests
INIT_PY="pkg/setproctitle/__init__.py"
if [ -f "$INIT_PY" ]; then
    echo "Found $INIT_PY" >&2
    echo "V1_CUSTOM_VAR = \"${MY_CUSTOM_VAR:-NOT_FOUND}\"" >> "$INIT_PY"
    
    # Read the data file
    DATA_PATH="${PYCROSS_BAZEL_ROOT}/${MY_DATA_FILE:-}"
    if [ -f "${DATA_PATH:-}" ]; then
        DATA_VAL=$(cat "$DATA_PATH")
        echo "V1_DATA_CONTENT = \"${DATA_VAL}\"" >> "$INIT_PY"
    else
        echo "V1_DATA_CONTENT = \"DATA_FILE_NOT_FOUND_AT_${DATA_PATH}\"" >> "$INIT_PY"
    fi
fi

# Prepend code to setup.py so it runs BEFORE setup() is called.
# This verifies that the PEP 517 build subprocess environment has PRE_HOOK_MARKER,
# and that the renamed path tool is available on PATH.
SETUP_PY="setup.py"
if [ -f "$SETUP_PY" ]; then
    echo "Found $SETUP_PY, prepending verification code" >&2
    cat << 'EOF' > setup.py.tmp
import os
import shutil
init_py = "pkg/setproctitle/__init__.py"
if os.path.exists(init_py):
    with open(init_py, "a") as f:
        # Check PRE_HOOK_MARKER
        val = os.environ.get("PRE_HOOK_MARKER", "NOT_FOUND_IN_ENV")
        f.write(f"V1_PRE_HOOK_MARKER = \"{val}\"\n")
        
        # Check if my_pre_hook_on_path is on PATH
        has_tool = shutil.which("my_pre_hook_on_path") is not None
        f.write(f"V1_HAS_PATH_TOOL = {has_tool}\n")
EOF
    cat "$SETUP_PY" >> setup.py.tmp
    mv setup.py.tmp "$SETUP_PY"
fi
