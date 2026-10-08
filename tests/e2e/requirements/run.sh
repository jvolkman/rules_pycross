#!/bin/bash
set -euo pipefail

bazel build "$@" //...
bazel test "$@" //...

# rerun-sdk 0.33.0 has no macOS x86_64 wheel and no sdist, so it is unavailable on
# //unavailable:macos_x86_64. The checks are scoped to //unavailable/... because the root py_tests
# can't be configured for a target platform that isn't an execution platform.
PLATFORM=--platforms=//unavailable:macos_x86_64
FAIL_AT_EXECUTION=--@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution
log=$(mktemp)
trap 'rm -f "$log"' EXIT

echo "fail_at_execution: targets that don't need rerun-sdk still build..."
bazel build "$@" "$PLATFORM" "$FAIL_AT_EXECUTION" -- //unavailable/... -//unavailable:uses_rerun

echo "fail_at_execution: a target that needs rerun-sdk fails at execution..."
if bazel build "$@" "$PLATFORM" "$FAIL_AT_EXECUTION" //unavailable:uses_rerun >"$log" 2>&1; then
  cat "$log"
  echo "Expected //unavailable:uses_rerun to fail under fail_at_execution!"
  exit 1
fi
if ! grep -q "No compatible wheel is available for rerun-sdk@0.33.0" "$log"; then
  cat "$log"
  echo "Expected the package-specific unavailable message!"
  exit 1
fi

echo "incompatible (default): //unavailable/... skips the target, and building it explicitly reports incompatibility..."
bazel build "$@" "$PLATFORM" //unavailable/...
if bazel build "$@" "$PLATFORM" //unavailable:uses_rerun >"$log" 2>&1; then
  cat "$log"
  echo "Expected //unavailable:uses_rerun to be incompatible by default!"
  exit 1
fi
if ! grep -q "didn't satisfy constraint @@platforms//:incompatible" "$log"; then
  cat "$log"
  echo "Expected an incompatible-target error!"
  exit 1
fi
echo "unavailable_package_mode checks passed."
