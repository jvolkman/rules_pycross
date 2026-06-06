#!/bin/bash
# e2e/build_all.sh — build all e2e workspaces locally
# Use this when testing cross-compilation (e.g. passing --platforms)
set -e
cd "$(dirname "$0")"

for ws in build_*/; do
  ws="${ws%/}"
  echo "═══ Building $ws ═══"
  (cd "$ws" && bazel build "$@" //:all_wheels)
done
echo "═══ All e2e builds passed ═══"
