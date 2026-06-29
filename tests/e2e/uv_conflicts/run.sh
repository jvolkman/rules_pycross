#!/bin/bash
set -euo pipefail

# Build all aliases (this verifies the lock repo works without testing the python scripts directly)
# This uses the variant-a flag to satisfy typing-extensions select().
# group-a is the default (via default-groups), so idna doesn't need explicit flags.
bazel build "$@" //... --@project//_variants:extra_variant-a=True

# Test variant A
echo "Testing Variant A..."
bazel test "$@" //:test_variant_a --@project//_variants:extra_variant-a=True --test_output=errors

# Test variant B
echo "Testing Variant B..."
bazel test "$@" //:test_variant_b --@project//_variants:extra_variant-b=True --test_output=errors

# Test that default-groups makes group-a the default for idna.
# This exercises the default_variants code path in thin_package_repo.bzl:
# the select() should have a //conditions:default entry pointing to idna 3.7.
echo "Testing default group (idna should be 3.7 without flags)..."
bazel test "$@" //:test_default_group --@project//_variants:extra_variant-a=True --test_output=errors

# Verify error without flags for extras (which have no default)
echo "Testing without flags (should fail for extras)..."
if bazel build "$@" //:test_variant_a >/dev/null 2>&1; then
  echo "Expected build to fail without flags!"
  exit 1
fi
echo "Failed as expected."

# Test platform transition: @project_pinned has variant-a pinned via flags on the member import.
# This should resolve typing-extensions 4.11.0 without any --flag arguments.
echo "Testing platform transition (variant-a pinned via flags)..."
bazel test "$@" //:test_transition_pinned --test_output=errors
echo "Platform transition test passed."
