#!/usr/bin/env bash
# Runs //:test_import_index and //:test_import_index_merged using rules_pycross's
# --@rules_pycross//pycross/settings:venv_import_index flag on stock rules_python.
#
#   ./run_import_index.sh [scan|prebuilt] [bazel args...]
set -euo pipefail
cd "$(dirname "$0")"
mode="${1:-prebuilt}"
shift || true
override_args=()
if [[ -n "${RULES_PYTHON:-}" ]]; then
    override_args+=(--override_module=rules_python="$RULES_PYTHON")
fi
targets=(//:test_import_index)
if [[ "$mode" == "prebuilt" ]]; then
    targets+=(//:test_import_index_merged)
fi
bazel test "${targets[@]}" \
    "${override_args[@]}" \
    --@rules_python//python/config_settings:bootstrap_impl=script \
    --@rules_pycross//pycross/settings:venv_import_index="$mode" \
    --test_output=errors \
    "$@"
