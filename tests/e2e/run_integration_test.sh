#!/bin/bash
set -euo pipefail

# Find the workspace root by resolving the physical path of this script
SCRIPT_PATH=$(readlink -f "$0")
E2E_DIR=$(dirname "$SCRIPT_PATH")
WORKSPACE_ROOT=$(dirname $(dirname "$E2E_DIR"))

WORKSPACE_DIR="${WORKSPACE_ROOT}/$1"
echo "Running Bazel integration test in ${WORKSPACE_DIR}..."
echo "DEBUG: RULES_PYCROSS_DEBUG=${RULES_PYCROSS_DEBUG:-}"

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
echo "Running bazel clean --expunge..."
bazel clean --expunge
# If a workspace provides an executable run.sh, use it instead of the default build/test commands.
# This serves as an escape hatch for tests that require specific bazel invocation flags.
if [[ -x "run.sh" ]]; then
  echo "Running custom run.sh..."
  ./run.sh
else
  BAZEL_ARGS=()
  if [ -n "${RULES_PYCROSS_DEBUG:-}" ]; then
    BAZEL_ARGS+=("--action_env=RULES_PYCROSS_DEBUG=1")
    BAZEL_ARGS+=("--remote_accept_cached=false")
    BAZEL_ARGS+=("--nouse_action_cache")
  fi
  echo "Running bazel build //..."
  bazel build "${BAZEL_ARGS[@]}" //...
  # Query if there are any test targets in the workspace
  if bazel query "tests(//...)" --output=label 2>/dev/null | grep -q .; then
    echo "Running bazel test //..."
    bazel test "${BAZEL_ARGS[@]}" //...
  else
    echo "No test targets found, skipping bazel test."
  fi
fi
