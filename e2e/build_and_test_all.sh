#!/bin/bash
# e2e/build_and_test_all.sh — build and test all e2e workspaces locally
# Use this for native testing (no cross-compilation flags)
set -e
cd "$(dirname "$0")"

WORKSPACES=(build_meson build_setuptools build_maturin build_pure_python build_cmake)
for ws in "${WORKSPACES[@]}"; do
  echo "═══ Building $ws ═══"
  (cd "$ws" && bazel build "$@" -- //... -//tests/...)
  echo "═══ Testing $ws ═══"
  (cd "$ws" && bazel test //tests/... "$@")
done
echo "═══ All e2e tests passed ═══"
