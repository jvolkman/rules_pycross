#!/bin/bash
set -euo pipefail

bazel build "$@" //...
bazel test "$@" //... --test_output=errors

# A file that no index lists must fail with an error naming every index tried.
echo "Testing that a missing file fails..."
if out=$(bazel build "$@" @file_not_found//file 2>&1); then
  echo "Expected @file_not_found to fail!"
  exit 1
fi
for expected in "was not found in any index" "/index/missing: could not fetch" "/index/mismatch: listed with sha256"; do
  if ! grep -qF "$expected" <<<"$out"; then
    echo "Expected error output to contain: $expected"
    echo "$out"
    exit 1
  fi
done
echo "Failed as expected."
