#!/bin/bash
# e2e/build_and_test_all.sh — build and test all e2e workspaces locally
# Use this for native testing (no cross-compilation flags)
set -e
cd "$(dirname "$0")"

for ws in build_*/; do
  ws="${ws%/}"
  echo "═══ Building $ws ═══"
  (cd "$ws" && bazel build "$@" -- //... -//tests/...)
  echo "═══ Testing $ws ═══"
  (cd "$ws" && bazel test //tests/... "$@")
done
echo "═══ All e2e tests passed ═══"
