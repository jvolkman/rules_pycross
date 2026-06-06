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

# Setup a clean output base to avoid collision with the outer Bazel server.
OUTPUT_BASE=$(mktemp -d)
trap 'cd "${WORKSPACE_DIR}" && bazel --output_base="${OUTPUT_BASE}" shutdown; chmod -R u+w "${OUTPUT_BASE}" && rm -rf "${OUTPUT_BASE}"' EXIT
cd "${WORKSPACE_DIR}"
echo "Running bazel build //..."
bazel --output_base="${OUTPUT_BASE}" build //...
echo "Running bazel test //..."
bazel --output_base="${OUTPUT_BASE}" test //... || exit_code=$?

if [[ -n "${exit_code:-}" && "${exit_code}" != 4 ]]; then
  exit $exit_code
fi
