#!/bin/bash
set -euo pipefail

# Find the workspace root by resolving the physical path of this script
SCRIPT_PATH=$(readlink -f "$0")
E2E_DIR=$(dirname "$SCRIPT_PATH")
WORKSPACE_ROOT=$(dirname $(dirname "$E2E_DIR"))

WORKSPACE_DIR="${WORKSPACE_ROOT}/$1"
echo "Running Bazel integration test in ${WORKSPACE_DIR}..."

if [[ ! -d "${WORKSPACE_DIR}" ]]; then
  echo "Error: Directory ${WORKSPACE_DIR} does not exist."
  exit 1
fi

# Bazel sets these variables during test execution. 
# They must be unset so the nested Bazel does not get confused.
unset TEST_TMPDIR
unset TEST_WORKSPACE
unset TEST_SRCDIR

# Use the default output base (usually ~/.cache/bazel) to persist caches across runs,
# which avoids re-downloading toolchains and improves performance.
# We also leave the daemon running as requested to preserve the in-memory graph.
cd "${WORKSPACE_DIR}"
echo "Running bazel build //..."
bazel build //...
echo "Running bazel test //..."
bazel test //... || exit_code=$?

if [[ -n "${exit_code:-}" && "${exit_code}" != 4 ]]; then
  exit $exit_code
fi
