#!/usr/bin/env bash
# Runs //:test_import_index, which needs a rules_python with --venv_import_index (prototype).
#
#   RULES_PYTHON=<rules_python checkout> ./run_import_index.sh [scan|prebuilt] [bazel args...]
set -euo pipefail
cd "$(dirname "$0")"
: "${RULES_PYTHON:?set RULES_PYTHON to a rules_python checkout that has --venv_import_index}"
mode="${1:-scan}"
shift || true
bazel test //:test_import_index \
    --override_module=rules_python="$RULES_PYTHON" \
    --@rules_python//python/config_settings:bootstrap_impl=script \
    --@rules_python//python/config_settings:venv_import_index="$mode" \
    --test_output=errors \
    "$@"
