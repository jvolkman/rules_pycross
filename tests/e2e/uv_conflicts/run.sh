#!/bin/bash
set -euo pipefail

# Build all aliases (this verifies the lock repo works without testing the python scripts directly)
# This uses the variant-a flag to satisfy typing-extensions select().
bazel build "$@" //... --@project//_variants:extra_variant-a=True

# Test variant A
echo "Testing Variant A..."
bazel test "$@" //:test_variant_a --@project//_variants:extra_variant-a=True --test_output=errors

# Test variant B
echo "Testing Variant B..."
bazel test "$@" //:test_variant_b --@project//_variants:extra_variant-b=True --test_output=errors

# Verify error without flags
echo "Testing without flags (should fail)..."
if bazel build "$@" //:test_variant_a >/dev/null 2>&1; then
  echo "Expected build to fail without flags!"
  exit 1
fi
echo "Failed as expected."
